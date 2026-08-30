---
track: A
prio: 20
type: feature
blocked-by: []
summary: "TypeInfo of a plain Integer rename reports `Integer`; FPC reports `LongInt`. decide-typeinfo-scalar-name-spelling settled this on 2026-08-21 -- keep ours by default, report FPC's under --strict-fpc -- and cited this slug as its Implementation. It was never filed. Measured NOT delivered: the name is `Integer` under default, --mimic-fpc and --strict-fpc alike."
status: backlog
owner: unassigned
---

# TypeInfo: report `LongInt` for Integer under `--strict-fpc`

- **Type:** feature — Track A, tag **compat-pascal**. Low prio on purpose (see below).
- **Filed 2026-08-30 by frankD**, from a dangling-link sweep, not from a user
  report. [[decide-typeinfo-scalar-name-spelling]] [U p20] has read
  `Implementation: [[feature-a-typeinfo-integer-name-under-strict-fpc]]` since
  2026-08-21 and that slug has never existed. **A decision in `decided/` whose
  implementation link resolves to nothing is a settled call with nothing tracking
  it** — it reads as discharged from every direction.

## The decision this implements

> *"in strict FPC mode, we just mangle the name 'Integer' to 'Longint'. we are
> already compatible about the underlying type. it's just naming."* — user,
> 2026-08-21

Keep `Integer` by default; report `LongInt` under strict-FPC. Our answer by
default, FPC's convention behind the flag.

## Measured NOT delivered, 2026-08-30

Against `$(PXX_STABLE)` (`stable_linux_amd64/default/pinned`), no rebuild:

```pascal
program ti;
{$mode objfpc}
uses typinfo;
type TMyInt = Integer;
begin
  Writeln(PTypeInfo(TypeInfo(TMyInt))^.NamePtr^);
end.
```

| flags | output |
| --- | --- |
| *(none)* | `Integer` |
| `--mimic-fpc` | `Integer` |
| `--strict-case` | `Integer` |
| `--strict-fpc` | `Integer` |

FPC 3.2.2 reports `LongInt`. So the decision is undelivered rather than
delivered-under-another-name — the other possibility, and the one worth ruling
out first, since a decided ticket advertising finished work is a different
defect from one advertising unfinished work.

## `--strict-fpc` is real and live — this is a missing arm, not a missing flag

Worth stating, because "the flag does not exist" was the obvious wrong
conclusion: `--strict-fpc` is **not in `--help`**, which is what made it look
absent. It is accepted (an unknown flag is rejected — `--nonsense-flag` gives
`unknown option`), it is documented as an umbrella in `compiler/defs.inc:2189-2191`,
and it demonstrably changes behaviour:

```python
var v: Variant; c: Char;
begin v := 65; c := Char(v); Writeln(c); end.
```

→ `A` by default, **`6`** under `--strict-fpc` (FPC's Variant→Char string hop).

So the umbrella works and this arm was never wired into it.

## Where the assertion lives

`test/test_typeinfo_named_types.pas` asserts the current answer explicitly and
points at the decision — lines 16-17 spell out *"We report `Integer` where FPC
reports `LongInt` for that last one"*. **That test is the thing to change**, and
it should gain a `--strict-fpc` leg rather than flipping: the default answer
stays ours.

## Why prio 20

This is `compat` by CLAUDE.md's table — *"our output formatting of a value
differs"* — and it is a string in RTTI, not a value any arithmetic sees. It clears
the compat bar only because a decision already blessed it; nothing here compiles
wrong. Raise it if a real corpus reads the name.

## Gate

`make compiler/pascal26` plus `test/test_typeinfo_named_types.pas` under both
legs. Do not widen.
