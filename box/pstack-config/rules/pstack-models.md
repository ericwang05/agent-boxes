# pstack model configuration. One line per role. Delete a line to fall back to the skill default.
# `inherit-parent` or `auto` as a value: the role runs on the parent chat model (omit Task `model`). Alias entries in a panel list still count toward its fan-out.
# budget: small (medium)
feature, refactoring: inherit-parent
bug-fix: inherit-parent
perf-issue: inherit-parent
hillclimb: inherit-parent
judgment and prose: opus medium
hardest tasks: opus medium
how explorer: inherit-parent
how explainer: opus medium
why investigators: inherit-parent
why synthesizer: opus medium
reflect tooling: inherit-parent
reflect judgment, divergent, synthesizer: opus medium
arena runners: opus medium, inherit-parent
arena cross-judge pool: fable medium, sonnet medium, opus medium
swarm workers: inherit-parent
architect runners: opus medium, inherit-parent
interrogate reviewers: opus medium, inherit-parent
