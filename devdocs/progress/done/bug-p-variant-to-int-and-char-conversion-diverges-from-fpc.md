---
track: P
prio: 45
type: bug
blocked-by: []
summary: "DECIDED (user, 2026-08-13) — plain work now. The Variant->scalar CONVERSION itself disagrees with FPC in two rows: a boolean variant answers 1 where FPC answers -1, and an integer variant converted to Char answers Chr(n) where FPC renders the number as a string and takes its first character ('65' -> '6'). Both spellings (`i := v` and `Int64(v)`) agree with each other — the conversion is what differs. Ruling: boolean adopts FPC's -1; Char keeps Chr(n) by default with FPC's format-then-index rule behind --strict-fpc."
status: done
owner: agent-apn
---

# Variant->Int64 and Variant->Char conversions diverge from FPC in two rows

- **Type:** bug (compat) — **Track P** (Pascal dialect semantics; the helpers
  are `VariantToInt64` / `VariantToChar` in `compiler/builtin/**`, so the fix
  lands in Track A/B ground)
- **Found:** 2026-08-13, while fixing
  [[bug-p-a-typecast-of-a-variant-reinterprets-it-instead-of-converting]] — the
  new `test/test_variant_typecast.pas` diffs every cast against an FPC build of
  the same file, and exactly two rows survived as differences after the cast
  itself was made to agree with the assignment.

```pascal
program vconv;
uses variants;
var v: Variant; i: Int64; c: Char;
begin
  v := True; i := v; writeln('bool->int: ', i);
  v := 65;   c := v; writeln('int->char: ', c);
end.
```

| | FPC 3.2.2 | pxx (HEAD 2026-08-13) |
| --- | --- | --- |
| `True` variant -> Int64 | `-1` | `1` |
| `65` variant -> Char | `6` | `A` |

Both are the OLE-variant conventions FPC inherits: a boolean variant is
`VARIANT_TRUE` = -1, and a Char target goes through the variant's STRING form.

The Char rule is genuinely "render, then take character 1" — measured, not
inferred, because the single row `65 -> '6'` is also consistent with several
wrong stories:

| variant | FPC `Char(v)` | pxx `Char(v)` |
| --- | --- | --- |
| `65` | `6` (ord 54) | `A` (ord 65) |
| `7` | `7` (ord 55) | #7 |
| `122` | `1` (ord 49) | `z` (ord 122) |
| `2.5` | `2` (ord 50) | #0 |
| `'hi'` | `h` | `h` |

`122 -> '1'` and `2.5 -> '2'` are what settle it: FPC is not doing `Chr(n)`
with some truncation, it is formatting the variant and indexing the result.
pxx does `Chr(n)`.

**Not the same bug as the typecast one.** The cast form and the assignment form
now agree with each other (that fix is landed); this ticket is about the shared
conversion the two of them call. `test_variant_typecast.pas` asserts the
current pxx values on those two lines with a comment pointing here, so
resolving this means updating that expectation and the Makefile assert.

## FPC contradicts ITSELF on the Char row

Worth stating plainly, because "the variant must be string-typed" is the
natural first guess and it is wrong — the same variant converts as a NUMBER
for every other ordinal width:

```
v := 65;
VarType(v) = 16     { a ShortInt variant. Numeric. Not a string. }
Byte(v)    = 65
Word(v)    = 65
Char(v)    = 6      { ord 54 }
```

The OLE variant type system has no char type, so Delphi defined a Char target
as "a string of length 1" and FPC inherited it. That is history, not a rule
worth reproducing by default.

FPC's own diagnostic leaks the intermediate step — ask for a Char and it
complains about a **String**:

```
v := Null;  c := Char(v);
EVariantTypeCastError: Could not convert variant of type (Null) into type (String)
```

The empty-string variant answering #0, and `'hi'` answering `'h'`, are the same
rule seen from the edges. Note you cannot write the second half yourself: FPC
rejects `c := someAnsiString` ("Incompatible types"), so the string hop is an
UNWRITABLE intermediate that only the variant conversion table can reach. The
provenance is Microsoft's OLE Automation VARIANT, by way of Delphi — an
inheritance, not a design decision anyone here gets to be blamed for.

## DECIDED (user, 2026-08-13)

Both rows resolved — this is now plain work, not an open question:

1. **Char stays `Chr(n)` by default**, and FPC's format-then-take-character-1
   rule is implemented **behind `--strict-fpc`**, so the conformance sweep can
   assert parity while ordinary code gets the coherent answer. A deliberate
   exception to the standing "semantics of accepted code track FPC by default"
   rule, made on the merits above.
2. **The boolean row adopts FPC's `-1`** (OLE `VARIANT_TRUE`): a boolean
   variant converts to -1 / 255 / -1.0 for Int64 / Byte / Double. FPC is
   self-consistent here and every OLE consumer expects it, so there is nothing
   to defend in our 1. Note this is the VARIANT conversion only — `Ord(True)`
   and `Integer(someBooleanVar)` stay 1, exactly as in FPC.

## HAZARD — the -1 change can break NilPy, and the gate will not tell you

Check this BEFORE touching `VariantToInt64`. NilPy is normally insulated from
the Pascal variant helpers because `IRLowerVariantAsScalar` picks the pylib set
(`pyvar_to_int`, `pystr_of`, …) under `PyProgramMode` — but that insulation is
at the LOWERING seam, and **pylib calls the Pascal helper directly, four
times**, which walks straight around it:

```
compiler/builtin/pylib.pas:5678   store(k, VariantToInt64(fetch(k)) + 1);
compiler/builtin/pylib.pas:5722   store(k, VariantToInt64(fetch(k)) + VariantToInt64(vs.at(i)))
compiler/builtin/pylib.pas:5744   (VariantToInt64(vs.at(idx[j])) > VariantToInt64(vs.at(idx[j - 1])))
compiler/builtin/pylib.pas:5796   c.store(s[i], VariantToInt64(c.fetch(s[i])) + 1);
```

NilPy uses the SAME boolean tag (`VT_BOOL = 4`; see pylib.pas:4805, which
treats 1/2/4 as one int family "by payload, tag-independent"). And Python
requires `True == 1` — `sum([True, True, False])` is `2` in CPython and in
NilPy today. Flip the shared helper to -1 and those become -2: a silent
CPython-compatibility break, which is exactly the one direction Track N does
not permit.

**It will pass the gate.** No current test sums or counts booleans through a
Counter, so nothing goes red — this is a "quick was GREEN every time" shape.

So the -1 must be scoped to the PASCAL helper set only. Either route those four
pylib sites to `pyvar_to_int` (preferred — it removes the seam violation as
well), or give the Pascal helper the new behaviour under a name pylib does not
call. Add a NilPy test asserting `sum([True, True, False]) == 2` and a
boolean-valued Counter before making the change, so the regression has somewhere
to land.

## Where the work lands

`VariantToInt64` / `VariantToDouble` / `VariantToChar` in
`compiler/builtin/builtin.pas`. A builtin change does NOT take effect for the
gate's fixedpoint until it is re-pinned — `tools/testmgr.py --pin` after the
gate (see project_builtin_change_needs_repin_for_gate_fixedpoint).

The `--strict-fpc` Char arm needs the strict flag readable from the runtime
helper, which it is not today; if that turns out to want a second helper
selected at the lowering seam (the way `IRLowerVariantAsScalar` already picks
between the Pascal and pylib helper sets), do it there rather than threading a
flag into builtin.

## Gate

`make test` + self-host fixedpoint, then re-pin. Updates
`test/test_variant_typecast.pas` and its Makefile assert: the `Int64(v)` row
under `v := True` becomes `-1`, and the Char row keeps `A`.

## Progress (2026-08-13)

**Both rows landed, as decided.**

### 1. Boolean adopts OLE's VARIANT_TRUE

`VariantToInt64` and `VariantToDouble` answer -1 / -1.0 for VT_BOOL. `Byte(v)`
gives 255 for free — the existing narrowing mask in the AN_PTR_CAST path turns
the -1 into it, no second change. Diffed against FPC: Int64 -1, Byte 255,
Double -1.0, all matching.

**The NilPy hazard was real and is closed FIRST.** The four `VariantToInt64`
calls in `pylib.pas` (dict/Counter update, most_common's sort, the string
counter) were rerouted to `pyvar_to_int` BEFORE the -1 went in, so NilPy never
observes it. `pyvar_to_int` reads VT_BOOL as its payload (1) and raises a
Python TypeError for a str/object, which is what CPython's Counter arithmetic
does — so the reroute is not merely defensive, it is the more correct helper at
those sites. `grep VariantToInt64 compiler/builtin/pylib.pas` now matches only
the comment explaining why not.

New regression: `test/test_nilpy_bool_is_an_int_not_ole_minus_one.npy`, diffed
against CPython, covering `sum([True, True, False])`, `int(True)+int(True)`,
Counter construction, a Counter merged from a boolean-valued mapping, dict
value arithmetic and `True + True`. Registered in BOTH `test-nilpy` and
`test-core`, like its sibling boolean tests.

### 2. Char keeps Chr(n); FPC's rule behind --strict-fpc

No flag threaded into the runtime. `StrictVariantChar` (defs.inc, set by
`EnableStrictFpc` and the `{$STRICT_FPC ON}` directive) is read at the LOWERING
SEAM — `IRLowerVariantAsScalar` already picks helper NAMES per mode for the
Pascal/pylib split, so strictness costs one more name there and the runtime
stays flag-free. The strict helper `VariantToCharFPC` is built ON TOP of
`VariantToStr` rather than walking the tags again, so "render then index" and
"render" cannot drift.

`--strict-fpc` output is byte-identical to an FPC build across the whole table
including the edges: 65→'6', 7→'7', 122→'1', 2.5→'2', True→'T', 'hi'→'h',
''→#0. FPC's `Null` error text is reproduced verbatim (it names *String*, not
Char — under a parity flag the message is part of the behaviour).

New test `test/test_variant_typecast_strict.pas` (run with `--strict-fpc` in
`make test`); `test_variant_typecast.pas` updated for the -1/255/-1.0/True rows
and now states the Char row as the one deliberate divergence.

### Fixed in passing

`{$STRICT_FPC OFF}` did not clear `StrictShiftWidth` — it was omitted from the
OFF list when it was added, so an ON...OFF region left the shift rule latched
on. Corrected along with the new flag, since otherwise `StrictVariantChar` had
to pick which of the two behaviours to copy.

### Found and filed, NOT fixed here

[[bug-n-inline-multi-entry-dict-literal-arg-loses-its-values]] — an inline
`{...}` with 2+ entries passed as an argument drops its values (`c.update({"x":
5, "y": 0})` counts each key once). Pre-existing (reproduces on pinned), Track
N, and it briefly masked the boolean test until the mapping was moved through a
variable.

**Gate:** `tools/gate.sh quick` + the three new asserts; builtin changed, so
this needs `tools/testmgr.py --pin` before Track B's ground moves.

## Log
- 2026-08-13 — resolved, commit 86410fdd1.
