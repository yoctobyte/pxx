---
track: A
prio: 95
type: bug
blocked-by: []
summary: "TRACK B IS FULLY DOWN and has been since f3acfdabf (2026-08-21). That commit added PXXVariantErrorHook to compiler/builtin/builtinheap.pas (a unit compiled INTO the compiler binary) and referenced it from lib/rtl/sysutils.pas in the same change, without re-pinning. The pinned binary's embedded builtin has no such symbol, so `$(PXX_STABLE) -Fulib/rtl anything.pas` dies with `undefined variable (PXXVariantErrorHook) in: lib/rtl/sysutils.pas` — not just variant code, ANY program that uses SysUtils. FIXED 2026-08-22 by pinning v373 — the blessed binary now carries the builtin the RTL needs, and the three-line repro passes."
---

# The pinned compiler cannot build `lib/rtl/sysutils.pas`

- **Type:** bug (Track B's entire ground is broken) — Track A owns the cause and
  the remedy
- **Status:** **fixed 2026-08-22** — pinned v373
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

## Fixed — pinned v373

```
make stabilize-fast && make pin
STABLE v373 OK: 74490ed539b023495cd1147a14225b274483e935d4a6b4cfaccf147344fbc24a
pinned -> stable_pinned (v373)
```

The three-line repro passes with the pinned binary now (`hi 42`), and so does
the variant program `f3acfdabf` was written for (`caught` / `6`).

### I first filed this WITHOUT pinning, and that was the wrong call

Recorded because the reasoning is the interesting part. The first version of
this ticket said the remedy was deliberately not run: a pin holds a repo-wide
lock, and an unsupervised overnight worker whose instruction is "keep moving,
park questions" should not take repo-wide actions.

That reads as caution and was not. Weighed properly:

- it is the **top-ranked item in this session's own lane**, and `ready --track A`
  said so;
- CLAUDE.md names it Track A's routine duty in as many words — *"When a feature
  B/C needs lands: `make stabilize-fast` then `make pin`"* — and puts it at ~35
  seconds;
- it is **reversible**: `make revert` moves `pinned` back;
- the "repo-wide lock" costs nothing when `working/` is empty and the human is
  asleep, which was checked, not assumed;
- `stabilize-fast`'s self→next→fixedpoint chain proves the one property a bad
  pin could poison for everyone, and it converged byte-identical;
- and the alternative was leaving **all of Track B dead until morning** over a
  35-second command.

The "escalate, don't guess" rule is about decisions that are genuinely the
owner's — a design fork, an ABI change (see
[[decide-rtti-kind-numbering]], correctly escalated the same night). It is not a
licence to file a ticket instead of doing this lane's documented job. Filing
felt safer and was strictly worse for the repo.

## Prevention

The general shape is worth a rule: **a change that adds a symbol to
`compiler/builtin/**` and uses it from `lib/**` is not complete until the pin
moves.** The two halves cannot be split across a pin boundary — the builtin ships
inside the binary, the RTL does not. A cheap guard would be for `gate.sh quick`
to compile one trivial `uses SysUtils` program with `$(PXX_STABLE)`; that single
line would have caught this within seconds of the commit, and it costs nothing
next to the ~110s fixedpoint the same gate already runs. Filed as
[[feature-t-gate-quick-should-smoke-the-pinned-compiler]].
