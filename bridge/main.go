// agentbox-bridge: POC. One yamux pipe per box over `orb run`. mac-side accepts streams and dials ONE fixed target.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/hashicorp/yamux"
)

const boxListen = "127.0.0.1:8080"

const downMsg = "agent box: proxy is down, stop and tell the user"

var downReply = fmt.Sprintf("HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s", len(downMsg), downMsg)

var noteMu sync.Mutex

// recentlyNoted keeps last-notified times in a file, so the 60 s merge also holds across a bridge restart
// (a restarted process has an empty memory). Both boxes' bridges share the file; the message carries the box name.
func recentlyNoted(msg string) bool {
	noteMu.Lock()
	defer noteMu.Unlock()
	p := filepath.Join(dir, "notes.json") // not under status/: `status` reads every .json there as a box
	m := map[string]int64{}
	if b, err := os.ReadFile(p); err == nil {
		json.Unmarshal(b, &m)
	}
	now := time.Now().Unix()
	if t, ok := m[msg]; ok && now-t < 60 {
		return true
	}
	m[msg] = now
	for k, t := range m {
		if now-t > 3600 {
			delete(m, k)
		}
	}
	b, _ := json.Marshal(m)
	os.WriteFile(p+".tmp", b, 0o600)
	os.Rename(p+".tmp", p)
	return false
}

var dir = func() string {
	if d := os.Getenv("BRIDGE_DIR"); d != "" {
		return d
	}
	h, _ := os.UserHomeDir()
	return filepath.Join(h, "agent-boxes-bridge")
}()

// clean strips control characters and caps length: anything a box sent is hostile.
func clean(s string) string {
	s = strings.Map(func(r rune) rune {
		if r < 32 || r == 127 {
			return ' '
		}
		return r
	}, s)
	if len(s) > 200 {
		s = s[:200]
	}
	return s
}

var logMu sync.Mutex

func appendLine(name, line string) {
	logMu.Lock()
	defer logMu.Unlock()
	f, err := os.OpenFile(filepath.Join(dir, name), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err == nil {
		f.WriteString(line + "\n")
		f.Close()
	}
}

type mac struct {
	box, dialNet, dialAddr string
	maxStreams             int
	rate                   float64
	idle, life, dialTO     time.Duration
	cmd                    []string

	mu             sync.Mutex
	open, peak     int
	tokens         float64
	tokAt          time.Time
	opened, closed int64
	rej            map[string]int64
	up, down       atomic.Int64
	lastGood       time.Time
	misses         int
	restarts       int
	lastReason     string
	started        time.Time
	lastLimitNote  time.Time
	sess           *yamux.Session
	exiting        atomic.Bool
}

func (m *mac) event(ev string, kv ...any) {
	e := map[string]any{"time": time.Now().Format(time.RFC3339Nano), "box": m.box, "event": ev}
	for i := 0; i+1 < len(kv); i += 2 {
		if s, ok := kv[i+1].(string); ok {
			kv[i+1] = clean(s)
		}
		e[kv[i].(string)] = kv[i+1]
	}
	b, _ := json.Marshal(e)
	appendLine("bridge.log", string(b))
}

// notify passes the text as an argv item, never inside AppleScript source.
func notify(box, msg string) {
	msg = clean(box + ": " + msg)
	if recentlyNoted(msg) { // identical pop-ups merge for 60 s, same rule as the proxy
		return
	}
	appendLine("notifications.log", time.Now().Format(time.RFC3339)+"\t"+msg)
	exec.Command("osascript", "-e", "on run argv", "-e", `display notification (item 1 of argv) with title "agent box"`, "-e", "end run", "--", msg).Run()
}

type state struct {
	Restarts int    `json:"restarts"`
	Reason   string `json:"reason"`
	Running  bool   `json:"running"`
	NoteWhat string `json:"note_what"` // last notified failure, so a restart loop notifies once
	NoteAt   int64  `json:"note_at"`
}

func (m *mac) statePath() string { return filepath.Join(dir, "status", m.box+".state") }

func (m *mac) saveState(s state) {
	b, _ := json.Marshal(s)
	os.WriteFile(m.statePath(), b, 0o600)
}

func (m *mac) loadState() (s state, ok bool) {
	b, err := os.ReadFile(m.statePath())
	if err != nil || json.Unmarshal(b, &s) != nil {
		return s, false
	}
	return s, true
}

// die records why we exit, optionally notifies once, and exits so launchd restarts us.
func (m *mac) die(reason string, note bool) {
	if !m.exiting.CompareAndSwap(false, true) {
		select {}
	}
	m.event("exit", "reason", reason)
	s, _ := m.loadState()
	s.Reason, s.Running = reason, false
	if note && !(s.NoteWhat == reason && time.Now().Unix()-s.NoteAt < 600) {
		s.NoteWhat, s.NoteAt = reason, time.Now().Unix()
		notify(m.box, "bridge restarting: "+reason)
	}
	m.saveState(s)
	m.writeStatus(false)
	os.Exit(1)
}

func (m *mac) writeStatus(up bool) {
	m.mu.Lock()
	rej := map[string]int64{}
	var tot int64
	for k, v := range m.rej {
		rej[k] = v
		tot += v
	}
	v := map[string]any{
		"box": m.box, "up": up, "updated": time.Now().Unix(), "last_good": m.lastGood.Unix(),
		"open": m.open, "peak": m.peak, "opened": m.opened, "closed": m.closed,
		"rejected": tot, "rejected_by": rej, "up_bytes": m.up.Load(), "down_bytes": m.down.Load(),
		"restarts": m.restarts, "last_reason": m.lastReason, "pid": os.Getpid(),
	}
	m.mu.Unlock()
	b, _ := json.Marshal(v)
	p := filepath.Join(dir, "status", m.box+".json")
	os.WriteFile(p+".tmp", b, 0o600)
	os.Rename(p+".tmp", p)
}

func (m *mac) reject(why string) {
	m.mu.Lock()
	m.rej[why]++
	n := m.rej[why]
	note := time.Since(m.lastLimitNote) > time.Minute
	if note {
		m.lastLimitNote = time.Now()
	}
	m.mu.Unlock()
	m.event("reject", "reason", why, "total", n)
	if note {
		notify(m.box, "limit hit: "+why)
	}
}

func (m *mac) admit() (string, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := time.Now()
	m.tokens += now.Sub(m.tokAt).Seconds() * m.rate
	m.tokAt = now
	if m.tokens > m.rate {
		m.tokens = m.rate
	}
	if m.open >= m.maxStreams {
		return "max_streams", false
	}
	if m.tokens < 1 {
		return "rate", false
	}
	m.tokens--
	m.open++
	m.opened++
	if m.open > m.peak {
		m.peak = m.open
	}
	return "", true
}

type rwc struct {
	io.Reader
	io.Writer
	closers []io.Closer
}

func (r rwc) Close() error {
	for _, c := range r.closers {
		c.Close()
	}
	return nil
}

func ycfg() *yamux.Config {
	c := yamux.DefaultConfig()
	c.LogOutput = io.Discard
	return c
}

// halfClose ends our write side so the peer sees EOF but we can still read.
func halfClose(w io.Writer) {
	if cw, ok := w.(interface{ CloseWrite() error }); ok {
		cw.CloseWrite()
	} else if c, ok := w.(io.Closer); ok {
		c.Close()
	}
}

func (m *mac) handle(s *yamux.Stream) {
	why, ok := m.admit()
	if !ok {
		s.Close()
		m.reject(why)
		return
	}
	t0 := time.Now()
	reason := m.serve(s)
	m.mu.Lock()
	m.open--
	m.closed++
	m.mu.Unlock()
	m.event("stream_closed", "reason", reason, "ms", time.Since(t0).Milliseconds())
}

func (m *mac) serve(s *yamux.Stream) string {
	p, err := net.DialTimeout(m.dialNet, m.dialAddr, m.dialTO)
	if err != nil {
		s.Write([]byte(downReply)) // the box client gets a plain answer instead of a silent close
		s.Close()
		notify(m.box, "proxy is down: cannot reach the proxy socket")
		return "dial_fail"
	}
	var last atomic.Int64
	last.Store(time.Now().UnixNano())
	done := make(chan struct{}, 2)
	cp := func(dst io.Writer, src io.Reader, ctr *atomic.Int64) {
		buf := make([]byte, 32<<10)
		for {
			n, err := src.Read(buf)
			if n > 0 {
				if _, werr := dst.Write(buf[:n]); werr != nil {
					break
				}
				ctr.Add(int64(n))
				last.Store(time.Now().UnixNano())
			}
			if err != nil {
				break
			}
		}
		halfClose(dst)
		done <- struct{}{}
	}
	go cp(p, s, &m.up)
	go cp(s, p, &m.down)
	tick := time.NewTicker(time.Second)
	defer tick.Stop()
	var life <-chan time.Time // nil channel when -life is 0: no lifetime limit
	if m.life > 0 {
		life = time.After(m.life)
	}
	for left := 2; left > 0; {
		select {
		case <-done:
			left--
		case <-life:
			p.Close()
			s.Close()
			return "lifetime"
		case <-tick.C:
			if time.Since(time.Unix(0, last.Load())) > m.idle {
				p.Close()
				s.Close()
				return "idle"
			}
		}
	}
	p.Close()
	s.Close()
	return "eof"
}

type tail struct {
	mu sync.Mutex
	b  []byte
}

func (t *tail) Write(p []byte) (int, error) {
	t.mu.Lock()
	t.b = append(t.b, p...)
	if len(t.b) > 400 {
		t.b = t.b[len(t.b)-400:]
	}
	t.mu.Unlock()
	return len(p), nil
}

func (m *mac) run() {
	os.MkdirAll(filepath.Join(dir, "status"), 0o700)
	m.rej, m.started, m.tokAt, m.tokens = map[string]int64{}, time.Now(), time.Now(), m.rate
	st, had := m.loadState()
	switch {
	case !had:
		m.lastReason = "first start"
	case st.Running:
		m.lastReason = "unclean exit (killed)"
		notify(m.box, "bridge restarted after unclean exit")
	default:
		m.lastReason = st.Reason
	}
	if had {
		st.Restarts++
	}
	st.Running, st.Reason = true, ""
	m.restarts = st.Restarts
	m.saveState(st)
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGTERM, syscall.SIGINT)
	go func() { <-sig; m.die("stopped by signal", false) }()
	m.event("start", "restarts", m.restarts, "last_reason", m.lastReason, "dial", m.dialNet+":"+m.dialAddr)

	cmd := exec.Command(m.cmd[0], m.cmd[1:]...) // no pty: a pty would corrupt binary data
	stdin, _ := cmd.StdinPipe()
	stdout, _ := cmd.StdoutPipe()
	errTail := &tail{}
	cmd.Stderr = errTail
	if err := cmd.Start(); err != nil {
		m.die("cannot start box command: "+err.Error(), true)
	}
	boxErr := func() string {
		errTail.mu.Lock()
		defer errTail.mu.Unlock()
		return clean(string(errTail.b))
	}
	go func() { // box process ended: the pipe is gone
		cmd.Wait()
		m.die("box side exited: "+boxErr(), true)
	}()
	sess, err := yamux.Server(rwc{stdout, stdin, []io.Closer{stdin, stdout}}, ycfg())
	if err != nil {
		m.die("yamux: "+err.Error(), true)
	}
	m.sess = sess
	go func() { // statuses
		for range time.Tick(2 * time.Second) {
			m.writeStatus(true)
		}
	}()
	go m.health()
	go func() {
		<-sess.CloseChan()
		time.Sleep(200 * time.Millisecond) // let a box-side exit message win the race
		m.die("session closed: "+boxErr(), true)
	}()
	for {
		s, err := sess.AcceptStream()
		if err != nil {
			time.Sleep(200 * time.Millisecond)
			m.die("session error: "+err.Error()+" "+boxErr(), true)
		}
		go m.handle(s)
	}
}

func (m *mac) health() {
	prev := time.Now()
	next := time.Now().Add(time.Second)
	for first := true; ; first = false {
		time.Sleep(time.Until(next))
		if gap := time.Since(prev); !first && gap > 30*time.Second {
			m.event("gap", "seconds", int(gap.Seconds()))
		}
		prev = time.Now()
		next = prev.Add(10 * time.Second) // fixed 10 s cadence, even when a check times out
		if m.check() {
			if m.misses > 0 {
				m.event("health_recovered", "missed", m.misses)
			}
			m.misses = 0
			m.mu.Lock()
			m.lastGood = time.Now()
			m.mu.Unlock()
			m.event("health", "ok", true)
		} else {
			m.misses++
			m.event("health", "ok", false, "missed", m.misses)
			if m.misses >= 3 {
				m.die("3 health checks missed", true)
			}
		}
	}
}

// check asks the box side to GET /__health over its own listener, so the whole loop is exercised.
func (m *mac) check() bool {
	s, err := m.sess.OpenStream()
	if err != nil {
		return false
	}
	defer s.Close()
	s.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := s.Write([]byte("H")); err != nil {
		return false
	}
	b := make([]byte, 1)
	_, err = io.ReadFull(s, b)
	return err == nil && b[0] == '1'
}

func boxSide() {
	ln, err := net.Listen("tcp", boxListen)
	if err != nil {
		fmt.Fprintf(os.Stderr, "listen %s failed: %v\n", boxListen, err)
		os.Exit(3)
	}
	sess, err := yamux.Client(rwc{os.Stdin, os.Stdout, []io.Closer{os.Stdin, os.Stdout}}, ycfg())
	if err != nil {
		os.Exit(4)
	}
	go func() { // mac asks for a health round trip
		for {
			s, err := sess.AcceptStream()
			if err != nil {
				os.Exit(0)
			}
			go func() {
				defer s.Close()
				b := make([]byte, 1)
				if _, err := io.ReadFull(s, b); err != nil || b[0] != 'H' {
					return
				}
				ok := byte('0')
				if c, err := net.DialTimeout("tcp", boxListen, 2*time.Second); err == nil {
					c.SetDeadline(time.Now().Add(4 * time.Second))
					c.Write([]byte("GET /__health HTTP/1.0\r\nHost: localhost:8080\r\n\r\n"))
					r := make([]byte, 16)
					n, _ := io.ReadAtLeast(c, r, 12)
					if strings.HasPrefix(string(r[:n]), "HTTP/1.") && strings.Contains(string(r[:n]), " 200") {
						ok = '1'
					}
					c.Close()
				}
				s.Write([]byte{ok})
			}()
		}
	}()
	go func() { <-sess.CloseChan(); os.Exit(0) }()
	for {
		c, err := ln.Accept()
		if err != nil {
			continue
		}
		go func() {
			s, err := sess.OpenStream()
			if err != nil {
				c.Close()
				return
			}
			done := make(chan struct{}, 2)
			go func() { io.Copy(s, c); halfClose(s); done <- struct{}{} }()
			go func() { io.Copy(c, s); halfClose(c); done <- struct{}{} }()
			<-done
			<-done
			c.Close()
			s.Close()
		}()
	}
}

func status() {
	fs, _ := filepath.Glob(filepath.Join(dir, "status", "*.json"))
	sort.Strings(fs)
	for _, f := range fs {
		var v map[string]any
		b, _ := os.ReadFile(f)
		if json.Unmarshal(b, &v) != nil {
			continue
		}
		num := func(k string) int64 { n, _ := v[k].(float64); return int64(n) }
		up := "down"
		if v["up"] == true && time.Now().Unix()-num("updated") < 6 {
			up = "up"
		}
		lg := "never"
		if num("last_good") > 0 {
			lg = time.Unix(num("last_good"), 0).Format("15:04:05")
		}
		fmt.Printf("%s %s last_good=%s open=%d peak=%d opened=%d closed=%d rejected=%d bytes_up=%d bytes_down=%d restarts=%d last_restart=%q\n",
			v["box"], up, lg, num("open"), num("peak"), num("opened"), num("closed"), num("rejected"),
			num("up_bytes"), num("down_bytes"), num("restarts"), v["last_reason"])
	}
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: agentbox-bridge mac-side|box-side|status")
		os.Exit(2)
	}
	switch os.Args[1] {
	case "box-side":
		boxSide()
	case "status":
		status()
	case "notify": // test hook: notify BOX TEXT
		notify(os.Args[2], os.Args[3])
	case "mac-side":
		m := &mac{}
		fs := flag.NewFlagSet("mac-side", flag.ExitOnError)
		fs.StringVar(&m.box, "box", "", "box name")
		dial := fs.String("dial", "", "fixed target: tcp:127.0.0.1:PORT or unix:/path")
		fs.IntVar(&m.maxStreams, "max-streams", 64, "open streams per box")
		fs.Float64Var(&m.rate, "rate", 20, "new streams per second")
		fs.DurationVar(&m.idle, "idle", 2*time.Minute, "idle timeout")
		fs.DurationVar(&m.life, "life", 60*time.Minute, "max stream lifetime")
		fs.DurationVar(&m.dialTO, "dial-timeout", 3*time.Second, "dial timeout")
		fs.Parse(os.Args[2:])
		m.cmd = fs.Args() // test-only: replaces the box command
		if len(m.cmd) == 0 {
			m.cmd = []string{"orb", "run", "-m", m.box, "-u", "root", "runuser", "-u", "bridge", "--", "/usr/local/sbin/agentbox-bridge", "box-side"}
		}
		i := strings.Index(*dial, ":")
		if m.box == "" || i < 0 {
			fmt.Fprintln(os.Stderr, "need -box and -dial tcp:HOST:PORT|unix:PATH")
			os.Exit(2)
		}
		m.dialNet, m.dialAddr = (*dial)[:i], (*dial)[i+1:]
		m.run()
	default:
		os.Exit(2)
	}
}
