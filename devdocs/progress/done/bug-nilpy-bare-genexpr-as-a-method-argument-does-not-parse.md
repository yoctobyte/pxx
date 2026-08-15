---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`obj.take(x for x in xs)` — a bare generator expression as a METHOD argument — dies with `undefined variable (x)`. The diversion that parses one (PyBareGenExprAhead) is wired into the ordinary-call argument path and the str-method path, but not into the user-method call path."
---

# A bare generator expression is refused as a method argument

```python
xs = [1, 2]
print("".join(str(x) for x in xs))     # works
print(sum(x for x in xs))              # works

class C:
    def take(self, s):
        return list(s)

print(C().take(x for x in xs))         # pascal26: error: undefined variable (x)
```

Found 2026-08-15 while adding `TPyFile.writelines`, whose first test used
`f.writelines(str(i) + "\n" for i in xs)` — the natural spelling — and could not
compile.

## Cause

A bare genexpr must be diverted BEFORE its element expression is parsed, since
that expression names the loop variable, which is not in scope until the `for`.
`parser.inc`'s ordinary-call argument loop does exactly that:

```pascal
else if isNilPy and PyBareGenExprAhead then
  CurASTNode := PyParseCompExprValue(False)
```

and the comment there notes the str-method argument path already did the same.
The USER-METHOD call path was the sibling left behind — the third arm of the
same case, which is the shape `devdocs/dev/normalise-dont-special-case.md`
describes: "if you fix a bug on one arm of a double case, grep for the sibling".

Loud, and the message names the loop variable rather than the construct, so it
reads as a scoping bug in the caller's code.

## Shape of a fix

Add the same two-line diversion to the method-call argument loop. Worth
grepping for every place an argument expression is parsed at the same time —
`PyBareGenExprAhead` should be asked by ALL of them, and a fix that adds a third
copy rather than one shared helper is the one that will need a fourth.

## Gate

`.npy` diffed against CPython: a genexpr passed to a user method, to a
`TPyFile.writelines`, to a pylib container method, to a constructor
(`C(x for x in xs)`), and the two forms that already work as controls.

## Resolved 2026-08-15 — in the one routine, not a third copy

The ticket asked for "the same two-line diversion in the method-call argument
loop", and warned that a third copy would need a fourth. It did not need any
copy: **`ParseArgExpr` already IS the shared entry point** — every call argument
under NilPy goes through it (43 call sites), and it exists precisely because a
NilPy argument obeys Python precedence rather than Pascal's. The genexpr
diversion had simply been added at two CALLERS instead of inside it.

So the fix is the diversion moved into `ParseArgExpr`, and every argument
position gets it at once: user methods, methods on a field receiver,
`TPyFile.writelines`, constructors, pylib container methods, and the ordinary
calls that already worked. The old check at the ordinary-call loop is left in
place: it fires first and does the identical thing, so removing it would be
churn in Track A's shared file for no behaviour.

Related and still open: [[bug-nilpy-star-unpack-into-a-builtin-or-a-bound-method-is-refused]]
has the same haves-and-have-nots list for `*args`, but `*` is NOT an
expression, so it cannot be diverted from inside `ParseArgExpr` the way this
was — that one really does need per-loop work or a restructure.

## Gate

`test/test_nilpy_bare_genexpr_arguments.npy` (+`.expected`, in the Makefile),
byte-identical to CPython: a bare genexpr passed to `sum`/`max`/`min`/`list`/
`sorted`/`any`/`all`/`tuple`/`set`/`dict`/`len`, to `"".join` and `", ".join`
with a filter, to a user method, to a method on a FIELD receiver, to a
two-argument method beside a fixed argument, to a user def, and to
`f.writelines`. `gate.sh quick` GREEN.
