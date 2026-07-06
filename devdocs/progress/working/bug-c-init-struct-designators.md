# C struct field designators `.field = v` in braced initializers

- **Type:** bug (cfront init lowering). Track C. Slice of
  [[bug-c-init-designated-and-nested]].
- **Found:** 2026-07-06 c-testsuite; scoped 2026-07-06 during that ticket's triage.

## Cases
- 00048 `struct S s = { .b = 2, .a = 1 };` (local + global)
- 00049 `struct S s = { .p = &x, .a = 1 };` (designator + &global)
- partial 00050 / 00148 (also need array designators / brace elision — sibling tickets)

## Symptom
Field values assigned in declaration order; the `.field` designator is ignored,
so `{ .b = 2, .a = 1 }` writes a=2, b=1.

## Fix (both paths — a "current field index" cursor)
Before reading each element value, if the token stream is `. ident =`, resolve
the field with `FindUField(recId, name)` and set the running `fldI` to it (then
consume `. ident =`); otherwise keep the sequential `fldI`. After each element,
`fldI` advances by one (C 6.7.8: a designator repositions, then filling
continues from there).
- **Local:** `ParseCLocalDeclAST`, the non-array record loop at ~cparser.inc:2626.
- **Global:** the PendingInit materializer at ~cparser.inc:3721 (per-field
  `UFldNOff/UFldNLen` writes).

## Gate
00048/00049 exit 0; drop them from `test/c-conformance/pxx.skip`; add a
regression test; `make test` + self-host byte-identical.
