---
summary: "nilpy: a keyword argument is resolved against ONE overload, so it fails when a sibling has the parameter"
type: bug
track: N
prio: 50
---

# nilpy: keyword arguments and overload sets do not mix

- **Type:** bug (Nil-Python frontend) — **Track N**
- **Opened:** 2026-07-27. Hit twice in one session, from opposite directions.

## Repro

A Pascal unit exposing two arities (which is how a shim gives Python's
`f(x, flag=True)` both spellings, since a unit-QUALIFIED call does not fill a
Pascal default — see the note below):

```pascal
function escape(const s: AnsiString): AnsiString; overload;
function escape(const s: AnsiString; quote: Boolean): AnsiString; overload;
```
```python
html.escape("it's", False)        # fine
html.escape("it's", quote=False)  # error: escape has no parameter named 'quote'
```

`PyKwArgIndex` resolves the name against the ONE proc the call site has in hand,
which is the first overload found. The one-argument overload has no `quote`, so
the call fails even though a sibling in the set has exactly that parameter.

The same thing bit the tkinter façade from the other side: `configure` could not
be both `configure(opts: string)` and `configure(state=…, width=…)`, because the
string overload won the lookup and the keyword name then failed. That one was
worked around by renaming the raw form to `configure_raw`.

## Shape

The keyword name has to be resolved against the overload SET, not one member —
either by scanning every proc of that name for the parameter (and letting the
existing type/arity matching pick the final one), or by deferring keyword binding
until after overload resolution.

## Related: a qualified call does not fill Pascal defaults

Found while writing lib/rtl/html.pas: `html.escape(s)` against
`function escape(const s: AnsiString; quote: Boolean = True)` reports "no overload
matches these arguments" — the trailing default is not filled on the
unit-qualified NilPy path, which is why the shim needs two arities at all. Worth
checking whether that is the same code path or a second, separate gap.
