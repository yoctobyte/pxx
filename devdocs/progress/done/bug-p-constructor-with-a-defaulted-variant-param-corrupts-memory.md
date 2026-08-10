---
track: P
prio: 70
type: bug
summary: "A class CONSTRUCTOR with a defaulted Variant parameter corrupts memory when the caller omits the argument — 12-line repro, 100% reproducible. The identical plain PROCEDURE is fine, and passing the argument explicitly is fine. Silent stack smashing: the crash lands in unrelated code with return addresses overwritten by text"
status: done
owner: claude-ACPN
---

# A constructor's defaulted `Variant` parameter smashes the stack

- **Type:** bug (memory corruption) — Track P / A (constructor call lowering ×
  default parameters × managed types)
- **Opened:** 2026-08-09
- **Found by:** Track B, chasing an intermittent crash in the reportlab mimic
  ([[bug-b-reportlab-mimic-multi-font-heap-corruption]]) down from a PDF library
  to this.

## Repro — 12 lines, no library, 100% reproducible

```pascal
program vctor;
uses pylib;
type
  TThing = class
    tag: Integer;
    constructor Create(const name: AnsiString; const v: Variant = 0);
  end;
constructor TThing.Create(const name: AnsiString; const v: Variant = 0);
begin
  tag := pyvartag(v);
end;
var t: TThing;
begin
  t := TThing.Create('a', 0);   writeln('  tag=', t.tag);   { ok, tag=1 }
  t := TThing.Create('b');      writeln('  tag=', t.tag);   { SEGFAULT }
end.
```

```
explicit:
  tag=1
defaulted:
Segmentation fault (core dumped)
```

## What narrows it

| shape | result |
| --- | --- |
| `constructor` with defaulted `Variant`, argument OMITTED | **crash, every run** |
| `constructor` with defaulted `Variant`, argument PASSED | ok |
| plain `procedure` with defaulted `Variant`, argument omitted | **ok** — `tag=1` |

So it is not default parameters in general, and not `Variant` in general: it is
the two together **in a constructor**.

## Why it is worth prio 70

The failure is not a clean crash at the call. It is **stack smashing**: in the
original symptom the faulting frame was `__crtl_utoa` deep inside printf
formatting, with every return address on the stack overwritten by ASCII text
(`0x7c7c7c7c7c7c7c7c` = `'|'`, and arguments decoding to `0x46464646` = `'FFFF'`).
Nothing pointed at the constructor. It took a differential harness, gdb, and
reduction through three layers to find, and along the way it produced a
convincing but WRONG intermediate conclusion ("crashes above four fonts") from
small samples of an intermittent fault.

From a library the corruption is INTERMITTENT (different stack layout per
caller), which is worse than deterministic — the reportlab mimic's cases went
from 2/3 failing to 0/3 to 3/3 across identical runs.

## Consumers hit today

`lib/pcl/mimic_reportlab_pdfgen.pas`'s `Canvas.Create(filename, pagesize = 0)` —
i.e. `canvas.Canvas("out.pdf")`, reportlab's single most common call. Track B is
sidestepping it with an explicit-argument overload, registered in
`devdocs/dev/track-b-workarounds.md` with a revert-when-fixed lifecycle.

## Gate

The repro above printing `tag=1` twice, plus `make test` + self-host fixedpoint.
Worth a regression test in `test/` pinning constructor × defaulted managed
parameter, since a plain procedure passing is exactly what let this survive.

## Log
- 2026-08-10 — resolved, commit PENDING-COMMIT.

## Resolution (2026-08-10)

**Root cause: a second mechanism.** The constructor call path
(`parser.inc`, the `TFoo.Create` arity check) built its default arguments with
a hand-rolled str/ordinal pair of its own instead of the shared
`DefaultArgValueNode`. That copy never learned what the shared builder had
since: float defaults, set defaults, AnsiString-vs-frozen tagging — and the
one that smashed the stack, **retagging a `Variant` parameter's ordinal as
`tyInteger` so `IRLowerCallArg` BOXES it**. Tagged `tyVariant`, the boxing was
skipped and the callee dereferenced the bare ordinal `0` as a 16-byte variant
slot, corrupting the caller's frame far from the call.

The shared builder had carried that exact retag (with a comment naming the
same crash for the NilPy path) since a previous fix — the ctor path just never
went through it. Classic `normalise-dont-special-case`: the second path is the
one that stays broken.

**Fix:** the ctor site now calls `DefaultArgValueNode(mpi, mlastArg + 1)`; the
duplicate builder is deleted. The ctor-specific arity diagnostic is kept.

**Regression test:** `test/test_default_params_methods.pas` grew
`proc-variant-default` / `ctor-variant-explicit` / `ctor-variant-default`
(12 → 15 checks; Makefile assertion updated). The plain-procedure arm is in
deliberately — it always passed, and that is what let this survive.

**Gate:** repro prints `tag=1` twice; `tools/gate.sh quick` GREEN (self-host
fixedpoint + testmgr quick).

**Follow-ups found while testing the neighbouring shapes** (filed separately —
both are *declaration*-side and pre-existing, unrelated to this fix):
- [[bug-p-float-literal-default-in-a-parameter-list-fails-to-parse]]
- [[bug-p-string-literal-default-in-a-parameter-list-is-not-a-constant]]

Track B may revert its explicit-argument workaround in
`devdocs/dev/track-b-workarounds.md`.
