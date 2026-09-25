# pxx — agent guide

**Start with `AGENTS.md`** at the repository root. It covers what PXX is, how to
build it from nothing, how to test it, how to check for memory leaks, the ESP32
tooling, where things are, and the known issues at beta 0.1 "Blaise" (pin v441).

Active development paused after that beta (September 2026), and the project
is looking for sponsors (see `README.md`). Nobody watches this repository day
to day.

The operating rules the AI fleet worked under from June to September 2026 are
kept, unchanged, in `devdocs/dev/fleet-rules-2026.md`. They were written for
several agents working in parallel under one owner and are long. Read them for
the reasoning behind the tooling, not as rules you must follow. The reasons
behind them are in `devdocs/dev/handbook-rationale.md`.

The repository's Claude Code hooks (`.claude/hooks/`) still apply. They refuse
full test suites by default (set `PXX_ALLOW_FULL_SUITE=1` when you mean it),
and they refuse `rm` with a variable or glob in the path (spell the path out).
