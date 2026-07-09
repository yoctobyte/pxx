---
prio: 40
---

# C anonymous struct/union member braced-designated init (`-fms-extensions`)

- **Type:** feature/bug. Track C (C frontend).
- **Found:** 2026-07-09, isolating c-testsuite 00216 after compound literals landed.

## Repro
```c
struct S { unsigned char a, b; unsigned char c[2]; };
union UV { struct { unsigned char a, b; }; struct S s; };
union UV g = {{.b = 7, .a = 8}};   // pxx: "expected C expression"
```
gcc/tcc accept this widely-used extension. Positional `{{6,5}}` and union-level
promoted designators `{.b = 8, .a = 7}` ALREADY work in pxx — only the braced +
designated form into a promoted anonymous member fails.

## Root cause
The anonymous struct's fields are PROMOTED flat into the union's field list (so
`.b`/`.a` resolve directly on the union — that's what makes the promoted-designator
form work). But an inner brace `{...}` is meant to initialise the WHOLE anonymous
member as one subaggregate. The recursive init walker (`CInitWalkRecord` /
`CInitWalkMember`, cparser.inc) treats the union's field[0] as the scalar `a`, sees
the inner `{` as a braced-scalar `{ expr }` (CInitLeaf's tkBegin branch), then
`ParseCExpr` chokes on the leading `.` of `.b`.

## Needed
The walker must recognise that field[0..k] belong to a promoted anonymous aggregate
and, on a matching inner brace, descend that anonymous sub-struct as one member
(honouring designators against its own fields) rather than as flat promoted scalars.
Likely wants an anon-group marker on the promoted UFields (parent anon record id +
span) so the walker can re-group them for a brace.

## Gate
`union UV g = {{.b=7,.a=8}}` byte-identical to gcc; contributes to unskipping
c-testsuite 00216 (with [[bug-c-fullfile-cumulative-parser-desync]]).
[[feature-c-compound-literals]]
