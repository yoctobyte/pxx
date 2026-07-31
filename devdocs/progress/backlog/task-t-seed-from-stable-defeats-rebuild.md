---
summary: "seed-from-stable makes the whole matrix test the pinned binary; only selfhost-fixedpoint can see it"
type: task
track: T
prio: 65
---

# `seed-from-stable` silently defeats the self-host rebuild

- **Type:** tooling trap (Track T — `tools/testmgr.py`)
- **Found:** 2026-07-31, enrolling the xeon watcher box. First run: 17 red.

## What happens

The documented fresh-box step is `make seed-from-stable`, which **copies**
`stable_linux_amd64/default/pinned` onto `compiler/pascal26`. The copy gets a
**fresh mtime**, newer than `compiler/compiler.pas`. testmgr then runs
`make compiler/pascal26`, make says *"up to date"*, and no self-host build ever
happens — the entire sweep tests the **pinned** binary instead of a compiler
built from the checked-out sources.

Measured on xeon at `110774a14648`: `compiler/pascal26` byte-identical to
`pinned`, mtime 13 minutes newer than the sources.

The window is not just the first run. It persists for **every sha whose diff
does not touch a compiler source** — a tstate commit, a docs commit, a
`lib/**`-only commit — because nothing bumps a source mtime past the binary.

## Why it matters

This is a concrete mechanism for the "phantom NEW-RED" complaint: jobs go red
against a stale compiler, then "fix themselves" on the next sha that happens to
touch `compiler/**` and forces a real rebuild. No commit in the range can
explain either transition, which is exactly the signature that makes other
agents stop trusting tstate.

Only `selfhost-fixedpoint` can detect it (property 2, the anti-Thompson
agreement check) — and when it does, it reads as a scary self-host regression
rather than "your seed is stale".

## Fix (Track T's own file)

`tools/testmgr.py`, at the point it builds the compiler: before trusting make's
"up to date", assert the binary is not simply the pinned seed —

- if `compiler/pascal26` is byte-identical to `stable_linux_amd64/default/pinned`,
  force the rebuild (`touch compiler/compiler.pas`, or build to a temp path and
  move it in), and say so on stdout;
- log the built binary's sha256 in the run report, so every verdict names the
  binary it came from (the repo's own "verify against a KNOWN sha" rule).

Do **not** fix this by editing the `seed-from-stable` rule — the `Makefile` is
Track A's fenced ground. The check belongs in testmgr.

## Repro

```sh
make seed-from-stable
tools/testmgr.py --tier native --job 'src:tools/selfhost_fixedpoint.sh'
# FAIL: the fixedpoint reached from PINNED differs from compiler/pascal26
touch compiler/compiler.pas && make compiler/pascal26
tools/testmgr.py --tier native --job 'src:tools/selfhost_fixedpoint.sh'   # green
```
