# C: post-increment/decrement used as a VALUE (`(p++)->f`, `x = a[i++]`)

- **Type:** feature/bug
- **Track:** C (C frontend)
- **Opened:** 2026-06-26
- **Found-by:** lua full-file bisection — lapi.c `lua_settop`:
  `setnilvalue(s2v(L->top.p++))` (= `&(L->top.p++)->val`).

## Symptom

`p++` / `p--` / `++p` used where its VALUE is consumed (not a bare statement)
miscompiles or hits `Unsupported linear node` (IRA=12 = AN_ASSIGN). E.g.
`(p++)->field`, `x = a[i++]`, `*p++ = v`. AST kind 12 (AN_ASSIGN) reaches
IRLowerAddress because the postfix `++` lowered to `p = p + 1` (an AN_ASSIGN) and
the field/deref then tries to take its address.

## Root cause

`CMakeIncDec` (cparser.inc) lowers both prefix and postfix `++`/`--` to
`lv = lv ± 1` (an AN_ASSIGN), with the comment "in statement / for-post context
the pre-vs-post value distinction is irrelevant, so both lower identically." That
is true only when the result is discarded. When the value is USED:
- post-increment must yield the OLD value, then advance;
- prefix must yield the NEW value;
- and the node must be a usable rvalue (here, a pointer base for `->`).

## Fix sketch

Give `CMakeIncDec` (or a new expression-context variant) a value-yielding form:
for `p++`, lower to: load `p` into a hidden temp `t`; store `p = t ± 1`; yield
`t` (the old value). For `++p`, yield the post-store load. Use the same hidden-
temp idiom as AN_TERNARY (AllocVar during lowering). The statement/for-post
callers can keep the cheap assignment form. Then `(p++)->field` lowers to a field
on the temp (a plain pointer value), no IRLowerAddress(AN_ASSIGN) needed.
Pervasive in lua/sqlite (stack/buffer cursors: `*top.p++`, `a[i++]`).
- RESOLVED 2026-06-26: AN_INCDEC node yields old/new value via a temp; pointer base supported. Fixture cincdec_value_b27.c.
