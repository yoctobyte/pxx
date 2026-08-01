---
summary: "NilPy: the mixed-type TypeError guard lives ONLY in the runtime variant path — when BOTH operands are statically typed, `7 - [1,2]` and `\"ab\" - \"ab\"` silently do pointer math (108 sweep cases)"
type: bug
track: N
prio: 70
---

# Mixed-type guard fires only for VARIANT operands; fully static operands do pointer math

- **Type:** bug (NilPy semantics, silent wrong value) — **Track N**
- **Opened:** 2026-08-01, from a CPython differential sweep (1094 cases,
  self-hosted binary at `3f2c5b915`).

## The isolating experiment

```python
vals = [3, [1, 2]]
va, vxs = vals[0], vals[1]     # VARIANT: type known only at run time
sa, sxs = 3, [1, 2]            # STATIC:  int and TPyList known at compile time
print(va - vxs)   # CPython TypeError   pxx TypeError   OK
print(va - sxs)   # CPython TypeError   pxx TypeError   OK
print(sa - vxs)   # CPython TypeError   pxx TypeError   OK
print(sa - sxs)   # CPython TypeError   pxx 840957547   WRONG, SILENT
```

The guard fires whenever **either** operand is a variant. It fails **only** when
**both** are statically typed — that case lowers straight to IR arithmetic with
the container's HANDLE as a number.

## Scale

108 of the sweep's 174 divergences are this one root: CPython raises
`TypeError`, pxx returns a plausible number. It is not confined to containers or
to one operand type — every statically-typed mismatched pair diverges on the
same operator set:

| operands | operators that silently compute |
| --- | --- |
| `int`/`bool`/`float`/`zero`/`negint` vs `list` | `-` `/` `//` `%` `<` `<=` `>` `>=` |
| `str` vs `list` | `-` `/` `//` `<` `<=` `>` `>=` |
| `list` vs `int` | `//` `%` `<` `<=` `>` `>=` |
| `list` vs `list` | `-` `//` `%` `<` `>=` |
| `str` vs `str` | `-` `*` `/` `//` — e.g. `"ab" - "ab"` → **`1`**, `"ab" / "ab"` → **`1.0`** |

`+`, `*`, `**`, `==` and `!=` are consistently correct, because those have real
container/string semantics (concat, repeat) or a defined cross-type answer, and
so were implemented deliberately.

The ORDERING rows are the most dangerous: they return a clean `True`/`False`
decided by an allocation address, so a condition takes a branch with nothing in
the output suggesting a type error occurred.

## Why the existing test did not catch it

`test_nilpy_mixed_type_operands` asserts exactly these cases (`sub-list
TypeError`, `mul-dict TypeError`, `lt TypeError`, …) and **passes**. Its
operands come from a heterogeneous literal:

```python
vals = [3, "ab", [1, 2], {"k": 1}]
a, s, xs, d = vals[0], vals[1], vals[2], vals[3]
```

so every one of them is a **variant** — the path that already works. The test
covers only the guarded half and reads as full coverage. That is why the
static-path hole survived: it is not that nobody tested mixed-type operands, it
is that the test could not reach the broken lowering.

## Cause

The check is implemented in the runtime variant helpers (`pyvar_*`,
`compiler/builtin/pylib.pas`), which inspect `VType` and raise. A binop whose
operand types are both known at compile time never routes through them.
`IRPyNumStrClash` (`compiler/ir.inc:3841`) is the static-side counterpart, and
it deliberately fires only for a **str-vs-number pair** — so the static path has
one narrow special case where the variant path has a general rule.

**Measure before fixing**: dump the inferred kinds with `PXXDBG` (`n.locals`,
`a.ir:<proc>`) rather than assuming which predicate is short. An earlier reading
of this same sweep concluded the bug was bool-specific, then float-specific;
both were artifacts of reading a partially-written results file. The
static-vs-variant split is the axis that actually reproduces.

## Fix shape

Give the static path the general rule the variant path has: at binop typing,
reject operand-kind pairs that Python does not define for that operator, as a
genuine runtime `TypeError` (a `PyNotOrderableError`-style pylib raise, so
`try/except` still compiles), rather than falling through to numeric lowering.

Do NOT simply widen `IRPyNumStrClash` — it answers "str vs number", and the
table above needs container-vs-number, container-vs-container and str-vs-str
too. Deriving the allowed pairs per operator from CPython's own table is the
approach least likely to leave a neighbour wrong.

Sequencing note: `+`/`*`/`**`/`==`/`!=` currently work and carry real semantics
(list concat, str repeat, pathlib `/`). Land per-operator, and keep the
`PyRecIsPylibOwnClass` exclusion (`compiler/symtab.inc`) in mind — pylib's own
containers must keep their behaviour.

## Separate finding from the same sweep — bool forces UNSIGNED arithmetic

Both operands static scalars, no container involved:

| expression | CPython | pxx |
| --- | --- | --- |
| `True // -7` | `-1` | **`18446744073709551615`** (2⁶⁴−1) |
| `True % -7` | `-6` | **`18446744073709551610`** |

`7 // -7` and `7 % -7` are correct, so the result type is taken from the bool's
own unsigned type-kind instead of being promoted to a signed integer. In Python
`bool` is a subclass of `int`, so it should promote. Likely independent of the
guard hole above (it needs no type MISmatch at all) — if it survives that fix it
wants its own ticket.

## Gate

`make test-nilpy` + self-host byte-identical, plus the tables above added as
STATICALLY-typed operands (literals and single-type locals) — not via a
heterogeneous list, which is what hid this. Keep the existing variant-typed
cases as-is so both paths are covered. Diff against CPython's own output, and
re-run the operator×operand sweep afterwards rather than only the listed rows.

## 2026-08-01 — the static path is not ONE path: two different typings, measured

Reading `PyWiden` (`compiler/pyparser.inc`) suggested a single root, and
measuring killed that idea. Recorded because it would otherwise be re-derived.

`PyWiden(a, b)` ends with a rule widening any class-meets-scalar pair to
`tyVariant`. That rule is right for the job it was written for — unifying the
possible types of one LOCAL across rebindings (`temp_file = 'tmp.pdf'` then
`temp_file = NamedTemporaryFile(...)`, which Python allows). It is meaningless
as a binop RESULT type, and `PyWiden(tyClass, tyInteger)` → `tyVariant` is
exactly what made `obj & 1` SEGFAULT: the handle was stored through the variant
path and dereferenced as a variant record
([[bug-nilpy-bitwise-shift-on-class-operand-segfaults]], now fixed by
dispatching before the widening is reached).

**But that is NOT the mechanism for the operators in this ticket.** Measured
with `PXXDBG=a.ir:g` on `y = 7 - xs`:

```
47: binop a=45 b=46 c=71 ival=0 tk=1        <- tk=1 is tyInteger, not tyVariant
```

So `-` types its result as a plain integer and does pointer arithmetic in
registers; it never reaches `PyWiden` at all. The bitwise operators call
`PyWiden` explicitly from `pyparser.inc`; `+ - * /` and the comparisons are
typed by the shared `parser.inc` expression chain.

**Consequence for the fix:** there is no single entry point to guard. The
per-operator legality check has to be added where each family is typed — the
`parser.inc` binop typing for arithmetic and comparison, and (already handled)
the `pyparser.inc` bitwise routines. Anyone starting from "just fix PyWiden"
will fix the bitwise family only and conclude the rest is unrelated.
