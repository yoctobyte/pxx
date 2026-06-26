# C: nested/anonymous struct-or-union member makes the whole struct opaque

- **Type:** bug (HIGH impact — silent miscompile) — Track C / layout
- **Opened:** 2026-06-26
- **Found-by:** lua ldo `setobjs2s(L, ci->func.p + i, ...)` reduced to
  `struct O { union { T *p; long x; } u; }; o.u.p` -> garbage / IR_UNSUPPORTED.

## Symptom
A struct that CONTAINS a nested anonymous struct/union member is laid out as an
opaque pointer, so every field access on it reads the wrong place:
```c
struct O { union { int *p; long x; } u; };
... o.u.p ...        /* gcc: the pointer; pxx: truncated garbage (e.g. 139) */
```
`CStructBodyIsSimple` (cparser.inc ~2446) deliberately returns False for "nested/
anonymous struct or union bodies (a second brace)" and falls back to an opaque
pointer (to avoid silently-wrong offsets). Plain pointer/scalar members and
nested-struct-BY-TAG (`struct Foo bar;`) work; only an inline `{ ... }` body bails.
A top-level union, and a struct whose nested aggregate is a NAMED type, both work.

## Why it matters
lua's core structs use nested unions/structs pervasively: `TValue` holds
`Value value_` (Value is a union), `CallInfo` has `union { ... } u;` and a
`union { ... } func`-ish field, `GCUnion`, `Node`/`TKey`, etc. So those structs go
opaque and field access silently miscompiles. It blocks ldo/ltm at codegen and is
a latent silent miscompile in several files that currently "parse clean".

## Fix direction
Teach ParseCStructInto to lay out a nested anonymous aggregate member
`struct|union { ... } name;` as a nested record field: create a sub-record for the
anon body (UNION = every member at offset 0, size = max member size; STRUCT =
sequential), make `name` a field of that record type at the current offset, and
advance by the sub-record size (aligned). Then `outer.name.member` resolves
through the sub-record (the existing nested-struct-by-tag path already does field
chains, so the resolver mostly works once `name` has a real record type). Keep the
opaque fallback only for genuinely unsupported bodies (bitfields). Verify
`o.u.p` / `o.u.p->f` / `&(o.u.p + i)->f` and union overlap vs gcc, and confirm
self-host byte-identical (C-frontend-only).

## Attempt 1 + the real obstacle (2026-06-26, reverted)
Implemented nested-aggregate layout in ParseCStructInto (AddUClass sub-record,
recurse with the right isUnion, add the member as a tyRecord field declRec=sub) +
relaxed CStructBodyIsSimple to allow nested braces. Anonymous nested STRUCTs then
worked (`o.in.b`), but UNIONs and any struct with a field AFTER the nested
aggregate collided. The OBSTACLE is the CONTIGUOUS field model: FindUField scans
`[UClsFBase[ci], UClsFBase[ci] + UClsFCount[ci])`. Laying out the sub-record
APPENDS its fields to the shared UFld pool BETWEEN the parent's earlier and later
fields, so the parent's span (e.g. tag, a, x, u, n) exceeds its count (3) and
`[base, base+3)` misses the trailing fields -> collisions. Debug confirmed the
sub-record size/offsets are correct; only the pool layout breaks.

Real fix options: (a) buffer the parent's member descriptors and append ALL of the
parent's UFld entries contiguously AFTER its sub-records are laid out (two-pass
inside ParseCStructInto) — most localized; (b) give each record an explicit
field-index list instead of a contiguous [base,count) range; (c) lay sub-record
fields into a separate region. Until then a struct with a nested anonymous
aggregate stays opaque (current behaviour). LANDMINE hit during the attempt: a
literal brace in a Pascal source COMMENT opens a nested comment (compiler.pas has
NESTEDCOMMENTS ON) and eats source — keep braces out of comment prose.

## Resolution
- 2026-06-26 — FIXED via option (a): ParseCStructInto now BUFFERS the parent record`s
  field descriptors during the walk and appends them to the UFld pool contiguously
  AFTER the body (and any nested sub-records) are laid out, anchoring UClsFBase at
  that point. Nested struct/union members create a sub-record (recursively, right
  isUnion) and are buffered as tyRecord fields. CStructBodyIsSimple no longer bails
  on nested braces. Self-host byte-identical (C-frontend-only); fixture
  cnested_union_b44.c (=42). lua core 25 -> 27 (ldo + ltm unblocked).
