---
track: P
prio: 70
type: bug
summary: "A class CONSTRUCTOR with a defaulted Variant parameter corrupts memory when the caller omits the argument — 12-line repro, 100% reproducible. The identical plain PROCEDURE is fine, and passing the argument explicitly is fine. Silent stack smashing: the crash lands in unrelated code with return addresses overwritten by text"
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
