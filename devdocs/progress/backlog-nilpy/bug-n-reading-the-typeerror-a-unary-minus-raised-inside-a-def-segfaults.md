---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`def neg(v): return -v`; `try: neg('s') except TypeError as e: str(e)` SEGFAULTS (print(e) too), while the same handler around a binary operator's TypeError (`1 - v`) prints its message. The exception is raised and caught (a handler that does not touch `e` runs); reading `e` is what dies. Pre-exists the 2026-09-16 pyvar_neg change (the old `0 - v` rewrite segfaults identically on 669685aeacc9103c)."
status: open
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
