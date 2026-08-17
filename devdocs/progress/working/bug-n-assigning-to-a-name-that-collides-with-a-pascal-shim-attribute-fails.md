---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`import string` then `digits = string.digits` fails with `undefined variable (digits)` — the LHS name breaks resolution of the same-named attribute on the RHS. Only for PASCAL shim modules (mimic_*.pas); a .py shim and a plain NilPy module both work. Blocks html5lib's constants.py:544, which most of html5lib imports."
status: working
owner: frank2
---

# Assigning to a name that collides with a Pascal shim's attribute fails

- **Type:** bug (name resolution) — **Track N** (NilPy import/attribute
  resolution). May be core; filed here because the construct is a NilPy import.
  **Not fixed under B** — `mimic_string` is not missing anything.
- **Found:** 2026-08-17 by frank3, chasing the `undefined variable (digits)`
  wall on the corpus ladder.
- **Measured against:** `pinned` **v346**. Not re-checked at HEAD.

## Repro

```python
import string
digits = string.digits
print(digits)
```

```
pxx:     pascal26: error: undefined variable (digits)
CPython: 0123456789
```

Rename the target and it compiles:

```python
import string
p = string.digits      # fine
```

## The boundary, measured one variable at a time

| case | result |
| --- | --- |
| `digits = string.digits` (Pascal shim, a `const`) | **FAIL** |
| `punctuation = string.punctuation` (Pascal shim, another `const`) | **FAIL** |
| `capwords = string.capwords` (Pascal shim, a **function**) | **FAIL** |
| the same inside a `def` rather than at module level | **FAIL** |
| `p = string.digits` — different target name | ok |
| `PY3 = six.PY3` (a **.py** shim, `mimic_six.py`) | **ok** |
| `value = mymod.value` (a plain NilPy `.py` module) | **ok** |
| `print(string.digits)` with no assignment at all | ok |

So it is not about the attribute, not about const-versus-function, and not about
scope. **It is specific to a Pascal-unit shim (`mimic_*.pas`)**, and it triggers
when the assignment target has the same name as the attribute being read. The
`.py` shim route added today is unaffected, which is a useful narrowing: the two
shim kinds resolve attributes differently and only one of them has this.

The collision is with the attribute name **anywhere in the right-hand side**,
not only in a bare `X = mod.X`. The real corpus site is a call:

```python
# html5lib/constants.py:544
digits = frozenset(string.digits)
```

## Why it is worth 55

`constants.py` is imported by most of html5lib — `_tokenizer.py` does
`from .constants import digits, hexDigits, EOF` — so this one line gates a large
part of that package, and `X = module.X` is an entirely ordinary Python idiom
(`digits = string.digits`, `path = os.path`). The diagnostic also points at the
wrong thing: it names the variable being *defined*, so the natural reading is
"this name is missing" when the name is being created on that very line.

## Not a `mimic_string` gap — checked first

`lib/rtl/mimic_string.pas` already exports every public name in CPython's
`string` module except `Formatter` and `Template`: `ascii_letters`,
`ascii_lowercase`, `ascii_uppercase`, `capwords`, `digits`, `hexdigits`,
`octdigits`, `printable`, `punctuation`, `whitespace`. `print(string.digits)`
prints `0123456789` today. Nothing is missing from the shim, so nothing in
Track B fixes this.

## Root cause (frank2, 2026-08-17, measured at HEAD `0fb7c932f`)

**Not NilPy at all, and not the shim route.** It is a Pascal frontend defect in
`ParseFactor`, and the whole thing reproduces in plain Pascal with no NilPy
anywhere:

```pascal
program p2;
uses mimic_string;
var digits: AnsiString;
begin
  digits := mimic_string.digits;   { error: undefined variable (digits) }
  WriteLn(digits);
end.
```

Rename the program's var and it compiles. FPC 3.2.2 accepts both spellings and
prints the unit's const, so this is a divergence from the reference, not a
dialect call.

The chain, traced with `PXXDBG=a.qual` plus three temporary tagged copies of the
`undefined variable` diagnostic (there are three, and knowing WHICH one fires is
the whole diagnosis):

1. `ConsumeUnitQualifier` resolves fine — `bestUnit=46` (mimic_string), member
   name `digits`. The qualifier is **not** the problem.
2. `FindSymInUnit('digits', 46)` returns **-1 in the working case too**. These
   `const x: AnsiString = '…'` declarations do not live in `Syms[]`; they live in
   the untyped **string-const table**, reached later by `FindStrConst`.
3. `parser.inc:15750` then cancelled it:
   `if (sci >= 0) and (FindSym(name) >= 0) then sci := -1;`
   — a scoping guard that exists for a real reason (fcl-json declares a
   method-local `const S` and a later method-local `var S`, and the unscoped
   const table otherwise expands the variable into the constant's text). It
   simply never asked whether the name had been reached through an explicit
   qualifier.
4. With `sci` cancelled, nothing claims the name, `ParseLValueAST` treats
   `digits` as a bare ident, `FindUClass` misses, and the third diagnostic fires
   — naming `digits`. That is why the error accuses the line that defines the
   variable.

So every row of the boundary table above is one fact: **an unqualified symbol of
that name anywhere in scope cancelled a QUALIFIED read of an untyped string
const.** `.py` shims and plain NilPy modules were unaffected because their
attributes are not string-table consts.

## Fix

`parser.inc:15750` — exempt an explicitly qualified read, the same exemption
`OwnFieldBeatsSym` already takes twenty lines above (`if qUnit < 0 then idx :=
OwnFieldBeatsSym(...)`). `qUnit = -1` is unqualified; `>= 0` is `unit.Name` and
`-2` is the `System.X` marker, and both mean "you asked for that scope by
construction". The `LineEnding` fallback on the next line had the identical
unguarded `FindSym(name) < 0` test and got the same treatment, so
`System.LineEnding` no longer loses to a local called `LineEnding`.

Note this does **not** fix `bug-pascal-string-const-not-scoped` — a qualified
read still consults a flat table, so it can still answer with another unit's
const of that name. That defect is untouched and older; this change only stops
the flat table from being switched off.

## Tests

- `test/test_nilpy_shim_attr_name_collision.npy` (wired into `test-nilpy`) —
  four lines, because "it compiles" is not the property: the bare name must
  still read the PROGRAM's value and the qualified name the MODULE's, so a
  fix that just deleted the guard fails line 1. Expectations are CPython's.
- `test/test_qualified_units.pas` + `test/qualified_a.pas` gained the Pascal
  half (`SharedTag`), expectation verified against FPC 3.2.2 directly.

## Gate

The repro prints `0123456789`, all four FAIL rows above become ok, and
`html5lib/constants.py` stops reporting `undefined variable (digits)`.

`tools/gate.sh quick` GREEN with the FPC seed canary run (concurrent).
