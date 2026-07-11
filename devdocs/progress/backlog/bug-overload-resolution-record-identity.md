---
prio: 45
---

# overload resolution ignores record IDENTITY — wrong overload silently called

- **Type:** bug (Pascal frontend, overload matching) — Track P (shared
  parser.inc/symtab.inc, A-gated)
- **Status:** backlog — filed 2026-07-11 while building
  [[feature-lib-vecmath]] (probe below), pre-existing (stable v197)
- **Owner:** —

## Symptom

Two overloads differing only in RECORD type: the matcher scores them as
equal (param kind tyRecord matches tyRecord, rec id not compared), and the
wrong body is silently called — reading fields past the smaller record's
end (out-of-bounds, garbage values):

```pascal
type
  TVec2 = record x, y: Double; end;
  TVec3 = record x, y, z: Double; end;
function Dot(const a, b: TVec2): Double; begin ... end;
function Dot(const a, b: TVec3): Double; begin ... a.z*b.z; end;
...
Dot(v2a, v2b)   { calls the TVec3 body: a.z reads past the 16-byte record }
```

Arity-based overloading works (ucomplex cstr 1/2/3-arg forms); it is only
the record-type discrimination that is missing. Likely same for class types
(check while fixing) and for distinguishing record vs class overloads.

## Where

Overload candidate scoring (FindProc/overload matcher in symtab.inc /
parser.inc call-site coercion). ProcParamRecId[procIdx*MAX_PROC_PARAMS+i]
already persists each param's rec id precisely because sym slots are reused
— the matcher just has to compare it against the arg node's rec id
(ResolveNodeRec).

## Consequence in the wild

`lib/rtl/vecmath.pas` uses suffixed names (Dot2/Dot3/Dot4, Cross,
MulMV3/MulMV4…) instead of clean overloads; de-suffix when this lands.

## Gate

`make test` + self-host fixedpoint byte-identical (matcher is shared core).
Tests: record-type overload dispatch (both orders of declaration), record
vs class overload, negative: ambiguous call still errors.
