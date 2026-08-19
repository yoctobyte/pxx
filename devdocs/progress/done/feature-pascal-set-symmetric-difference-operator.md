---
track: P
prio: 35
type: feature
blocked-by: []
summary: "ALREADY SOLVED — measured 2026-08-19 against pin v363: `><` parses, lowers, and matches FPC (`s1 >< s2` over [1,3,5] and [3,5,7] yields {1,7} under both). The ticket's quoted parse error no longer reproduces."
status: done
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

## Triage 2026-08-19 (Track D re-triage pass, pin v363) — ALREADY SOLVED, closing

Re-ran the ticket's own repro against the pinned compiler; it no longer
reproduces. The quoted `pascal26:25: error: expected expression` is gone.

```pascal
s1 := [1,3,5]; s2 := [3,5,7];
WriteLn(1 in (s1 >< s2));          { pxx: TRUE    FPC: TRUE }
s3 := s1 >< s2;
for i := 0 to 9 do if i in s3 then Write(i, ' ');
                                   { pxx: 1 7     FPC: 1 7  }
```

Both the membership form the ticket quotes and a full enumeration of the
resulting set agree with FPC 3.x element for element, so the operator is not
merely parsed — it lowers correctly. Landed incidentally in the weeks of
operator/set work since 2026-08-09; no separate implementation is needed.

Closed as already solved, not as rejected.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
