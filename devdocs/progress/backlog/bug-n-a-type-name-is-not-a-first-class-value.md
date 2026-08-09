---
track: N
prio: 45
type: bug
summary: "`t = str`, `f(str)`, `[str, int]`, `{\"k\": str}` are all parse errors in NilPy, and a user-class alias `A = B` parses but is unusable (`A()` fails, isinstance says unknown type) — functions ARE first-class values, types are not"
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
