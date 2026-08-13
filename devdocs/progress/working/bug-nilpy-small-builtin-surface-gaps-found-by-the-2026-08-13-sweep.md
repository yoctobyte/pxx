---
track: N
prio: 40
type: bug
blocked-by: []
summary: "Four small refusals found by the 2026-08-13 CPython sweep: `issubclass(A, B)`, `d.update(k=v)` (the keyword form), `key=str.lower` (an unbound method as a callable value), and Unicode special-casing in upper()/lower() ('ß'.upper() is 'ß', CPython 'SS'). Each is a parse error or a wrong string, none is a silent wrong VALUE"
status: working
owner: claude-A-C-N
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
