---
prio: 55
---

# High(Type)/Low(Type) not accepted in constant expressions / array bounds

- **Type:** bug (Pascal frontend — const-eval) — **Track P** (edits the shared
  parser/const-eval, so it runs under A's gate + no-concurrent-edit rule)
- **Status:** done
- **Opened:** 2026-07-11, first blocker of the New-ZenGL Pascal ladder
  ([[feature-game-library-candidate-suite]] slice C).

## Symptom

`High(T)` (and presumably `Low(T)`) works as a runtime expression
(project memory: "High/Low of type" landed) but is rejected by the constant
evaluator, so it cannot appear in an array bound or const declaration:

```pascal
type
  TSmall = array[0..High(Byte)] of Byte;              { minimal repro }
  TByteArray = array[0..High(LongWord) shr 1 - 1] of Byte;   { ZenGL zgl_types.pas:105 }
```

```
ConstEval error at SrcLine 3: SVal = High Kind = 1 TokPos = 11
```

Also note the diagnostic itself: `ConstEval error` reports a raw token dump
instead of a file:line error like the parser's other messages — worth folding
into the normal error path while in there.

FPC accepts both forms; `High(LongWord)` = 4294967295 must evaluate as an
unsigned value in const context (the ZenGL bound is
`High(LongWord) shr 1 - 1` = $7FFFFFFE).

## Where hit

`library_candidates/zengl/Zengl_SRC/src/zgl_types.pas:105` — blocks the whole
New-ZenGL Pascal ladder (every zgl unit pulls zgl_types via uses).

## Acceptance

- `High(T)`/`Low(T)` for ordinal types (incl. LongWord, Int64, enums,
  subranges, Char, Boolean) evaluate in const expressions: array bounds,
  `const x = High(...)`, case labels.
- Compose with const operators (`shr`, `-`, ...) as in the ZenGL bound.
- Self-host byte-identical; a compile-run test covers the forms above.

## Log
- 2026-07-12 — resolved, commit HEAD.
