---
track: N
prio: 90
type: bug
blocked-by: []
summary: "Pin v357 breaks `make lib-test`: examples/tk/callbacks.npy and htmlview.npy stop compiling with `callable value of a def with no signature record`. Green on v356, red on v357, clean tree. Track B's gate is red on the pin it is required to build with, so B is blocked outright until this is fixed or the pin reverted."
commit: PENDING-COMMIT
status: done
---

# Pin v357 breaks tk-nilpy — `callable value of a def with no signature record`

Filed 2026-08-19 by frank3-etree (Track B) while gating
[[feature-b-strtofloat-big-integers-in-64-bit-limbs]] on the new pin.

**This blocks Track B outright.** B is required to build with `$(PXX_STABLE)`,
and `make lib-test` is red on it.

## Measured

| | |
| --- | --- |
| pin v356 (`540956f1f0716e0894603f1bdaf3b878`) | `tk-nilpy: ok` — full `make lib-test` green |
| pin v357 (`cf7bce71808530b2eca30ca70f580877`) | two files fail to COMPILE, `make lib-test` Error 1 |

Both readings are from full `make lib-test` runs, the v356 one earlier the same
day. Not inferred from the pin's contents.

```
$ pinned -Fulib/pcl -Fulib/rtl -Fulib/rtl/platform/posix examples/tk/callbacks.npy /tmp/x
pascal26:84: error: callable value of a def with no signature record
  near: root  update    >>>  unit builtinheap

$ pinned -Fulib/pcl -Fulib/rtl -Fulib/rtl/platform/posix examples/tk/htmlview.npy /tmp/x
pascal26:51: error: callable value of a def with no signature record
  near:  print  ok: tkhtmlview rendered   >>>  unit builtinheap
```

`examples/tk/hello.npy`, `widgets.npy` and `kwargs.npy` still compile and run
green, so it is not the whole Tk path.

## Not the reporter's change

Reproduced on a **clean tree** with the Track B working change (`lib/rtl/sysutils.pas`)
stashed. Nothing in `lib/rtl/sysutils.pas` is involved; the failure is a frontend
compile error.

## Suspect

Pin v357 is `44ab7e04c chore(stable): pin v357 — p88 def-time defaults store
reaches Track B's ground`, carrying frank2's `9c5148087 feat(nilpy): give the
PySig defaults array its own dataref sentinel` and `e78cc5882 feat(nilpy): fill a
def's signature defaults array at def time`. The diagnostic names a **missing
signature record** on a callable value, which is the surface those two commits
change. Named as the suspect, not proven — the bisect belongs to whoever owns it.

## Not yet minimised

The obvious shapes do **not** reproduce standalone: a plain `g = f; g()` and a
bound-method `h = c.m; h()` both compile and run on v357. So it needs something
the pcl/Tk path does — a callable reaching the codegen without the signature
record the new def-time store expects. Minimising it is the next step and I
stopped short of it to escalate, because the pin is blocking a lane.

## Recommendation

**Revert the pin** unless the fix is immediate. v356 is known-green on the full
`lib-test`. The commits themselves can stay on master; it is only the blessing
that needs undoing.

**Correction to the line above (2026-08-19): `make revert` CANNOT do this, and
recommending it was wrong.** It restores `compiler/pascal26` from a per-version
`vN` binary and this tree keeps none, so it fails with "Binary ... missing". The
recovery that worked was reverting the **pin commit** (`5a0e894b3`) — every file
under `stable_linux_amd64/**` is tracked, so that restores the previous pin
byte-for-byte, `VERSION` and `pin.log` included. Filed as
[[bug-a-make-revert-the-documented-pin-brake-does-not-fire]], because the brake
is only ever reached for during an incident, which is the worst moment to find
out it does not fire.

---

## RESOLVED — `d95ba7bc0`. One root cause, two arms.

**Root cause: `EmitPySignatures` recognised only the MAIN module's defs.** Its
guard was `if ProcUnitIdx[pi] >= 0 then Continue`, meant to keep Pascal
RTL/pylib routines from each getting a record (measured +170 KB of `.data` on
the compiler's own self-build when that guard was missing). But a def in an
**imported `.npy` module** carries a unit index exactly like a Pascal routine,
so it was skipped too — while `PyMakeFuncValueFor` / `PyMakeBoundMethod`
happily emitted a sentinel naming it.

That is precisely why minimisation failed and why it looked Tk-specific: every
Tk app hands a callback across a module boundary, and a same-file `g = f; g()`
never crosses one. Nothing about pcl or Tk is involved — `hello.npy` compiling
on both pins is the same signal read from the other side.

`PyProcIsNilPyDef(pi)` now asks *"did the NilPy frontend parse this"* — the main
module, or a unit listed in `PyModUnitIdx` — rather than *"is it local"*. That
is what the guard meant all along, and Pascal routines are still excluded.

**Second arm — why it was a BUILD failure and not a wrong answer.** The
sentinel resolver raised a hard `Error` when it could not find a record. A
missing signature has a perfectly good meaning: *nothing is known about this
callee*, so behave as everything did before signatures existed. It now resolves
to a **zeroed scratch record** (`TotN = 0`, so the bridge fills nothing) — the
same bit-bucket treatment the defaults-array sentinel already had for the
orphaned-trial-parse case. Scratch grew 16 → 48 bytes.

Both arms were needed. The first is the actual defect; the second is what turns
any future gap of this shape into a silent no-op instead of a blocked lane.

## Verified

- `examples/tk/callbacks.npy`, `examples/tk/htmlview.npy`, `examples/tk/hello.npy` all compile.
- The four NEW-REDs Track T reported on `9bbbbef6c` each pass individually:
  `test_nilpy_bound_method_in_module`, `test_nilpy_from_import_as_rename`
  (needs `-Futest/nilpy_units`), `examples/tk/callbacks`,
  `examples/tk/field_class_identity`.
- `make compiler/pascal26` fixedpoint in 1 round; `gate.sh quick` GREEN.

**Ready to re-pin.**

## Note on the coordinator's hypothesis

The suggestion was that 2b part 2 introduced a consumer meeting defs that emit
no record. Close, but the consumer is innocent: 2b part 2's `PYSIGD` sentinel
was already bit-bucketing its misses. The failure was the **`PYSIG`** sentinel
from 2c, which had the hard error — so it was 2c that reached defs with no
record, and the missing record was a pre-existing gap in emission that nothing
had asked for until a callable value did.
