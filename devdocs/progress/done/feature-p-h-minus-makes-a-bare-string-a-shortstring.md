---
slug: feature-p-h-minus-makes-a-bare-string-a-shortstring
track: P
prio: 45
type: feature
blocked-by: []
status: done
owner: unassigned
created: 2026-09-05
summary: "{$H-} is accepted and ignored, so a bare `string` stays a managed 8-byte handle where the source asked for a 256-byte ShortString. MEASURED under {$mode objfpc}, which is the only mode where the directive bites: `record s: string; n: Integer` is 260 bytes under fpc 3.2.2 and 16 under pxx, and SizeOf(string) is 256 vs 8. It is line 3 of FPC 3.2.2's fpcdefs.inc, included by essentially every unit of that compiler, so this is the corpus-wide string model and not one file's opinion. Split out of feature-p-packenum-and-h-minus-for-the-fpc-compiler-corpus when the enum half landed; that ticket asked for exactly this measurement before scoping, and the answer is that the H half is real."
---

# `{$H-}` is accepted and ignored, and it is a record-layout change

Split from [[feature-p-packenum-and-h-minus-for-the-fpc-compiler-corpus]] when
the `{$PACKENUM}` half landed. That ticket said *"whether that is a problem for
pxx specifically needs measuring — pxx's string model is not FPC's — and that
measurement is half this ticket"*, and said to split if only one half turned out
real. **Both are real.** Here is the measurement.

## Measured, fpc 3.2.2 vs pxx, 2026-09-05, compiler `89f51a99f0b3`

`type TR = record s: string; n: Integer; end;`

| | `SizeOf(string)` | `SizeOf(TR)` |
| --- | --- | --- |
| `{$mode objfpc}{$H+}` fpc | 8 | 16 |
| `{$mode objfpc}{$H+}` pxx | 8 | 16 |
| `{$mode objfpc}{$H-}` fpc | **256** | **260** |
| `{$mode objfpc}{$H-}` pxx | 8 | 16 |

So `{$H+}` already agrees and `{$H-}` does not.

## The first probe could not fail, and that is worth recording

Measured WITHOUT `{$mode objfpc}` first, and fpc answered 256 in both arms — so
`{$H-}` looked like a no-op and the gap was invisible. **In plain mode a bare
`string` is ALREADY a ShortString**, i.e. `{$H-}` is the default there and the
directive changes nothing it could be caught changing. The discriminating probe
needs `{$mode objfpc}`, which is what `fpcdefs.inc` actually sets one line
earlier. A probe run in the wrong mode returns a real number, from a real
compiler, about a configuration where the question does not exist.

## Why it matters at corpus scale

`/usr/share/fpcsrc/3.2.2/compiler/fpcdefs.inc` lines 1-3 are `{$mode objfpc}`,
`{$asmmode default}`, `{$H-}` — and that include is pulled into essentially
every unit of the FPC compiler. So under `--mimic-fpc-compiler` every bare
`string` in those sources is a managed handle where the source declared a
256-byte inline buffer. Any record crossing between a pxx-built unit and a
differently-built one disagrees about where every field after the string lives.
Same failure shape as the enum half, and a much bigger field.

## Where to start

`BareStringKind` (util.inc) is the one function that answers *what a bare scalar
`string` IS*, and its header already says it was consolidated there precisely so
there is one answer. `tyShortString` (ordinal 25) already exists. The shape of
the fix is the one `{$PACKENUM}` just used: a per-token `TokHMinus` snapshot,
because **directives run in the LEX pass** — a global read at parse time gives
the last `{$H}` in the file to every declaration in it, and a file with a single
directive cannot tell the two apart.

## Gate

`SizeOf` of a bare `string` and of a record containing one, under
`{$mode objfpc}` with `{$H+}` and `{$H-}`, against fpc 3.2.2 — **both arms**,
since the `{$H+}` arm is the control that already passes and the `{$H-}` arm is
the claim. A single-arm test cannot distinguish "implemented" from "the default
already agreed".

## Related

- [[feature-p-packenum-and-h-minus-for-the-fpc-compiler-corpus]] — the other half, landed.
- [[goal-compile-fpc-compiler]] / [[feature-mimic-fpc-compiler-define-profile]]

---

## Landed (frankB, 2026-09-05, compiler `ba573b6cf02a`)

`{$H-}` / `{$H+}` / `{$LONGSTRINGS OFF}` / `{$LONGSTRINGS ON}` all implemented,
positionally, on the same per-token discipline `{$PACKENUM}` uses
(`TokHMinus[]`). `BareStringKind` — already the single answer to *what a bare
scalar `string` IS* — now consults the token being parsed.

### The kind was right and the type was still wrong

The first cut set the KIND correctly at every declaration site — instrumenting
`BareStringKind` showed it returning `tyShortString` on every call — and
`SizeOf` still answered **8** for a variable. A ShortString's CAPACITY has no
carrier in the kind: `string[N]` sets `LastTypeStrCap` from N and the
`shortstring` NAME sets 255, so a bare `string` under `{$H-}` is the **third
spelling of the same type** and had to set it too. The variable was allocated
with capacity 0.

`SizeOf(string)` then needed a second fix for the same missing fact:
`TypeSlotSize` takes a kind and no capacity, and the `shortstring` name never
reaches it (`BuiltinTypeNameNeedsDecl` routes that spelling through
`ParseTypeKind`). **Two sites, one omission** — the kind and the capacity are
one fact and neither half is sufficient.

### Measured

Five declaration paths, all against fpc 3.2.2, all 256 under `{$H-}`: a global,
a `type TS = string` alias, a record field, a local, and `SizeOf(string)`
itself. Values survive both models — concatenation, `Length`, a `const string`
parameter and result, `Copy`, `Pos`, and a record field of each model in one
program. `test_h_minus_shortstring`, `.expected` is fpc's own output.

### A separate divergence, measured and deliberately NOT changed

`{$mode objfpc}` does **not** imply `{$H+}` in fpc — only `{$mode delphi}` does:

| mode | fpc | pxx |
| --- | --- | --- |
| (none) / `objfpc` / `fpc` | 256 | 8 |
| `delphi` | 8 | 8 |

So pxx's *default* bare `string` matches fpc only in delphi mode. That is the
managed-string model this compiler chose, pre-dates this ticket, and is not
touched here — flipping a default is not what a directive ticket may do. It is
recorded because the row is easy to meet later and misread as this fix leaking.
The corpus is unaffected either way: `fpcdefs.inc` says `{$H-}` explicitly.

### On the corpus it was filed for

```
program fd2; {$i fpcdefs.inc}  var s: string;
  pxx --mimic-fpc-compiler : 256      fpc 3.2.2 : 256
```

**Correctness, not reach** — same as the enum half. The march is where it was:
`cutils`, `globtype`, `constexp`, `version`, `cstreams` COMPILE; four stop at
`TFPCHeapStatus`, `cmsgs` at its object constructor. Those five compiled before
too, with a managed handle where their own source said ShortString.

### Gate

`test_h_minus_shortstring` in test-core, BOTH arms — the `{$H+}` rows would pass
against a discarded directive, so only the `{$H-}` rows are the claim — plus a
switch back to `{$H+}` half way down the file, since a single-directive file
cannot catch a global read. `gate.sh quick` GREEN, FPC seed canary PASS.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
