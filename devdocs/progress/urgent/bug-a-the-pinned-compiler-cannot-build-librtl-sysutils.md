---
track: A
prio: 95
type: bug
blocked-by: []
summary: "TRACK B IS FULLY DOWN and has been since f3acfdabf (2026-08-21). That commit added PXXVariantErrorHook to compiler/builtin/builtinheap.pas (a unit compiled INTO the compiler binary) and referenced it from lib/rtl/sysutils.pas in the same change, without re-pinning. The pinned binary's embedded builtin has no such symbol, so `$(PXX_STABLE) -Fulib/rtl anything.pas` dies with `undefined variable (PXXVariantErrorHook) in: lib/rtl/sysutils.pas` — not just variant code, ANY program that uses SysUtils. Remedy is one documented command; NOT run unilaterally because a pin holds a repo-wide lock."
---

# The pinned compiler cannot build `lib/rtl/sysutils.pas`

- **Type:** bug (Track B's entire ground is broken) — Track A owns the cause and
  the remedy
- **Status:** **urgent, open** — needs a pin, which is a repo-wide-lock action
- **Opened:** 2026-08-22 by the Track A night session

## Measured

```
$ ./stable_linux_amd64/default/pinned -Fulib/rtl hello.pas out
pascal26:4790: error: undefined variable (PXXVariantErrorHook)
  in: lib/rtl/sysutils.pas
```

where `hello.pas` is three lines and does nothing but `uses SysUtils` and
`IntToStr(42)`. The same file with the HEAD compiler prints `hi 42`.

So this is not a variant-code problem. **Every Track B build of every program
that uses SysUtils is failing**, and Track B's whole rule is to build with
`$(PXX_STABLE)` and never rebuild the compiler.

## Cause

`f3acfdabf` ("a failed Variant conversion raises EVariantError instead of
killing the process") did two things in one commit:

- added `PXXVariantErrorHook` to `compiler/builtin/builtinheap.pas` — a builtin
  unit that is compiled **into the compiler binary**, and
- referenced it from `lib/rtl/sysutils.pas`, which is ordinary SOURCE the
  *pinned* compiler compiles.

`git log -S PXXVariantErrorHook` returns that one sha for both files. The pin
was not moved, so the blessed binary carries a builtin without the symbol while
the tree carries an RTL that needs it. That is exactly the stable-binary
boundary CLAUDE.md describes: *"When a feature B/C needs lands: `make
stabilize-fast` then `make pin` (blesses it, moves `pinned`)."* The pin half
never ran.

## How it surfaced

Track T reported `demos#00` red, bad `f3acfdabf53c`, last good `ba5791c02ce3`,
one commit in range. `demos` is ADVISORY, so it was a notice rather than a gate
— correct policy for a broken demo, and it undersells this one badly: the
advisory job was reporting a total Track B outage. Worth remembering the next
time an advisory red is skimmed past.

The sibling red in the same report, `test-core#src:test/fpcv.pas@2`, is
attributed to the same sha and is a DIFFERENT, unrelated defect (a broken
`printf` expectation in the Makefile row); it is fixed separately.

## Remedy — one command, deliberately not run here

```
make stabilize-fast && make pin      # ~35s, then commit stable_linux_amd64/**
```

Not run by this session on purpose. A pin holds a **repo-wide lock** — every
other lane and the human wait on it — and this session is an unsupervised
overnight Track A worker whose standing instruction is to keep moving and park
questions rather than take repo-wide actions. It would also bless a tree Track T
has not finished sweeping (tonight's Track A commits are hours old at most).

Whoever picks this up: `tools/gate.sh quick` is GREEN at HEAD and the self-host
fixedpoint converges in one round, so the pin should be uneventful. Check
`tools/twatch.py --status` first — the current `pin verify` red at v372 is
recorded there as NOT CORROBORATED (all 16 new reds pass in the breadth tier an
hour later, a load-shaped flake), so do not read it as a reason to hold off.

## Prevention

The general shape is worth a rule: **a change that adds a symbol to
`compiler/builtin/**` and uses it from `lib/**` is not complete until the pin
moves.** The two halves cannot be split across a pin boundary — the builtin ships
inside the binary, the RTL does not. A cheap guard would be for `gate.sh quick`
to compile one trivial `uses SysUtils` program with `$(PXX_STABLE)`; that single
line would have caught this within seconds of the commit, and it costs nothing
next to the ~110s fixedpoint the same gate already runs. Filed as
[[feature-t-gate-quick-should-smoke-the-pinned-compiler]].
