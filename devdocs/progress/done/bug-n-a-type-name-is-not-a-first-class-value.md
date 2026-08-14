---
track: N
prio: 45
type: bug
summary: "`t = str`, `f(str)`, `[str, int]`, `{\"k\": str}` are all parse errors in NilPy, and a user-class alias `A = B` parses but is unusable (`A()` fails, isinstance says unknown type) — functions ARE first-class values, types are not"
status: done
owner: claude-A-N
---

# A type name is not a first-class value

- **Type:** bug — Track N (Nil-Python frontend)
- **Opened:** 2026-08-09
- **Filed by:** Track B, scoping [[feature-nilpy-six-and-warnings-shims]]. The
  shim's load-bearing line is `text_type = str`; it does not compile, so the
  ticket that called `six` "the cheap win" rests on a premise that is false. Not
  Track B's file, so it is handed over.

## Measured (pinned, 2026-08-09) — vary the shape, find the boundary

Everything below runs correctly on CPython, so by the upward-compatibility rule
in CLAUDE.md every failing row is an N defect rather than a dialect choice.

| shape | pxx |
| --- | --- |
| `print(chr(65))` | **OK** — `A` |
| `f = len; f("abc")` | **OK** — `3` |
| `def g(x): ...; h = g; h(1)` | **OK** — `2` |
| `isinstance("a", str)` | **OK** — `True` |
| `isinstance("a", (str, int))` | **OK** — `True` |
| `t = str` | `error: unexpected token` |
| `x = int` | `error: unexpected token` |
| `print(str)` | `error: unexpected token` |
| `f(str)` (type as an argument) | `error: unexpected token` |
| `ts = [str, int]` | `error: unexpected token` |
| `d = {"k": str}` | `error: unexpected token` |
| `t = (str,)` | `error: unexpected token` |
| `unichr = chr` | `error: undefined variable (chr)` |
| `A = B` (B a user class) | parses |
| …then `A()` | `error: unexpected token` |
| …then `isinstance(x, A)` | `error: Nil Python: unknown type in isinstance: A` |

## The shape of it

**Functions are first-class; types are not.** `len` and a user `def` both bind
to a name and call through it. A type name — builtin (`str`, `int`, `bytes`) or
user class — is only ever accepted in the syntactic positions the frontend
special-cases: a call `str(x)`, an `isinstance` second argument, a base-class
list. Anywhere a value is expected, the parser does not have a production for
it.

The user-class row is the one to look at first, because it is the worse failure
mode: `A = B` **succeeds**, so nothing warns, and the alias is then dead — the
call site fails with a bare "unexpected token" pointing at `A()`, and
`isinstance` reports `A` as an unknown *type* even though it is a bound name.
Something is accepting the assignment without recording anything usable, which
is the "two mechanisms for one concept" smell from
`devdocs/dev/normalise-dont-special-case.md`: a name lookup that knows about
functions and a separate type lookup that only knows about syntactic type
positions.

`chr` vs `len` is the same split seen from the other side — both are builtins,
one is a value and one is not, so the builtin table itself is not uniform.

## Why it is worth more than the six shim

`type(x)` is already restricted (`error: Nil Python: type(x) is only supported
as type(x).__name__`), and factory/registry code — `handlers = {"int": int,
"str": str}`, `cls = Foo if flag else Bar`, `sorted(xs, key=str.lower)` (recorded
separately in `feature-nilpy-str-surface-gaps-2026-08-09`) — is ordinary Python
that this blocks wholesale. `six` is one caller; the pattern is everywhere in
real libraries, which is the mission target.

## Gate

`make test-nilpy` green + the rows above as a `.npy` test with CPython's own
output as the expectation.

## 2026-08-09, Track A+N — split in two; the six-shim half is the BUILTIN half

Scoped against [[bug-nilpy-a-class-used-as-a-value-segfaults-or-refuses]], and
the two halves of this ticket turn out to have different root causes:

- **User-class rows** (`A = B`, then `A()` / `isinstance(x, A)`) are the same
  problem as that ticket, and it is now blocked on
  [[decide-nilpy-class-as-value-dispatch-strategy]] — measured: NilPy ctor
  params are statically inferred per class, so a variant tag alone can never
  make `cls(...)` callable.
- **Builtin-type rows** (`t = str`, `f(str)`, `[str, int]`, `(str,)`) are a
  SEPARATE representation question. `str`/`int`/`bytes` are not user classes and
  have no RTTI blob, so they need a payload space of their own — a small type
  code — whatever is decided about user classes.

That split matters for [[feature-nilpy-six-and-warnings-shims]]: every one of
its blocked names (`text_type = str`, `binary_type = bytes`,
`string_types = (str,)`) is a BUILTIN type, so the six shim turns entirely on the
builtin half and **not** on the user-class decision. The builtin half is also the
smaller one — a type code plus `isinstance`, `==`, `repr` and call-as-conversion
over it, with no ABI problem at all, because `str(x)` / `int(x)` are conversions
the frontend already emits rather than user ctors.

Recommend doing the builtin half first and independently. It unblocks the
library campaign's stated top lever without waiting on the Track U decision.

## 2026-08-11 (claude-A) — RE-MEASURED: most of the table is stale, one gap closed

The measurements above are from 2026-08-09 and `feature-nilpy-class-as-a-value`
landed since. Re-ran the user-class rows at HEAD before building anything:

| row | ticket (2026-08-09) | HEAD (2026-08-11) |
| --- | --- | --- |
| `A = B` | parses | parses |
| `A(3)` | `error: unexpected token` | **works** |
| `print(A)` | (not listed) | **works** — `<class '__main__.B'>` |
| `isinstance(x, A)` | `unknown type in isinstance: A` | **was still broken; FIXED here** |

So the user-class half was down to ONE row, and the ticket's own "blocked on
decide-nilpy-class-as-value-dispatch-strategy" no longer applies to it: binding
a class and CALLING through it already work, because a class object is a real
VT_CLASSREF variant now. Only the type TEST had not caught up — it resolves its
second argument by NAME, and a name is exactly what an alias is not.

**Fixed:** `pyisinstance_v(x, t)` walks the instance's ancestry against the
class object t (so a DESCENDANT answers True, as CPython does), and accepts a
TUPLE of types, which is what CPython allows anywhere a type is expected. The
frontend routes to it when the second argument is not a type name but IS a bound
name — deliberately not for an unbound one, so a typo'd type keeps its
compile-time diagnostic naming it rather than quietly becoming a runtime False.
That is pinned by a negative test.

**This unblocks the six shim's real idiom** — `string_types = (str,)` then
`isinstance(s, string_types)` — for the tuple-in-a-name half. The remaining work
is the BUILTIN-type half the 2026-08-09 note scoped: `t = str` still does not
parse, because `str`/`int`/`bytes` are not classes and have no RTTI blob to
point at, so they need a payload space of their own. `pyisinstance_v` is written
to take them the moment they exist (its `Exit` for a non-class tag is the seam).

Gate: `make test-nilpy` EXIT=0, `gate.sh quick` GREEN (self-host byte-identical).
New `test/test_nilpy_isinstance_over_a_type_value.npy` (+ the unknown-name
negative test). Needs a pin before other lanes see it (`compiler/builtin`).

**Left OPEN** for the builtin-type half; moved back to the backlog rather than
resolved, with the user-class rows struck out above.

## 2026-08-14 (claude-A-N) — the BUILTIN half SHIPS. The ticket is done.

`t = str`, `f(str)`, `[str, int]`, `{"k": str}`, `(str,)`, `t(5)` and
`isinstance(x, t)` all work and match CPython. With the user-class half already
struck out above, that closes the ticket.

### Representation: a tag with a small code, not a synthesized RTTI blob

`VT_BTYPE_TAG = 13`, payload = a `PYBT_*` code — the sibling of
`VT_CLASSREF_TAG` for the types that are not user classes. The alternative
considered and rejected was giving each builtin a fake `TClassRTTI` so it could
ride tag 11 and reuse the ancestry walk: a `str` VALUE is variant tag 6, not an
object carrying an RTTI pointer, so that walk is unreachable for exactly the
scalar types this is about and isinstance must switch on the variant tag either
way. The blob would have bought repr alone, at the price of a record that looks
like a class to every consumer that walks one.

`pybtype_of_value` is deliberately NOT a second tag→code switch. `pytype_name_v`
is already the one place that decides a value's Python type — and it knows what
a tag cannot, since list/tuple/set share one class and differ by FKind, and
bytes/bytearray share TPyBytes and differ by a flag. So the code is recovered by
asking that function and mapping its answer back through the same name table
repr uses. One mechanism.

### THREE entry points, and the third was found only by running it

The construct is reached three ways, and each had to be told:

1. **`ParseFactorCore`'s tkIdent path** — a type in an expression. Ahead of the
   conversion arms, which all open `Next; Expect(tkLParen, '(')` and so reported
   a bare "unexpected token" with no '(' after the name.
2. **`PyMakeFuncValue`** — an assignment RHS. This is the one that was missed
   first, and the symptom is the interesting part: **five of the eleven type
   names (`list`, `dict`, `tuple`, `bytes`, `bool`) are ALSO pylib procs**, so
   the function-value arm claimed those five and `L = list` bound the pylib
   ROUTINE. `L("abc")` then went through the callable ABI and answered an
   **int**, while `t = str` had worked from the first build because `str` is not
   a proc. One construct, two answers, decided by which builtins happen to
   exist — invisible to any test written only around `str`.
3. **`pyvar_callv0/1`** — calling a type held in a name is the CONVERSION, so it
   sits beside the `pyclassref_is` arm that constructs, because it is the same
   concept: a type used as a value, called.

That is the `normalise-dont-special-case.md` shape twice over, and both were
caught by widening the test to every builtin rather than by reading.

### One landmine avoided and one theory disproved

`pybtype_call0/1` are PROCEDURES with a var result, not Variant-returning
functions: the value is forwarded straight into `pyvar_callv1`'s own Variant
Result, which is the NRVO corruption shape
(`project_variant_fn_return_forward_nrvo_corruption`). Worth saying plainly that
this was **not** what caused the empty `list("abc")` — that was entry point 2
above, and converting to var-out changed nothing. The conversion is kept anyway
because the hazard is real; the wrong diagnosis is recorded because it was
wrong.

### Scope, stated

`bytes` / `bytearray` / `tuple` / `frozenset` bind, print, sit in containers and
answer isinstance, but CALLING one through a name raises a named TypeError
rather than converting — they need constructors pylib does not expose as a
one-argument variant conversion. Refused at the boundary of what can be answered
exactly, the same call the unbound-str-method arm makes for an arity it cannot
express. `type(str)` still hits the pre-existing `type(x) is only supported as
type(x).__name__` restriction, which is its own ticket.

### What this unblocks

[[feature-nilpy-six-and-warnings-shims]]'s load-bearing lines — `text_type = str`,
`binary_type = bytes`, `string_types = (str,)`, `integer_types = (int,)` and
`isinstance(s, string_types)` — all compile and answer correctly now. `six` is
the first wall of the html5lib ladder in
[[feature-nilpy-thirdparty-libraries-as-targets]], blocking 13 of its 48 files.

### Gate

`test/test_nilpy_builtin_type_as_a_value.npy` + `.expected` generated from
CPython, byte-identical, wired into `test-nilpy`. `make compiler/pascal26`
fixedpoint + `tools/gate.sh quick` GREEN. This touches `compiler/builtin/**`, so
it needs a pin before other lanes see it.

## Log
- 2026-08-14 — resolved, commit PENDING-COMMIT.
