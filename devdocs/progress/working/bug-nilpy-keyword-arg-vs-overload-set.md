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

## 2026-07-30 — diagnostic landed; the BINDING is still not fixed

Deliberately partial, and the ticket stays OPEN. What changed: when a keyword
name is absent from the chosen overload but present on a sibling, the error now
says so and names both arities, instead of the flatly untrue "escape has no
parameter named 'quote'":

```
Nil Python: escape has no parameter named 'quote' in the overload taking 1
argument(s) — a sibling overload taking 2 does. Keyword names are resolved
against the chosen overload, not the whole set: pass it positionally for now
(bug-nilpy-keyword-arg-vs-overload-set)
```

That is worth having on its own — the name DOES exist, and nothing in the old
message let the reader guess where — but it is a signpost, not the fix.

### Why the fix was not attempted here

`PyKwArgIndex` is handed one `mpi` and cannot re-target: by the time it runs, the
caller has chosen the overload and may already have parsed arguments against that
signature, so switching mid-list corrupts the chain. The fix has to happen
BEFORE argument parsing — pre-scan the call's token range for `ident =` pairs at
paren depth 1, and let those names participate in overload selection alongside
arity and types.

There are SEVEN call sites that call PyKwArgIndex (pyparser.inc 6192, 6240, 6610,
7242, 7604; parser.inc 5738, 8645, 12062), covering plain calls, unit-qualified
calls, method calls and constructor keywords. Fixing one and leaving six is worse
than fixing none — the failure would then depend on which spelling you used. So
this wants doing as one pass, with the pre-scan factored into a helper all seven
share.

Also still open, from the note above: a unit-qualified call does not fill Pascal
trailing DEFAULTS, which is the reason the html shim needs two arities at all.
Check whether that is the same selection path before starting — if it is, both
fall out of one change.
