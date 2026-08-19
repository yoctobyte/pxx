---
track: N
prio: 90
type: bug
blocked-by: []
summary: "Pin v357 breaks `make lib-test`: examples/tk/callbacks.npy and htmlview.npy stop compiling with `callable value of a def with no signature record`. Green on v356, red on v357, clean tree. Track B's gate is red on the pin it is required to build with, so B is blocked outright until this is fixed or the pin reverted."
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

**Revert the pin** (`make revert` moves `pinned` back to v356) unless the fix is
immediate. v356 is known-green on the full `lib-test`. The commits themselves can
stay on master; it is only the blessing that needs undoing, which is exactly the
brake `make revert` exists to be.
