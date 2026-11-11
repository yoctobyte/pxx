---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`def neg(v): return -v`; `try: neg('s') except TypeError as e: str(e)` SEGFAULTS (print(e) too), while the same handler around a binary operator's TypeError (`1 - v`) prints its message. The exception is raised and caught (a handler that does not touch `e` runs); reading `e` is what dies. Pre-exists the 2026-09-16 pyvar_neg change (the old `0 - v` rewrite segfaults identically on 669685aeacc9103c)."
status: done
---

# Reading the TypeError a unary minus raised inside a def segfaults

Repro (both on the pre-fix binary 669685aeacc9103c and on the pyvar_neg one):

    def neg(v):
        return -v
    try:
        neg("s")
    except TypeError as e:
        print("TypeError:", e)      # SIGSEGV; `s = str(e)` too

Control, same handler, prints `TypeError: unsupported operand type(s) for -: 'int' and 'str'`:

    def sub(v):
        return 1 - v
    try:
        sub("s")
    except TypeError as e:
        print("TypeError:", e)

And `except TypeError as e: print("caught")` runs for the negation, so the
raise and the catch are fine; the exception OBJECT the handler binds is not
readable. The difference between the two shapes is not the message (the new
pyvar_neg builds its message with the same TypeError.Create the binary
operator uses) — suspect the frame the unary path raises from (a def whose
result is a variant `-v`) leaves the handler's `e` slot pointing at freed or
unboxed memory. Found while landing pyvar_neg (test_nilpy_negating_a_variant_
zero_keeps_its_sign keeps its str row to `print("variant str TypeError")`
for exactly this reason).

## Resolution (2026-11-11)

The crash was never in the handler. gdb on a `-g` build put it inside `neg`:
the call site passes a str, so the frontend typed `v` as str, and the
unary-minus arm built a plain AN_NEG over it -- `neg %rax` on the string
POINTER, then an addref of the result. The `1 - v` control worked because the
binary operator has its own str check.

Fix (pyparser.inc, pasparser_expr.inc): new `PyUnaryOperandIsNotANumber`
(str, bool, or a pylib object handle). Those operands go through
`pyvar_neg` / `pyvar_pos`, which box to a variant and raise CPython's
`bad operand type for unary -: 'str'`. Found next to it and fixed in the same
place:

- A typed list (or a user class with no `__neg__`/`__pos__`) raised the generic
  `unsupported operand type(s) for this operator`; it now gets CPython's message.
- `-True` / `+True` printed `True` (AN_NEG kept the Boolean type); now -1 / 1.
- A leading `+` (ParseSimpleExpr) on a str or bool now dispatches the same way.

Test `test/test_nilpy_a_unary_sign_on_a_str_list_or_bool.py` (row `unarystr26`).
