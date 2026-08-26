---
track: T
prio: 65
type: feature
blocked-by: []
summary: "Add one line to gate.sh quick: compile a trivial `uses SysUtils` program with $(PXX_STABLE). Track B's ground was silently broken for a day because a Track A commit added a symbol to compiler/builtin/** and used it from lib/rtl/** without moving the pin — the pinned binary's embedded builtin lacked the symbol, so every Track B build died. Nothing in the dev loop builds with the PINNED compiler, so nothing noticed."
owner: pxx-aa
---

# `gate.sh quick` should smoke the PINNED compiler against `lib/rtl`

- **Type:** feature (a gate gap) — Track T (`tools/gate.sh`)
- **Status:** done
- **Opened:** 2026-08-22, from
  [[bug-a-the-pinned-compiler-cannot-build-librtl-sysutils]]

## The gap

The per-fix loop builds and gates with the **freshly self-hosted** compiler.
Track B builds with the **pinned** one. Nothing in the dev loop ever runs the
pinned binary, so a change that makes the tree's `lib/rtl` require a compiler
newer than the pin is invisible to every gate a dev track runs — while breaking
Track B completely.

That is what happened: `PXXVariantErrorHook` was added to
`compiler/builtin/builtinheap.pas` (compiled INTO the binary) and referenced
from `lib/rtl/sysutils.pas` (ordinary source) in one commit, with no pin. Every
`$(PXX_STABLE) -Fulib/rtl <anything>.pas` then failed with `undefined variable
(PXXVariantErrorHook)` — including a three-line hello-world. It surfaced only as
an ADVISORY `demos#00` red.

## Proposed check

```sh
# the pinned binary must still be able to build the tree's RTL
printf 'program s;\n{$mode objfpc}{$H+}\nuses SysUtils;\nbegin WriteLn(IntToStr(42)); end.\n' > $tmp/pinsmoke.pas
$(PXX_STABLE) -Fulib/rtl $tmp/pinsmoke.pas $tmp/pinsmoke && $tmp/pinsmoke
```

Sub-second, no compiler rebuild, and it fails loudly with the real error. It
belongs in `quick` rather than a breadth tier precisely because the failure it
catches is *created by a dev-lane commit and invisible to the dev lane*.

## Design note — what it must NOT become

This is not "run Track B's gate in the dev loop". It is one file, chosen because
`SysUtils` is what every Track B build pulls, and its whole job is to answer a
single question the dev loop cannot otherwise ask: *can the blessed binary still
build the tree's RTL?* Keep it to that; if it grows into a lib-test shard it
will get deleted for costing ten minutes, which is how the dev loop is supposed
to react.

Consider the same one-liner as a `make pin` PRE-condition, so a pin that would
not fix such a break is caught before it takes the lock.

## Gate

Track T's own breadth run green, and the new check verified both ways — passing
at a pinned/RTL pair that agrees, failing with the real error message at
`f3acfdabf`'s tree.

## Resolved 2026-08-26 (pxx-aa, Track T) — and it was a DUPLICATE

This and [[bug-t-gate-quick-cannot-see-a-broken-pinned-rtl]] are one defect
filed twice, from two separate incidents four days apart, both at prio 65:
`PXXVariantErrorHook` (2026-08-22, this ticket) and `PXXNilRefHook`
(97b1812fe). Neither ticket cites the other. That the same seam produced two
independent reports is itself the argument for the check — the class has an
unknown population and was being rediscovered by accident each time.

The canary landed under the other ticket (`1cc54252e`). Two deltas from **this**
ticket's spec were real and are now in:

**1. It RUNS the program, not just compiles it.** The other ticket argued
compile-only ("running it is not the point"); this one wrote `&& $tmp/pinsmoke`.
This one is right, and they are two questions rather than one preference: the
compile asks whether the frozen builtin still satisfies `lib/rtl`'s references,
the run asks whether the result works. A pinned RTL that compiles and then dies
is exactly as broken for Track B, and nothing else in the dev loop asks. The two
failures print different messages so triage stays sharp — a run failure is NOT
the frozen-builtin seam.

**2. `make pin` verifies the binary it just blessed.** Suggested here as a
PRE-condition; implemented as a POST-freeze one, because before the freeze the
frozen set is still the *old* pin's and the answer is about a binary nobody is
about to commit. It exits 1 rather than warning: the entire cost of this failure
is that nobody looks, so a warning that scrolls past is the same as no check. It
names the undo (`make revert`) because the pin has already moved by then.

This is the other end of the seam gate.sh guards. gate.sh catches the *commit*
that breaks `$(PXX_STABLE)`; this catches the *pin* that fails to fix it —
taken while holding the repo-wide lock, which is the expensive moment to be
wrong.

### Verified failing, both ends

Not asserted — executed. In a scratch tree with one injected reference in
`lib/rtl/sysutils.pas` to a builtin the frozen set does not define, the pin
recipe's own fragment prints

```
PIN VERIFY FAILED — the binary just pinned cannot build lib/rtl:
  pascal26:5306: error: undefined variable (PXXCanaryProofHook)
  The pin HAS already moved. Undo with: make revert
```

and exits 1; the gate canary fails the same way through `gate.sh`'s `step`
wrapper. Green against the real tree in both places.

`tools/gate_pinned_rtl_canary_devtest.py` guards both, including that the
canary still RUNS what it built (the half a later cleanup would drop as
redundant) and that the pin check still `exit 1`s rather than warning.

## Log
- 2026-08-26 — resolved, commit PENDING-COMMIT.
