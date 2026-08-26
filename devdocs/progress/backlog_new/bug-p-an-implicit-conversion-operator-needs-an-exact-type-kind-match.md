---
track: P
prio: 45
type: bug
blocked-by: []
summary: "`operator := (const s: Int64): TCe` is found only when the source expression's type kind is EXACTLY tyInt64, so `c := 10` fails with `cannot assign Integer to record` while `c := someInt64` works. FPC applies the conversion to any assignment-compatible source. Found behind feature-p-fpc-global-operator-overload-declarations; it is the wall after the High(QWord) one in FPC's constexp.pas."
status: backlog
---

# An implicit-conversion operator is looked up on an exact type-kind match

- **Type:** bug (a refusal, not a wrong value) — Track P
- **Opened:** 2026-08-27, found while clearing
  [[feature-p-fpc-global-operator-overload-declarations]]

## Measured

```pascal
program w;
type TCe = record v: Int64; end;
operator := (const u: Int64): TCe;
begin Result.v := u; end;
var x: TCe; n: Int64;
begin x := 10; n := 7; x := n; end.
```

| declared source type | `x := 10` (a tyInteger literal) | `x := n` (a tyInt64 var) |
| --- | --- | --- |
| `Integer` | ok | **error: cannot assign Int64 to record** |
| `Int64`   | **error: cannot assign Integer to record** | ok |
| `QWord`   | **error: cannot assign Integer to record** | error |

FPC accepts every cell: the conversion operator applies to any source that is
assignment-compatible with the parameter type.

## Where it is

`FindOpOverload(Ord(tkAssign), typeKind, recId)` (`symtab.inc`) matches
`OvrlTypeKind[i] = typeKind` exactly, and the guard in `ir.inc:126` that lets
the assignment past the type check asks the same question. Neither widens
within the integer family, so the entry registered under `tyInt64` is invisible
to a `tyInteger` expression.

## Why it is not a one-line widening

The table is keyed on the SOURCE type and carries no destination, so "retry
over the integer family" can find an operator whose result is a completely
different record. With two conversion operators in scope —
`operator := (const a: Int64): TA` and `operator := (const b: Integer): TB` —
a widened lookup for `someTA := 10` could answer with TB's. FPC resolves this
by picking the best assignment-compatible match **for the destination type**,
which is information this lookup does not currently have.

So the fix is either (a) key the conversion entries on the destination record
as well and match source by assignment-compatibility, or (b) keep the exact
lookup and add a widening retry only when it is unambiguous. (a) is the one
that matches what FPC actually does; (b) is smaller and would leave a
second-order gap. State the choice in the ticket before writing code.

## Why it matters

`operator :=` is how a Pascal library gives a record value semantics against
builtin types, and an integer LITERAL is the commonest thing anyone assigns to
one — so the exact-match rule fails on the first line most users write. FPC's
own `constexp.pas` declares the pair `(const u:qword)` / `(const s:int64)` and
then assigns plain integer constants throughout, which is the corpus case.

## Gate

The table above, all cells, oracled against `fpc -Mobjfpc` 3.2.2. Plus the
Pascal suite green and self-host byte-identical. The corpus gate is
`constexp.pas` compiling once
[[feature-p-const-evaluator-carries-unsigned-64-bit]] clears the `High(QWord)`
wall ahead of it.
