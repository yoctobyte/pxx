---
track: A
prio: 45
type: bug
blocked-by: []
status: done
owner: claude-A
commit: PENDING-COMMIT
summary: "`b := v` with v = 'True' RAISES EVariantError; FPC answers True. VariantToBool refuses every string, on the strength of a measurement that only covered the empty one. FPC accepts case-insensitive 'true'/'false' and any numeric text, and raises only for text that is neither -- so pxx kills a program on a value FPC converts."
---

# A string Variant never converts to a Boolean

Found 2026-08-23 by the Variant differential family (`fpc 3.2.2 -Mobjfpc -O1`
vs pxx `d014cc21a`).

```pascal
var a: Variant; b: Boolean;
begin
  a := 'True';  b := a;   { fpc: True   pxx: EVariantError }
end.
```

Loud, not silent — but it kills a program on a value FPC converts happily, and
the string form is exactly how a Boolean arrives from a config file, a query
result or a parsed field, which is the whole reason a variant holds it.

## The existing comment was right about the case it measured, and wrong in general

`VariantToBool` (`compiler/builtin/builtin.pas`) says:

> *FPC RAISES for a string here (`b := v` with v='' is EVariantError, measured)
> rather than treating '' as false*

`''` does raise. So does `'zz'`. But those are the only kind that does, and the
arm was written to refuse **every** VT_STRING. A one-value measurement became a
whole-tag rule — the failure mode `devdocs/dev/root-cause-over-microfix.md`
describes as varying the shape too little.

## FPC's actual rule, measured across 21 spellings

| input | fpc | note |
| --- | --- | --- |
| `'True'` `'true'` `'TRUE'` | True | case-insensitive, EXACT — no trimming |
| `'False'` `'FaLsE'` | False | same |
| `' true'` `'true '` | **raises** | whitespace is not trimmed |
| `'1'` `'2'` `'-1'` `'2.5'` | True | numeric text, non-zero |
| `'0'` `'0.0'` `'-0'` | False | numeric text, zero |
| `''` `'zz'` `'yes'` | raises | neither a keyword nor a number |
| `1` `0` `2.5` `0.0` (non-string) | True/False/True/False | unchanged |

So: try the two keywords case-insensitively, then try to parse a number and
test it against zero, then raise. Nothing else.

## Fix

That rule, in `VariantToBool`'s string arm. The number half is the same
`Val` → `ValFloat` ladder `PXXVarNumCoerce` already uses twenty lines above, so
the two agree about what "numeric text" means by construction.

`VT_CHAR` (tag 5) is folded in as its one-character text — pxx has a char
variant and FPC does not (`v := c` gives FPC a varString), so there is no
oracle for it; treating it as the 1-character string is the coherent reading and
is what `PXXVarNumCoerce` already does with VT_CHAR. `'0'` is False, `'1'` is
True, `'x'` raises.

`VT_OBJECT` keeps raising, unchanged.

## NilPy is not affected

NilPy routes to pylib's `pyvar_to_bool` at the lowering seam
(`ir.inc:5364`), so Python's truthiness — where `''` is False and `'zz'` is
True — is untouched.

## Gate

Track A's, plus the 21 rows above matching fpc 3.2.2 (raise vs value, and which
value) on x86-64 and a cross target, and a `.npy` row proving `bool('')` is
still False and `bool('zz')` still True.

## FIXED 2026-08-23 (claude-A)

All 21 measured rows now match `fpc 3.2.2 -Mobjfpc -O1` exactly — including
which ones RAISE, which is half the rule and the half a lenient fix would have
broken.

`VariantToBool`'s string arm now: `__pxxSameNameCI` against `'true'`/`'false'`,
then `Val` → `ValFloat` (the same ladder `PXXVarNumCoerce` uses twenty lines
above, so the two agree about numeric text by construction) tested against zero,
then `PXXVariantError`. `VT_CHAR` folded in as its one-character text;
`VT_OBJECT` unchanged.

One mechanical note: `__pxxSameNameCI` is implemented ~1000 lines below
`VariantToBool`, so it gained an interface declaration beside `__pxxUpCase`
rather than being duplicated.

### Verified

- `test/test_variant_string_to_boolean.pas`, wired into `test-core`: 21
  assertions, and the six raising rows assert a RAISE rather than being skipped.
  `ALL OK` under pxx x86-64, i386, aarch64 (qemu), arm32 (qemu) and fpc 3.2.2.
- NilPy untouched: `bool('')` False, `bool('zz')` True, `if "zz":` truthy —
  matches CPython, because the seam routes to pylib's `pyvar_to_bool`.
- Self-host fixedpoint converged in one round.

## Gate

`make compiler/pascal26` converged + the 21-row differential + `tools/gate.sh quick`.

## Log
- 2026-08-23 — resolved, commit PENDING-COMMIT.
