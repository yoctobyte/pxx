---
track: P
prio: 70
type: bug
blocked-by: []
summary: "`type TIA2 = array of TIA` (TIA itself `array of Integer`) silently collapsed to `array of Integer`: m[0][0] read a heap handle as an Integer and printed a different number every run, and Length(m[0]) did the same. The identical type spelled at the variable (`var m: array of TIA`) was always correct -- two spellings of one type, one of which composed the alias's depth and one of which did not."
status: done
owner: frank1-ACP
---

# `array of <named dynamic-array alias>` loses a dimension in a TYPE declaration

- **Track P** (`compiler/parser.inc`, the dynamic-array type-alias branch).
- Found 2026-08-20 by an FPC differential probe over dynamic arrays.

## The measurement

`fpc -O- -Mobjfpc` 3.2.2 vs pxx at `837fffa22`:

```pascal
type TIA = array of Integer;
     TIA2 = array of TIA;       { the alias-of-alias }
var m: TIA2;  v: array of TIA;  { same type, spelled at the VAR }
    r: TIA;
begin
  SetLength(m, 2); SetLength(v, 2);
  SetLength(r, 3); r[0] := 7;
  m[0] := r;  v[0] := r;
```

| expression | FPC | pxx |
| --- | --- | --- |
| `m[0][0]` | 7 | **1233125496** (differs every run) |
| `Length(m[0])` | 3 | **1233125496** |
| `v[0][0]` | 7 | 7 |
| `Length(v[0])` | 3 | 3 |
| `SetLength(m[0], 3)` | compiles | **error: SetLength expects an array variable in IR codegen** |

The wrong value is the row's heap handle read as an Integer, so it is
nondeterministic — an ASLR address, not a stable wrong answer.

## Root cause — one type, two parsers, one of which composed

`ParseVarDecl` has had the composing rule for a long time (parser.inc, the
`array of TA` arm): *"A named dynamic-array alias as the element composes its
depth … ParseTypeKind cannot do this — array-type aliases live in the ArrType
table, not the scalar alias table, so it would resolve `TA` to a bare base type
and drop the dynamic dimension."* That comment describes this bug exactly.

The **type-alias** parser, registering `TIA2` into the ArrType table, checks
only whether the element is a named FIXED array:

```pascal
if (fAi >= 0) and (not ArrTypeIsDyn[fAi]) then   { row-element case }
  ...
else
begin
  aElemTk := ParseTypeKind;    { <-- a named DYN alias falls in here }
  ...
end;
```

so `TIA` fell to `ParseTypeKind`, resolved to `tyInteger`, and `TIA2` was
registered with `ArrTypeDynDepth = 1`. Everything downstream then behaved
correctly for the type it had been told about.

`devdocs/dev/normalise-dont-special-case.md` names this shape: one construct
reachable through two spellings, and the second path is the one that stays
broken. The fix adds the missing arm so both parsers compose alias depth
identically. Because the composition now lands in the **ArrType table itself**,
every consumer that reads `ArrTypeDynDepth` — variables, record fields,
parameters — gets the corrected depth without its own change.

## Why it stayed hidden

`SetLength(m[0], n)` is the only loud symptom, and it is loud for an unrelated
reason (codegen's `IR_SETLEN_DYN` path needs root `DynDepth >= 2`, and depth 1
fell through to the symbol path which refuses an index target). Every *read*
was silent. And the far more common spellings — `array of array of Integer`
inline, `TM = array of array of Integer`, `var m: array of TIA` — were all
correct, so only the alias-of-alias spelling was wrong.

## Test

`test/test_dynarray_named_alias_element.pas`, 26 FPC-verified rows: the value
and length through the alias, `SetLength` on a row, multidim `SetLength(m,3,5)`
through it, the var-spelled twin still agreeing, three levels of alias
(`TIA3 = array of TIA2`), a managed (`string`) element and a record element
through the same chain, and a jagged walk of the kind real code writes.

## Gate

`make compiler/pascal26` fixedpoint + `tools/gate.sh quick`.
