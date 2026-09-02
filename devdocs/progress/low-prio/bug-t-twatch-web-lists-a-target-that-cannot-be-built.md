---
track: T
prio: 15
type: bug
blocked-by: []
summary: "tools/twatch_web.py lists riscv64 in CROSS_TARGETS, but no compiler backend can produce a riscv64 binary and the test manager never mentions the target. The dashboard therefore carries a column that is structurally empty, and an empty column reads as 'no news' rather than 'impossible'."
status: low-prio
owner: ""
---

# The dashboard lists a target that cannot be built

Found 2026-08-21 while answering the first question in
[[feature-a-riscv64-as-a-hosted-first-class-target]], which flagged it as worth
checking separately. It checks out.

## Measured

- `tools/twatch_web.py:89` — `CROSS_TARGETS = ("i386", "arm32", "aarch64",
  "riscv32", "riscv64", "arm", "xtensa", "riscv")`
- the test-manager script — **no occurrence** of the string `riscv64`
- `compiler/` — no `ir_codegen_riscv64`; the backend does not exist

The runner half is ready (`tools/run_target.sh` handles `riscv64`,
`tools/install_qemu.sh` installs `qemu-riscv64`), which is presumably how the
name got into the list. Nothing can produce the binary for it to run.

## Why it matters more than a stray string

A column with no results looks identical to a column whose jobs all passed
quietly, or whose jobs have not run yet. So the dashboard silently asserts
coverage that cannot exist. Same class as
[[bug-a-a-lua-cross-timeout-is-reported-as-wrong-output-from-the-backend]] — a
report saying something untrue about the compiler — one notch quieter, because
this one says nothing at all where it should say "not a target".

Note `CROSS_TARGETS` also carries `"arm"` and `"riscv"` alongside `"arm32"` and
`"riscv32"`; whether those are live aliases or the same kind of leftover is worth
one look while in there.

## Fix shape

Track T's call: drop `riscv64` until a backend exists, or render it explicitly as
"no backend" rather than blank. The second is better — it turns a silent absence
into a stated one, and it will be right again the day the backend lands.

## Gate

Track T's own, plus the page still renders against a real `tstate/` tree.

## Deprioritised 2026-09-02 — the Track T tooling backlog was cut as a pile

**This ticket is not being called wrong.** It was moved as part of a pile, not
judged individually, and nothing here disputes its finding.

Owner decision. 73 of the 74 open `track: T` tickets were filed between
2026-08-31 and 2026-09-02, 58 on one day. The pile was too large to work through
and returned almost nothing, and a ticket nobody will fix does not sit neutrally
— it stays in the ranker forever at zero value, which is the argument CLAUDE.md
already makes for a terminal folder over a low prio.

Four were kept in the ranker on a purely structural test — an active umbrella or
a hard `blocked-by:` edge from live work:
`umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**Kept, not deleted, for two reasons:** so the finding is not rediscovered and
refiled from scratch by the next agent who trips over it, and so it can be pulled
back if what it touches becomes load-bearing.

**To revive it:** move it to the owning lane's backlog, set `status: backlog`,
and say in the ticket WHAT CHANGED to make it matter now. Restoring it because it
reads well is how the pile comes back.
