---
track: A
prio: 40
type: bug
commit: PENDING-COMMIT
blocked-by: []
summary: "`int(\"1\" + \"2\")` raised ValueError on garbage text and `str(\"a\" + \"b\")` printed empty: two literals are folded to one interned literal at IR time, but the expression they replace was typed tyAnsiString, so the call path passed the raw literal pointer where a managed handle was promised and its length was read out of the bytes before the text."
---

# A folded string literal reaches a managed parameter raw

```python
print(int("1" + "2"))    # CPython 12
                         # pxx: ValueError: invalid literal for int() with base 10:
                         #      '1212ab\xdc\xb3a...'
print(str("a" + "b"))    # CPython ab      pxx printed an empty string

x = "a" + "b"
print(str(x))            # ab              — correct, via a name
```

Found 2026-08-15 by a CPython differential sweep. Track A: the fold is in
`ir.inc` and is target-independent, so the same mismatch is reachable from any
frontend whose parser types a literal `+` chain tyAnsiString.

## Cause — the AST's type and the lowered VALUE disagreed

`IRLowerAST`'s binop arm folds `'a' + 'b'` to one interned literal and returns
an `IR_CONST_STR` typed **tyString** — deliberately, and the note there records
why tagging it tyAnsiString is not the fix (a static literal pointer treated as
a heap handle is released at scope exit).

But the AST node it replaces was typed **tyAnsiString** by the parser, and
`IRLowerCallArg` decides how to pass a string argument from `ASTTk[argAST]`.
Seeing tyAnsiString it concluded "already a managed handle, pass it through",
so the callee received a pointer to static bytes and read its length from the
eight bytes in front of the text — hence a ValueError quoting the digits
followed by heap junk, and an empty string from `pystr_of`.

The fold now materialises through a hidden OWNING local when the replaced
expression was tyAnsiString — the store carries the literal-to-managed
conversion, the load hands over a real handle, and scope exit releases it.
That is exactly what `IRPromoInitFromLiteral` already does, for the same
reason, three thousand lines up.

Third instance today of one rule: **take the kind from the value, not from the
AST** — see `project_variant_store_kind_came_from_the_ast_not_the_value` and
[[bug-nilpy-int-of-a-division-reads-the-doubles-bits]].

Consumers that were already right stay right, and that asymmetry is what made
this survivable: `len`, `==`, `.upper()`, `list()`, `.encode()` and a further
`+` all take the literal at a position that re-reads its type, so only the
managed-parameter path saw the mismatch.

## Gate

`test/test_nilpy_folded_literal_as_argument.npy` (+`.expected`, in the
Makefile), byte-identical to CPython: `int`, `str` and `float` over a folded
literal; the implicit `"1" "2"` spelling the lexer turns into the same `+`; via
a name as the control; the consumers that were already correct; a folded literal
as an ordinary def argument, inside a list, as a dict value and as a dict KEY;
one used twice; and a three-part fold. `gate.sh quick` GREEN — self-host
converged in two rounds, the compiler's own build being a consumer of the fold.
