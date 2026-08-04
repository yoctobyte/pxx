---
summary: "b := a on a static array with managed elements copies NOTHING — every element comes out empty, silently; elementwise copy and the same array inside a record both work"
type: bug
track: A
prio: 80
---

# Whole-array assignment of a static array with managed elements silently loses the data

- **Type:** bug — Track A (codegen / managed-type assignment)
- **Status:** urgent
- **Opened:** 2026-08-04
- **Found by:** Track B, `tools/fpc_diff_probe.sh` `str-in-array` case.

## Repro

```pascal
var a, b: array[0..2] of string;
begin
  a[0] := 'p'; a[1] := 'q'; a[2] := 'r';
  b := a;
  writeln('[', b[0], '][', b[1], '][', b[2], ']');
end.
```

    FPC:  [p][q][r]
    pxx:  [][][]

**No error, no warning.** `a` is left intact; `b` is silently all-empty.

## What works and what does not — measured

| form | result |
| --- | --- |
| `array[0..1] of string`, `b := a` | **all elements EMPTY** |
| `array[0..1] of TR` where `TR` has a string field | **`[p][]`** — first survives, second lost |
| 2-D `array[0..1,0..1] of string`, `b := a` | **all empty** |
| const-initialised `array[0..1] of string = ('p','q')`, `b := a` | **all empty** |
| same arrays, copied **elementwise** in a loop | ok |
| `array[0..1] of Integer`, `b := a` | ok |
| **a record CONTAINING an `array[0..1] of string`, `y := x`** | **ok** |
| passing the array as a value parameter | ok |

The last two are the useful ones. Wrapping the identical array in a record and
assigning the record copies it correctly, and so does parameter passing — so the
machinery for copying managed elements exists and works; only the direct
whole-array assignment statement fails to use it. That comparison is probably
the whole diagnosis.

The `array of record-with-string` row giving `[p][]` rather than `[][]` says the
failure is not a simple no-op either — something copies partially, or copies and
then releases.

## Severity

Silent data loss on an ordinary statement. `b := a` on a `array[0..N] of string`
is not an exotic construct, and the failure produces empty strings rather than a
crash, so it surfaces later and somewhere else — the expensive shape described
in the debugging playbook.

## Related but distinct

`bug-p-string-char-relational-compares-lengths` (urgent) and
`bug-a-virtual-method-int64-in-and-out-32bit` (urgent) were found in the same
sweep; neither shares a mechanism with this one.
