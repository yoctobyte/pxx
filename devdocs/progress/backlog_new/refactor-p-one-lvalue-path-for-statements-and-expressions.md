---
slug: refactor-p-one-lvalue-path-for-statements-and-expressions
title: "Two lvalue parsers, and the statement one keeps missing what the expression one learned"
track: P
prio: 35
type: refactor
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-24
summary: "An assignment TARGET is parsed by a second, smaller copy of the lvalue walk in pasparser_stmt.inc, which resolves every `.name` as a field and ends on Expect(':='). Every capability the expression path gains has to be re-added there by hand, and three bugs so far are exactly that omission: the builtin pointer-name fallback, the PChar adapter, and the deref-then-index shape. The statement path should delegate, as its own cast-headed-CALL arm already does."
---

# The shape

`ParseStatementAST` handles `<name>(...)^.f := v` itself: it builds the
AN_PTR_CAST, walks `^` and `.field` in a small loop, then `Expect(tkAssign)`.
`ParseLValueAST` / the expression parser handle the same syntax with far more in
them — default properties, class casts, metaclasses, the `-2` PChar adapter,
depth-carrying derefs, index-over-deref, builtin pointer names.

The statement copy has to be taught each of those separately, and the failure
mode is always the same: the expression spelling works, the assignment-target
spelling is a compile error or a wrong node.

Known instances, all measured:

- `PInteger(p)^ := 42` was "undefined variable" while `WriteLn(PInteger(p)^)`
  compiled — [[bug-p-a-builtin-pointer-cast-is-refused-as-an-assignment-target]]
  (fixed by copying two lines).
- `PChar(p)^ := 'x'` needed the `-2` adapter copied over as well (same ticket).
- The deref chain's own arms (AN_FIELD / AN_INDEX / AN_CALL depth reads) live
  only in `pasparser_lval.inc`, so any target-position use of those shapes is a
  separate question nobody has swept.

# What to do

The statement path already knows how to hand off: its cast-headed-CALL arm says
*"hand the whole thing to the expression parser, which already builds this chain
correctly"*. Do that for the ASSIGNMENT case too — parse the target with the
expression lvalue parser, then `Expect(':=')` and build AN_ASSIGN over whatever
came back — and delete the duplicated walk.

The catch to measure first: the expression parser resolves a trailing `.name` as
a field/method/property and may CALL it, which in target position must not
happen; and it consumes `[` as an index or a default property. Both are decided
before `:=` is seen, so the hand-off needs the same "this is an assignment
target" flag the class-cast arm passes today. Sweep with a differential over
every target shape (bare, field, index, deref, cast, property, default
property) before and after.

# Gate

Track P's, plus a target-shape differential against fpc 3.2.2, plus the
self-host fixedpoint (this path parses every assignment in `compiler.pas`).
