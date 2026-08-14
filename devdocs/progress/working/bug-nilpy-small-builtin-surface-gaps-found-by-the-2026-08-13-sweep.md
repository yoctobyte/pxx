---
track: N
prio: 40
type: bug
blocked-by: []
summary: "Four small refusals found by the 2026-08-13 CPython sweep: `issubclass(A, B)`, `d.update(k=v)` (the keyword form), `key=str.lower` (an unbound method as a callable value), and Unicode special-casing in upper()/lower() ('ß'.upper() is 'ß', CPython 'SS'). Each is a parse error or a wrong string, none is a silent wrong VALUE"
status: working
owner: claude-A-N
---

# Small builtin-surface gaps from the 2026-08-13 sweep

- **Type:** bug (refusals / one wrong string) — **Track N**
- **Found:** 2026-08-13, sweeping the str / dict / sequence / class surface
  against CPython. The rest of those four files matched CPython exactly; these
  are what did not.

| shape | pxx | CPython |
| --- | --- | --- |
| `issubclass(Derived, Base)` | `error: unexpected token` | `True` |
| `d.update(z=6)` (keyword form) | `error: unexpected token` | updates |
| `sorted(xs, key=str.lower)` (an UNBOUND method as a value) | `error: unexpected token` | sorts |
| `"ß".upper()` | `ß` | `SS` |
| `"İ".lower()` | `İ` | `i̇` |

The first three are diagnostics at compile time, which is the honest failure
mode; the case-mapping rows are a wrong VALUE but only for non-ASCII letters
whose case change alters LENGTH (the ASCII and Latin-1 letters are correct).

## Notes for whoever takes it

- `issubclass` has a runtime twin already: `pyisinstance_v` walks the RTTI
  parent chain, and `issubclass` is the same walk from a class ref rather than
  an instance — the frontend intercept is what is missing.
- `d.update(**kw)` / `d.update(k=v)` is the dict twin of
  [[bug-nilpy-kwargs-and-star-unpack-at-a-construction-are-refused]]: a keyword
  argument reaching a pylib method.
- `str.lower` as a VALUE is the unbound-method form of
  [[bug-nilpy-map-over-a-bound-method-segfaults]] (which fixed the BOUND form,
  `obj.method`). A str method has no instance to bind, so it wants the same
  callable-value treatment a plain def gets.
- Case mapping: `pystr_upper`/`pystr_lower` map byte by byte, so a mapping that
  changes the code-point COUNT cannot be expressed. Worth doing only with the
  wider unicode question, not on its own.

## Gate

A `.npy` diffed against CPython covering each row, kept in one file so the four
are visible together.


## Row 1 DONE 2026-08-13 — `issubclass`; the other three stay open

`issubclass(D, B)` now answers, matching CPython on every shape swept: direct,
transitive, reversed, unrelated, reflexive, a tuple second argument (hit and
miss), and used as a VALUE — in an `if`, in a list, and composed with
`and`/`not`.

**Folded at compile time, deliberately.** With class NAMES the answer IS a
compile-time fact: the class graph is fully known and nothing about it can
change at run time, so the intercept walks `UClsParent` at parse time and emits
a bool literal. No runtime helper, no new pylib entry point, so no re-pin.

**A class held in a VARIABLE is refused**, with a diagnostic that says exactly
that rather than the misleading "unknown class" the first cut produced:

    issubclass() takes class NAMES; t is a variable, and there is no runtime
    subclass test yet

The ticket's own note says `pyisinstance_v` has the parent-chain walk and "the
frontend intercept is what is missing". That is true for the NAME form and not
for the variable form: `pyisinstance_v` walks from an INSTANCE, and there is no
`pyissubclass_v` to call. Writing one is a `compiler/builtin/**` change, which
carries a stabilize+pin obligation — out of proportion to a row of a
small-gaps sweep, and worth doing when something actually needs it. Refusing at
the boundary of what can be answered exactly is the same call this dialect makes
elsewhere (the ESP PAL's `PAL_ERR_UNSUPPORTED`, `__pxxSig*` on xtensa).

Not shadow-guarded, matching the isinstance arm beside it: neither checks
`FindProc`, so a user `def issubclass(...)` loses to the intercept. Consistent
with its sibling is better than one lone divergence; worth revisiting for both
at once if it ever bites.

### Still open in this ticket

- `d.update(z=6)` — a keyword argument reaching a pylib method.
- `sorted(xs, key=str.lower)` — an UNBOUND method as a callable value.
- `"ß".upper()` / `"İ".lower()` — case mappings that change the code-point
  COUNT, which the ticket already scopes to the wider unicode question rather
  than to itself.

Test `test/test_nilpy_issubclass.npy`, expectations from CPython, wired into
`test-nilpy`. Gate: `make compiler/pascal26` fixedpoint + `gate.sh quick` GREEN.


## Parked 2026-08-13 after row 1 — measured notes on the remaining three

Moved to `unfinished/` rather than left in `working/`: row 1 is landed and
pushed, the other three are untouched, and none of them is the small job the
"small gaps" framing suggests.

### The table's diagnostics are out of date for two rows

Both now produce a precise message rather than the recorded "unexpected token",
so do not go looking for a parser crash:

    d.update(z=6)  ->  TPyDict.update has no parameter named 'z'
    d.update(**e)  ->  expected expression

### `d.update(z=6)` is not a keyword-binding gap — the keywords are KEYS

This is the trap in that row. `PyKwArgIndex` is behaving correctly: `update`
really has no parameter called `z`, and no amount of fixing keyword binding will
change that. Python's `dict.update(**kw)` / `dict(a=1)` is a **special case in
the language itself** — the keyword NAMES become dict keys, not parameter names
— so the lowering wanted is `recv.setitem("z", 6)` per keyword, not a binder
change.

That makes it a design question rather than a fix: the arm has to live where the
receiver's class is known (the method-call site), and it must not become a
second path that later diverges from the ordinary keyword path — the failure
mode `devdocs/dev/normalise-dont-special-case.md` describes and this file's
sibling tickets keep paying for. `dict(a=1)` wants the same arm, so whoever does
it should do both at once.

Related: [[bug-nilpy-kwargs-and-star-unpack-at-a-construction-are-refused]] is
the `**` half and should probably be taken together with this.

### The other two are unchanged in scope

`sorted(xs, key=str.lower)` still wants the unbound-method-as-value treatment
(the bound form was fixed by [[bug-nilpy-map-over-a-bound-method-segfaults]]),
and the unicode case mappings are already scoped by this ticket to the wider
unicode question rather than to themselves.

## Row 3 DONE 2026-08-13 — `str.lower` as an UNBOUND method value

`sorted(xs, key=str.lower)`, `map(str.upper, xs)`, `f = str.upper; f("hi")` and
`map(str.isdigit, ...)` all match CPython now.

**No new runtime.** The str-method table (`PyStrMethodInfo`) already names the
pylib routine `s.lower()` desugars to, so the unbound form is that same routine
taken as a value — one table, both forms, nothing to drift. The Variant callable
ABI is bridged by `PyGetOrMakeCallableWrapper`, whose hand-built
`return realproc(a0)` body already applies the ordinary argument coercion; that
is exactly what it exists for, so `pystr_lower(const s: AnsiString)` needs no
Variant twin in pylib.

The wrapper is requested **at this call site**, deliberately, rather than by
widening `PyMakeFuncValueFor`'s all-Variant-parameters gate — that gate answers
the same question for every other callable value, and moving it would move
unrelated code onto a path nobody swept.

### TWO entry points, because there are two

`key=str.lower` reaches ParseFactor; `map(str.upper, xs)` reaches
`PyMakeFuncValue`. Building it in only one is the
`normalise-dont-special-case.md` shape this file's siblings keep paying for, so
both call the one builder.

### The `map(str, xs)` collision — found by testing the sibling, not by reading

`map(str.upper, xs)` still failed after both entry points were in, because
map's **conversion** arm (`map(int, xs)` / `map(str, xs)` / `map(float, xs)`)
matches on the leading token alone: it consumed `str` and then failed on the
dot. The two forms are told apart by what follows — a comma is the conversion,
anything else is not — so the arm now requires it. The conversion rows are in
the new test for that reason.

### Refused, by name

Only the str methods whose pylib entry takes the receiver and nothing else. A
one-argument method (`str.split`, `str.replace`) is an arity-2 callable in
Python, which this shape cannot express, so it says so:

    Nil Python: str.split cannot be taken as a value — only the str methods
    that take no arguments can

Test `test/test_nilpy_unbound_str_method.npy` + `.expected` (from CPython),
wired into `test-nilpy`. Gate: `make compiler/pascal26` fixedpoint +
`tools/gate.sh quick` GREEN + the full `make test-nilpy` family sweep (this
change moves a parse gate, which the sweep is for).

### Still open in this ticket

- `d.update(z=6)` — the keywords-are-KEYS lowering (see the parked note above).
- `"ß".upper()` / `"İ".lower()` — case mappings that change the code-point
  count, scoped to the wider unicode question.


## Row 2, HALF done 2026-08-13 — `dict(a=1)` ships, `d.update(a=1)` does NOT

The parked note above called this a design question and named the answer: the
keyword NAMES are dict KEYS, so the lowering is a dict, not a binder change.
Built exactly that — one builder, `PyBuildKeywordDict`, which constructs the
dict the keyword run describes the same way a `{...}` literal is constructed
(hoisted temp, one `setitem` per pair, `pydict_merge` for a `**` spread) and
hands it over as the single dict argument both callees already take. No second
update path, no new pylib entry point.

**Shipped and matching CPython:** `dict(a=1, b=2)`, `dict(**src)`,
`dict(**src, r=9)`, values that are ordinary expressions including `None` — and
**`dict()`**, which was refused before this (`no overload of dict matches these
arguments`, on the pinned binary too) and rides the same builder as the keyword
run with no keywords.

### NOT shipped: `d.update(a=1)`. It segfaults on TWO keywords.

This is the part worth recording, because everything about it looks fine:

| | result |
| --- | --- |
| `d.update(z=6)` | correct |
| `d.update(z=7, y=8)` | **SEGFAULT** |
| `d.update({"z": 7, "y": 8})` | correct |
| `dict(z=7, y=8)` | correct |

Same builder in all four. The dict it builds is right (row 4 proves it) and the
dict it is handed is fine (row 3), so what breaks is the METHOD-argument path's
handling of the **hoisted** setitem statements the builder queues — the
trial-parse-rewind-replays-its-hoists shape (`PyHoistPark`/`Restore`/`Merge`) is
the obvious suspect and was not confirmed. A construct that is correct with one
keyword and corrupts memory with two is strictly worse than the compile error it
replaces, so `PyKeywordsAreKeys` answers `dict` only and `update` keeps its
error.

### Where the `**` form is refused is NOT where you would look

`d.update(**e)` reports `expected expression`, and that error does **not** come
from any of the five argument loops in parser.inc. All five were instrumented
(a `Warn` in `PyKeywordsAreKeys`, printing the callee name every time it is
asked): while compiling `g.update(**src)` **not one of them is reached** — the
last probe fires deep inside pylib, then the error. So a route that is neither
the arity-driven method loop, nor the field-receiver loop, nor the plain
class-method loop, nor the metaclass-ctor loop, nor the plain-call loop handles
it. Find that route before trying again; guessing at loops cost this session
four rebuilds and found nothing.

(The keyword form `d.update(z=6)` DOES reach the arity-driven loop, which is why
it worked. Same construct, two routes — this file's recurring shape.)

### Still open in this ticket

- `d.update(a=1)` / `d.update(**e)`, per the two sections above.
- `"ß".upper()` / `"İ".lower()`, scoped to the wider unicode question.

## Row 2 DONE 2026-08-14 — `d.update(a=1)` and `d.update(**e)`, both halves

Shipped, matching CPython on every receiver shape. The two symptoms the previous
sessions recorded separately — the **segfault on two keywords** and the
**"expected expression" from a place no argument loop explains** — are ONE cause,
and neither is where the notes above looked.

### The cause: the argument list was described to overload selection in the wrong units

Keywords-are-KEYS means the whole run is **one TPyDict argument**, however many
keywords it holds. `FindUMethOverloadAhead` was never told that, and both of its
halves then went wrong on the same call:

- its **arity filter counts the keywords**, so `d.update(z=7, y=8)` looked like a
  two-argument call, matched none of the three `update` arms
  (TPyList / TPyDict / Variant), and fell through to `FindUMethArity`'s first
  name hit — `update(l: TPyList)` — which then received a TPyDict. That is the
  segfault, and it is the same type confusion as
  [[bug-nilpy-dict-update-with-a-variant-argument-segfaults]] arriving by a new
  road. `d.update(z=6)` *happened* to land on the Variant arm, which is the whole
  reason one keyword worked and two corrupted memory.
- its **speculative probe** parses each argument to learn its type, and a `**` is
  not an expression, so it raised a bare `expected expression`.

So the parked note's suspicion — "the METHOD-argument path mishandles the
builder's hoisted setitem statements, the trial-parse-rewind shape is the
suspect" — was wrong. The builder and its hoists were never at fault; the callee
was already the wrong one before an argument was parsed.

### How it was found, since the notes above say guessing cost four rebuilds

Instrumenting argument loops is what failed twice. **Ten** loops call
`PyKwArgIndex`; all ten were instrumented this time and the failing call reached
none of them. One `gdb -batch -ex "break Error" -ex bt` on `compiler/pascal26-debug`
named `FindUMethOverloadAhead` in the first frame that mattered. The tool was
`make pxx-debug`, which is one line in the playbook and cheaper than every probe
tried before it.

### The fix — one intercept, ahead of both halves

`PyDictKwOverloadAhead(ci, name)` answers the UMeth index a keywords-are-KEYS run
resolves to, and `FindUMethOverloadAhead` asks it before the arity filter and
before the probe. Placed there deliberately: an intercept *after* selection would
have to repair the chosen call node instead, and an earlier cut of this fix did
exactly that (`PyDictKwRetarget`, patched into all four builder sites) — it
worked, and it was **deleted** once the upstream fix landed, because two
mechanisms for one concept is the shape `normalise-dont-special-case.md` warns
about and the second one is the one that stays broken.

`PyKeywordsAreKeys` also had a real bug of its own: it compared `mpi` against
`FindUMeth`'s **single** hit, so it answered True or False for the same construct
depending on which of the three overloads the call site had picked. It now checks
every arm of TPyDict.

### The dynamic receiver is a THIRD route and needed its own arm

`def f(m): m.update(a=1)` and `xs[0].update(r=1)` never reach
`FindUMethOverloadAhead` — they go through the dynamic-dispatch path, where
`update` is a name TPyList and TPySet carry too, so the scan answered with
`TPyList.setupdate`. That path now asks the same `PyDictKwOverloadAhead` for the
callee and the same `PyKwDictArgNode` for the argument. A keyword run only ever
means `dict.update` — CPython's list and set take no keywords — so there is one
right answer and every route gives it.

### Gate

`test/test_nilpy_dict_update_keywords.npy` + `.expected` **generated from
CPython**, byte-identical, wired into `test-nilpy`. Covers one/two/three
keywords, `**` spread, spread mixed with a keyword, later-key-wins, the plain
dict argument, `dict()`/`dict(p=1)`/`dict(**e, q=2)`, non-literal values, and
name / field / subscript / unannotated-parameter receivers. `make
compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN; the seven sibling
kwarg/update tests re-run by hand and green.

### Still open in this ticket

- `"ß".upper()` / `"İ".lower()` — case mappings that change the code-point count,
  scoped by this ticket to the wider unicode question rather than to itself.
