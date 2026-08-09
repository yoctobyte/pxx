---
track: P
prio: 35
type: feature
blocked-by: []
---

# The set symmetric-difference operator `><` is not parsed

- **Type:** feature (Pascal dialect surface) — **Track P**
- **Found:** 2026-08-09, an FPC differential over the set/record operator
  surface (Track A session). Everything else in that sweep matched FPC exactly:
  `+ * -`, `=`, `<=`, `>=`, `in`, `Include`/`Exclude`, char sets, ranges,
  runtime-valued elements, 256-element sets, and records/arrays of records.
  `><` is the one hole.

```pascal
s1 := [1, 3, 5];
s2 := [3, 5, 7];
WriteLn(1 in (s1 >< s2));      { FPC: TRUE }
```

```
pascal26:25: error: expected expression
  near:   in  s1  >>>  s2
```

## Shape of the fix

A lexer token for `><` and one more arm in the set-binop lowering, which already
has `+`/`*`/`-` through `IR_SET_BINOP` — symmetric difference is `(a - b) + (b - a)`,
or a per-word XOR at the same place the other three are emitted, which is
cheaper and is what FPC does.

Filed under **P** (Pascal dialect surface) though the edit lands in the shared
`lexer.inc`/`parser.inc`, so it obeys Track A's no-concurrent-edit rule. Low
priority: `><` is rare in real code, and the workaround `(a - b) + (b - a)` is
exact.
