---
track: P
prio: 55
type: bug
blocked-by: []
summary: "fcl-json's `CreateJSONArray([1])` yields a `TJSONInt64Number` where FPC yields a `TJSONIntegerNumber`. The direct `CreateJSON(1)` agrees with FPC; only the `array of const` path diverges, in `With Element do case VType of vtInteger: CreateJSON(VInteger)`. Two of the fpjson suite's 203 cases fail on it."
---

# An `array of const` integer arm picks the Int64 overload

- **Type:** bug (Pascal frontend — `array of const` / overload resolution)
- **Track:** P
- **Found:** 2026-08-25, by
  [[bug-a-the-fpjson-suite-overflows-the-fixed-4096-entry-data-ptr-fixup-table]]
  — the fpjson suite could not build at all until that landed, so these two
  failures had been invisible, not introduced.

## Measured — differential, against the FPC oracle, on fcl-json's own sources

Same `fpjson.pp`, compiled both ways (pxx with `--mimic-fpc`):

```
                            pxx                    fpc
CreateJSON(Longint)      -> TJSONIntegerNumber     TJSONIntegerNumber   agree
CreateJSON(1)            -> TJSONIntegerNumber     TJSONIntegerNumber   agree
CreateJSONArray([1])[0]  -> TJSONInt64Number       TJSONIntegerNumber   DIVERGE
```

The direct overload resolution is right. Only the value routed through
`array of const` comes out as Int64.

## Where

`fpjson.pp`, `VariantToJSON`:

```pascal
With Element do
  case VType of
    vtInteger : Result := CreateJSON(VInteger);   { -> TJSONIntegerNumber }
    ...
    vtInt64   : Result := CreateJSON(vInt64^);    { -> TJSONInt64Number   }
```

`fpjson` declares `CreateJSON(Data: Integer)`, `CreateJSON(Data: Int64)`,
`CreateJSON(Data: QWord)` and `CreateJSON(Data: NativeInt)` as four separate
overloads, and picks the result class from which one binds. So the question is
either

1. the `TVarRec` we build for a plain integer literal is tagged `vtInt64`
   rather than `vtInteger` (wrong arm taken), or
2. the arm is right and `CreateJSON(VInteger)` — a `Longint` field read
   through `with` — binds the `Int64` (or `NativeInt`) overload.

**Measure which before theorising**; they are one `case` apart and lead to
completely different fixes. A standalone `Show([1])` printing `VType` gives 0
(vtInteger), which points at (2), but that probe did not go through fpjson's
overload set.

Note `CreateJSON(Data: NativeInt)` is a live confounder on 64-bit: it is a
third candidate that is layout-identical to `Int64`.

## Repro

```sh
tools/install_lib_candidates.sh fcl-json
# stage the suite flat (see the test-fpjson recipe in the Makefile), then:
#   probe.pp:  uses fpjson; writeln(CreateJSONArray([1]).Items[0].ClassName)
# pxx --mimic-fpc  -> TJSONInt64Number
# fpc             -> TJSONIntegerNumber
```

Or just run the suite: `TTestFactory.ArrayCreateInteger` and
`TTestFactory.ObjectCreateInteger` fail with
*"Correct class" expected: `<TMyInteger>` but was: `<TMyInt64>`*.

## Why prio 55

It is the entire remaining gap between the fpjson rung and its recorded
203/203 — the suite is at 201/203 — and it is a *silent wrong type* in a real
library's public factory, not a diagnostic nicety. Below the segfault tier,
above ordinary parity work.

## Gate
`make compiler/pascal26` + the fpjson suite reaching
`run: 203  failures: 0  errors: 0` + `tools/gate.sh quick`.

## Links
[[feature-pascal-corpus-fpjson]] ·
[[bug-a-the-fpjson-suite-overflows-the-fixed-4096-entry-data-ptr-fixup-table]]
