---
summary: "`g(3).show()` — a selector on the RESULT of calling a callable VALUE is a parse error (`expected expression`). Binding the result first (`o = g(3); o.show()`) works, so only the chained arm is broken. Applies to any callable value: a def taken as a value, and now a class."
type: bug
track: N
prio: 50
found-by: claude-AN
status: done
owner: claude-an-1
---

# A method call on a callable value's result is refused

- **Type:** bug (parse error on valid Python) — Track N
- **Opened:** 2026-08-10
- **Found by:** the gate cases for [[feature-nilpy-class-as-a-value]], where
  every `cls(3).show()` had to be rewritten to two statements.

## Repro

```python
class A:
    def __init__(self, v): self.v = v
    def show(self): print("A", self.v)

def mk(v):
    return A(v)

g = mk
g(3).show()
```

CPython prints `A 3`. pxx:

```
pascal26:11: error: expected expression
  near: mk  g    >>>  show
```

Confirmed pre-existing at `pinned`, and NOT specific to classes — `g` here is an
ordinary def taken as a value. `o = g(3); o.show()` works, so the call and the
method both work; only the chain is refused.

## Shape

The variant-callee call (`pyvar_callvN`) is built where the expression parser
does not go on to accept a selector on its result. Pascal had the mirror image
of this on the STATEMENT side twice — `bug-pascal-statement-call-result-selector`
(`.`) and `bug-a-assignment-through-a-pointer-returned-by-a-function-call-is-dropped`
(`^`/`[`) — and both were one branch that only knew some of the selector tokens.
Check `[` and `.attr` here too, not just `.method()`.

## Gate

`make test-nilpy` + self-host byte-identical, with a `.npy` case covering
`g(3).m()`, `g(3).attr`, `g(3)[0]` and the class-value spelling `cls(3).m()`,
diffed against CPython.

---

## Root cause: nine suffix loops run as a SEQUENCE, so order decided reachability

`ParseFactor` handles Python's postfix suffixes with **nine** separate `while`
loops, each claiming one (suffix token, receiver shape) pair — `.method()` on a
str base, on a call result, on a class expression, on a variant; `[i]`; a
dynamic call through a variant; the `__call__` protocol. They run once each, in
source order.

Python's grammar has no such ordering: a primary takes `.attr`, `[i]` and
`(args)` in ANY sequence, any number of times. `g(3).show()` needs the
dynamic-call loop (ninth) and then the call-result method loop (third) — 
backwards through the sequence — so the `.` was left for nobody and the parse
died. `o = g(3); o.show()` worked because each statement needs only one pass.

Nine mechanisms for one concept is far past the two-is-a-smell line. The honest
fix is ONE dispatcher over the suffix tokens; that is a rewrite of a hot region,
so this change instead wraps the cluster in a **re-entry loop that repeats until
a pass consumes no tokens**. Order stops mattering without touching any of the
nine loops, and the dispatcher stays recorded as the real target. Termination is
on TOKEN PROGRESS, not on the node changing — a loop that rewrote the node
without consuming input would otherwise spin.

## Two of the ticket's three asks land here; the third is split out

The ticket asked to check `[` and `.attr` too, not just `.method()`. Measured:

| shape | before | after |
| --- | --- | --- |
| `g(3).show()` | parse error | works |
| `g(3).show().upper()` | parse error | works |
| `g()[1]`, `g()[1:][0]` | parse error | works |
| `b(4)[1]` (`__call__` then subscript) | parse error | works |
| `g(3).v` (bare attribute) | parse error | **still refused** |

`.attr` is NOT a parser-only gap, which is why it is split rather than forced
in: routing it to `PyMakeDynAttrGet` makes it parse and then raises
`AttributeError: 'A' object has no attribute 'v'`, because `pydynattr_get_v`
consults only the dynamic-attribute side store and never the class's DECLARED
fields. That version was written, measured and reverted — converting a loud
compile error into a plausible-but-false runtime AttributeError moves the
failure away from the cause. Filed with the diagnosis and the RTTI
`FieldCount`/`FieldsPtr` route as
`bug-nilpy-a-bare-attribute-on-a-call-result-is-refused`.

## Verification

`test_nilpy_postfix_after_parens` extended (the file that already holds the
parenthesised-callee cases). Byte-identical to CPython's stdout; `pinned`
cannot compile the file at all. `tools/gate.sh quick` GREEN, self-host
fixedpoint. Breadth offloaded to Track T, which is UP (plexus through
d10a982af010).

## Log
- 2026-08-11 — resolved, commit PENDING-COMMIT.
