#!/usr/bin/env python3
"""Round 4 proxy. One file, base-URL style: no CONNECT, no CA, no pop-ups. One Unix socket per box (run/<box>.sock) is the box's identity.
Routes: /gh/<owner>/<repo>/... (git smart HTTP), /ghapi/repos/<owner>/<repo>/... (REST), everything else goes to Anthropic.
Fake token swapped for the real one. One JSON log line per request: time, box, rule, method, host, path (no query), bytes. Never headers. Throwaway."""
import base64, http.client, json, os, re, socketserver, ssl, subprocess, sys, threading, time
from http.server import BaseHTTPRequestHandler

DIR = os.path.dirname(os.path.abspath(__file__))
BOXES = {"r4a": {"claude": "FAKE-CLAUDE-r4a", "gh": "FAKE-GH-r4a", "own": "ericwang05/test"}}
QUIET = {("GET", "/mcp-registry/v0/servers"), ("GET", "/api/directory/plugins"), ("POST", "/api/event_logging/v2/batch")}
HOP = {"transfer-encoding", "connection", "keep-alive", "host", "content-length", "proxy-connection", "authorization"}
BAD_PATH = re.compile(r"\.\.|//|%2f|%2e", re.I)
OWN_WRITES = {("POST", ("pulls",)), ("PATCH", ("pulls", "#")), ("POST", ("issues", "#", "comments")), ("POST", ("pulls", "#", "comments"))}
OWN_REPO = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
loglock = threading.Lock()


def keychain(name):
    v = subprocess.check_output(["security", "find-generic-password", "-s", name, "-w"], text=True).strip()
    if re.fullmatch(r"([0-9a-f]{2})+", v):  # security prints hex when the stored value has a newline
        v = bytes.fromhex(v).decode()
    return "".join(v.split())


def own_api_ok(command, rest):
    """Reads, open or edit a PR, comment. Not merge, ref delete, settings or contents write."""
    return command in ("GET", "HEAD") or (command, tuple("#" if s.isdigit() else s for s in rest)) in OWN_WRITES


def body_chunks(h):
    if "chunked" in h.headers.get("Transfer-Encoding", "").lower():
        while (n := int(h.rfile.readline().split(b";")[0], 16)):
            yield h.rfile.read(n)
            h.rfile.readline()
        h.rfile.readline()
        return
    left = int(h.headers.get("Content-Length") or 0)
    while left > 0:
        b = h.rfile.read(min(left, 1 << 20))
        if not b:
            return
        left -= len(b)
        yield b


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    timeout = 120  # same 2-minute idle rule as the bridge

    def log_message(self, *a):
        pass

    def log(self, rule, host, status, nbytes=0):
        line = json.dumps({"t": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "box": self.server.box, "rule": rule, "method": self.command,
                           "host": host, "path": re.sub(r"[^ -~]", "?", self.path.split("?")[0])[:200], "status": status, "bytes": nbytes})
        with loglock:
            print(line, flush=True)

    def reply(self, status, body=b"", rule="ok", host="-"):
        self.close_connection = True
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.log(rule, host, status, len(body))

    def fake_ok(self, kind):
        a, box = self.headers.get("Authorization", ""), BOXES[self.server.box]
        if kind == "claude":
            return a == f"Bearer {box['claude']}"
        if a.startswith("Basic "):
            try:
                return base64.b64decode(a[6:]).decode().split(":", 1)[1] == box["gh"]
            except Exception:
                return False
        return a.split(" ", 1)[-1] == box["gh"]  # "token X" or "Bearer X"

    def handle_any(self):
        p = self.path
        path, _, query = p.partition("?")
        if path == "/__health":  # bridge health check
            return self.reply(200, b"ok\n", "health")
        if path == "/api/hello" and self.command in ("GET", "HEAD"):
            return self.reply(200, b"", "hello-local")
        if BAD_PATH.search(p):
            return self.reply(403, b"forbidden\n", "bad-path")
        seg = path.split("/")[1:]
        own = BOXES[self.server.box]["own"]
        if seg[:1] == ["gh"]:
            host, kind, up = "github.com", "gh", "/" + "/".join(seg[1:])
            repo, rest = "/".join(seg[1:3]).lower().removesuffix(".git"), seg[3:]
        elif seg[:2] == ["ghapi", "repos"]:
            host, kind, up = "api.github.com", "gh", "/repos/" + "/".join(seg[2:])
            repo, rest = "/".join(seg[2:4]).lower(), seg[4:]
        elif seg[:1] == ["ghapi"]:  # graphql and anything else on the API
            return self.reply(403, b"forbidden\n", "gh-api-not-repos", "api.github.com")
        else:
            host, kind, up, repo, rest = "api.anthropic.com", "claude", p, "", []
        if not self.fake_ok(kind):
            if kind == "gh" and host == "github.com" and not self.headers.get("Authorization"):  # git retries with the credential helper
                self.close_connection = True
                self.send_response(401)
                self.send_header("WWW-Authenticate", 'Basic realm="box"')
                self.send_header("Content-Length", "0")
                self.send_header("Connection", "close")
                self.end_headers()
                return self.log("auth-challenge", host, 401)
            if not self.headers.get("Authorization") and (self.command, path) in QUIET:
                return self.reply(403, b"forbidden\n", "quiet-tokenless", host)
            return self.reply(403, b"forbidden\n", "bad-token", host)
        if kind == "gh":
            if repo != own:
                return self.reply(403, b"forbidden\n", "not-own-repo", host)
            if host == "api.github.com" and not own_api_ok(self.command, rest):
                return self.reply(403, b"forbidden\n", "rest-not-allowed", host)
            up = up + (("?" + query) if query else "")
            auth = "token " + GH if host == "api.github.com" else "Basic " + base64.b64encode(f"x-access-token:{GH}".encode()).decode()
        else:
            auth = f"Bearer {CLAUDE}"
        hdrs = {k: v for k, v in self.headers.items() if k.lower() not in HOP}
        hdrs["Authorization"] = auth
        sent = 0
        try:
            c = http.client.HTTPSConnection(host, timeout=300)
            c.request(self.command, up, b"".join(body_chunks(self)) or None, hdrs)
            u = c.getresponse()
        except Exception as e:
            return self.reply(502, b"upstream error\n", "upstream-" + type(e).__name__, host)
        self.send_response_only(u.status, u.reason)
        for k, v in u.getheaders():
            if k.lower() not in HOP:
                self.send_header(k, v)
        nobody = self.command == "HEAD" or u.status in (204, 304) or u.status < 200
        if nobody:
            if u.getheader("Content-Length"):
                self.send_header("Content-Length", u.getheader("Content-Length"))
        elif u.length is not None:
            self.send_header("Content-Length", str(u.length))
        elif u.chunked:
            self.send_header("Transfer-Encoding", "chunked")
        else:
            self.send_header("Connection", "close")
            self.close_connection = True
        self.end_headers()
        try:
            while not nobody and (chunk := u.read1(65536)):
                sent += len(chunk)
                self.wfile.write(f"{len(chunk):x}\r\n".encode() + chunk + b"\r\n" if u.chunked else chunk)
            if u.chunked and not nobody:
                self.wfile.write(b"0\r\n\r\n")
        except (OSError, ssl.SSLError):
            self.close_connection = True
        self.log("forward", host, u.status, sent)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = do_OPTIONS = handle_any


class Unix(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True
    request_queue_size = 1024

    def get_request(self):
        c, _ = super().get_request()
        return c, ("unix", 0)


if __name__ == "__main__":
    GH, CLAUDE = keychain("agentbox-github"), keychain("agentbox-claude")
    run = os.path.join(DIR, "run")
    os.makedirs(run, mode=0o700, exist_ok=True)
    os.chmod(run, 0o700)
    for box in BOXES:
        path = os.path.join(run, box + ".sock")
        if os.path.exists(path):
            os.unlink(path)
        srv = Unix(path, H)
        srv.box = box
        os.chmod(path, 0o600)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        print(json.dumps({"event": "listening", "box": box, "socket": path}), flush=True)
    threading.Event().wait()
