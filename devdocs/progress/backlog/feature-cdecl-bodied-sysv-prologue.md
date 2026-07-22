---
track: A
prio: 40
type: feature
---

# Bodied Pascal `cdecl` procs: genuine SysV prologue (float params, >6 args)

Follow-up to bug-cdecl-indirect-over-6-integer-args. State after that fix:

- Indirect cdecl calls (dlsym'd C targets) marshal TRUE SysV including >6-int
  stack spill and xmm float classes — Synapse/OpenSSL 7+-arg entry points work.
- A BODIED pxx proc marked `cdecl` still receives the INTERNAL convention
  (every param in an integer register by position; >6 all-stack; floats as GPR
  bits). Direct pxx calls agree with that prologue, so pure-Pascal use works.
- The unsound overlap — `p := @PascalProc` into a cdecl proc-type when the
  proc has a by-value float param or >6 params — is now a LOUD compile error
  at the assignment (ir.inc AN_ASSIGN check). <=6 int/pointer params coincide
  with SysV and stay allowed (GTK-style callbacks).

Wanted: emit a real SysV prologue (and matching direct-call marshalling) for
bodied cdecl procs: int/sse classes counted independently (an int param AFTER
a float param shifts register!), xmm0..7 reception, >6/>8 stack reception at
[rbp+16+...], Single narrowing at the right site (see the LANDMINE note in
parser.inc's param homing about per-target narrow points). Then delete the
AN_ASSIGN reject. Float RETURNS already work both ways (EmitLoadVar leaves
xmm0 and rax both set).

Gate: cd8/cd11/cd12-style tests (8 int args, mixed float/int order, C-side
callback via crtl calling a @PascalProc with double params) + make test +
self-host byte-identical.
