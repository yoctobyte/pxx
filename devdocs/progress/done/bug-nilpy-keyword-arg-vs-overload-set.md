---
reopened: 2026-08-04
summary: "nilpy: a keyword argument is resolved against ONE overload, so it fails when a sibling has the parameter"
type: bug
track: N
prio: 50
status: done
owner: claude-AN
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

## Log
- 2026-08-01 — resolved, commit 7be01f05f.


## 2026-08-04 — NOT finished: the promoter is scoped to ONE unit, and pylib/pyeval are two

Found while implementing `min(xs, key=len)` for
[[bug-nilpy-list-sort-rejects-key-and-reverse-with-a-bare-parse-error]]. The
2026-08-01 resolution (`7be01f05f`) generalized the promotion correctly, but
kept the sibling search **scoped to the same unit** as the initially-chosen
overload — deliberately, and its own comment says why. That leaves a case it
cannot reach:

```python
words = ["bb", "a"]
print(min(words, len))        # 'a'  — correct, positionally
print(min(words, key=len))    # error: min has no parameter named 'key' in the
                              # overload taking 2 argument(s) — a sibling
                              # overload taking 2 does.
```

`min` resolves first to the two-Variant scalar form in **pylib**, while the
list form that takes `key` has to live in **pyeval** (only pyeval has
`PyCallKey1`, and `pyeval uses pylib`, not the reverse). Different units, so
`PyPromoteProcOverloadByKwAt` refuses to promote.

The scoping is right in general — same-named routines really do collide across
unrelated RTL units — and wrong here: pylib and pyeval are not two unrelated
units, they are one language's builtins split for a layering reason. So the fix
is a way to say "these units are one overload set" (a builtin-unit group, or
`NilPyUserCode`-gated widening to any builtin unit), not removing the scope.

Note this is now a BLOCKER, not a nuisance: `key=` is the only valid Python
spelling, so the positional form is not a workaround for user code, and the
`min`/`max` implementation was reverted rather than landed inert.

Reopened — moved back to `backlog/`.


## Resolved 2026-08-04 — the cross-unit half, which is the one that mattered

The ticket's own repro (`html.escape("it's", quote=False)`) has worked since
`7be01f05f`; re-measured before touching anything. What was left is the case
found yesterday while implementing `min(xs, key=len)`: the promoter's sibling
search was scoped to the **same unit** as the initially-chosen overload.

That scoping reads as a safety rule and is one, but it excluded the shape that
matters most here, because it is how one Python builtin is normally split in
this tree: anything needing `PyCallKey1`'s callable dispatch has to live in
`pyeval`, since `pyeval uses pylib` and not the reverse. So `min` resolves first
to **pylib**'s two-Variant scalar form while the list form carrying `key` is in
**pyeval**, and the promotion refused to cross:

```python
print(min(words, len))       # 'a'  — worked
print(min(words, key=len))   # "min has no parameter named 'key'"
```

`key=` is the only valid Python spelling, so the positional form was never a
workaround — which is why this was a blocker rather than a nuisance and why the
`min`/`max` implementation was reverted yesterday instead of landed inert.

### Fix: same unit first, any unit second

Two loops rather than one. The same-unit pass still wins whenever it finds
something, so no genuine Pascal overload set changes its answer; the cross-unit
pass runs only when the same unit has nothing.

Widening is safe **here specifically**, and the reasoning is narrower than "the
scope was wrong":

- the promotion already demands an exact **parameter-name** match that the
  chosen overload lacks — a far more selective key than the routine name alone,
  which is what the original comment was worried about;
- NilPy's unit scope is **flat by design**, so a visible same-named routine is a
  candidate for that call anyway;
- and the whole routine is `isNilPy`-gated, so Pascal's resolution is untouched.

### `min`/`max` with `key=` landed on top of it

The list forms moved from `pylib` into `pyeval` **whole** (not as siblings —
keeping the keyless form in pylib would make `min(xs)` ambiguous across the two
units) and gained `key: Pointer = nil`. They compare the KEYS and return the
ELEMENT, and on a tie return the FIRST, as CPython does. That closes the
`min`/`max` half of
[[bug-nilpy-list-sort-rejects-key-and-reverse-with-a-bare-parse-error]]; only
`xs.sort(key=, reverse=)` remains there, blocked on a separate frontend rewrite.

### Also fixed in passing: a temp-file collision between two tests

`test_nilpy_user_def_shadows_builtin` (added earlier today) was writing
`/tmp/test_nilpy_shadow26`, already used by `test_nilpy_user_class_shadows_builtin`.
Harmless in a sequential `make`, a race under parallelism. Renamed.

### Verified

`test/test_nilpy_kwarg_overload.npy` + `.expected` (an expected FILE, not an
inline `printf` — the output contains quotes), wired into `make test-nilpy`:
`min`/`max` with and without `key=`, `sorted` with `key=`/`reverse=`/both, the
scalar and variadic `min`/`max` forms unchanged, the tie-returns-first rule, and
the ticket's original same-unit `html.escape` repro in both arities. Diffed
against CPython, identical. `tools/gate.sh quick` GREEN, self-host
byte-identical.

## Log
- 2026-08-04 — resolved.
- 2026-08-04 — resolved, commit 4970562a5.
