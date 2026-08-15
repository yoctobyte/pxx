---
track: A
prio: 30
type: compat
blocked-by: []
summary: "Given overloads on Int64 and LongInt, pxx selects Int64 for Integer / SmallInt / Byte / an untyped literal; only an exact type-NAME match picks LongInt. FPC picks the narrowest that FITS. The widening is NOT a bug — it is the dialect (user, 2026-08-14) — but --strict-fpc must reproduce FPC's rule, because a width-sensitive routine like IntToHex answers differently under it. Compat work behind the flag, not a default-behaviour change."
status: done
owner: claude-A-N
---

# `--strict-fpc` should pick the narrowest integer overload

- **Type:** compat (FPC parity behind a flag) — **Track A** (overload resolution
  lives in the shared `parser.inc`/`symtab.inc` ground; Pascal surface, so
  P-adjacent).
- **NOT A BUG — retitled 2026-08-14.** Filed by Track B as
  `bug-a-overload-resolution-widens-to-int64-…` on the assumption that the
  widening was a defect. The user's call:

  > *"this widening is not a bug. BUT it affects `--strict-fpc` mode"*

  So the default dialect keeps widening to the widest overload, deliberately,
  and the parity work belongs behind the flag. Same shape as
  `StrictVariantChar` and `StrictShiftWidth`: PXX's dialect stays lax by
  default, FPC's exact rule is opt-in.

## Measured — pxx vs FPC 3.2.2, same source

```pascal
program h3;
function F(v: Int64): AnsiString; overload;
begin F := 'int64'; end;
function F(v: LongInt): AnsiString; overload;
begin F := 'longint'; end;
var i: Integer; li: LongInt; si: SmallInt; c: Cardinal; b: Byte;
begin
  i := -1; li := -1; si := -1; c := 1; b := 1;
  WriteLn('Integer  -> ', F(i));
  WriteLn('LongInt  -> ', F(li));
  WriteLn('SmallInt -> ', F(si));
  WriteLn('Cardinal -> ', F(c));
  WriteLn('Byte     -> ', F(b));
  WriteLn('literal  -> ', F(-1));
end.
```

| argument | pxx (default dialect) | FPC (`{$mode objfpc}`) |
| --- | --- | --- |
| `Integer` | int64 | **longint** |
| `LongInt` | longint | longint |
| `SmallInt` | int64 | **longint** |
| `Cardinal` | int64 | int64 |
| `Byte` | int64 | **longint** |
| literal `-1` | int64 | **longint** |

`Cardinal` agrees, and it is the row that shows FPC's rule is not "narrowest
declared": `LongInt` cannot hold every `Cardinal`, so `Int64` is the narrowest
that FITS and FPC picks it. FPC's rule is therefore *narrowest that fits*, not
*exact match then anything wider*.

`SizeOf(Integer) = SizeOf(LongInt) = 4` in pxx, and the `LongInt` row proves the
narrow overload is reachable — so what selects it today is the type **name**,
not the type.

## Why it still matters even though the default is intended

An overload set on integer widths exists to give each width its own behaviour,
so the choice is observable in the answer, not just in which body ran:

```pascal
var i: Integer;
begin
  i := -1;
  WriteLn(IntToHex(i, 8));   { pxx FFFFFFFFFFFFFFFF · FPC FFFFFFFF }
end.
```

`lib/rtl/sysutils` declares the FPC family (`Int64` / `LongInt` / `LongWord`)
and its `LongInt` body masks correctly, so a `LongInt` argument already answers
`FFFFFFFF`. An `Integer` argument sign-extends into the `Int64` spelling — by
design in the default dialect, and wrong under `--strict-fpc`. That is
[[bug-b-inttohex-of-a-negative-integer-prints-16-digits]], whose remaining half
is exactly this flag.

The RTL cannot paper over it either way: adding an `Integer` overload beside the
`LongInt` one would be compiler-appeasement (in FPC they are the same type, so
the family already declared IS the platonic form).

## Scope

- **Default dialect: unchanged.** Widening to the widest candidate stays.
- **Under `--strict-fpc`:** rank integer candidates by *(fits ? width :
  reject)*, narrowest first, so an alias resolves like its underlying type.
  `Cardinal` already agrees and must not regress.
- **Umbrella enrolment is a separate call**, per the precedent in
  [[decide-may-uses-math-cost-the-heap-and-exception-runtime]] and
  `StrictOverload`'s deliberate exclusion: adding a member changes what
  `--strict-fpc` costs for the corpora it is *"proven to compile"* (fgl,
  Synapse, fpjson 203/203), so re-check those before enrolling rather than
  enrolling automatically. A standalone `--strict-overload-width`-style flag is
  the safe first landing.

## Sweep before closing

Same question for the unsigned family (`Byte`/`Word`/`Cardinal`/`QWord` sets),
for `Single`/`Double`/`Extended` sets, and for a user alias
(`type MyInt = Integer`) — the same name-vs-type question one level out.

## Gate

Under `--strict-fpc` the table above matches FPC on every row and
`bug-b-inttohex-…`'s 14-row FPC diff goes green; **without** the flag every row
is unchanged from today. `make test` + self-host fixedpoint, and the corpora
`--strict-fpc` already compiles stay green.

## RESOLVED — landed as the standalone `--strict-overload-width`

Every row of the ticket's table now matches FPC 3.2.2 under the flag, and the
default dialect is byte-identical to `pinned` without it.

| argument | default (unchanged) | `--strict-overload-width` | FPC |
| --- | --- | --- | --- |
| `Integer` | int64 | **longint** | longint |
| `LongInt` | longint | longint | longint |
| `SmallInt` | int64 | **longint** | longint |
| `Cardinal` | int64 | int64 | int64 |
| `Byte` | int64 | **longint** | longint |
| literal `-1` | int64 | **longint** | longint |

### The `Cardinal` row is the whole design, and it needed a new predicate

Ranking the qualifying candidates by declared width got five rows right and
broke `Cardinal` — it started answering `longint` where FPC says `int64`. The
existing `ArgNarrowsInt` compares `TypeSize(pType) < TypeSize(aType)` and is
**signedness-blind**, so it reports that a `LongInt` parameter does not narrow a
`Cardinal` argument. It does: same width, half the range unreachable.

So the flag needs its own fits test, `IntParamHoldsEveryValue` — same width when
the signedness agrees, one width wider for a signed parameter taking an unsigned
argument, never for an unsigned parameter taking a signed one.
**`ArgNarrowsInt` was deliberately left alone**: it ranks candidates on the
DEFAULT path too, and the default's widening is intended behaviour, so
"fixing" it there would have been a dialect change smuggled in under a compat
ticket.

### Shape of the change

The ranking is collected inside Phase 1c2's existing walk and only when the flag
is set; the unflagged path still returns the first qualifying candidate and exits,
byte for byte as before. A candidate that cannot hold every value of its argument
is not ranked at all but stays reachable through the ordinary phases below —
which is what keeps *"a narrowing candidate still wins when it is the only one"*
true (asserted: an `N(SmallInt)`-only set still binds for an `Integer` argument,
flag or not).

### Sweep (the ticket's own list), all against FPC

- **unsigned family** `QWord`/`LongWord`/`Word`: `Byte`→word, `Word`→word,
  `Cardinal`→longword, `QWord`→qword. Matches.
- **float sets** `Double`/`Single`: unchanged by the flag, and already agreed.
  (`Extended` is not a separate candidate here — pxx maps it onto the same
  8-byte kind as `Double` on this target, so declaring both is a duplicate
  definition rather than an overload set.)
- **user alias** `type MyInt = Integer`: resolves like `Integer` → longint.
  Matches — the name-vs-type question one level out comes out right for free,
  because the ranking reads the type kind and never the spelling.

### Umbrella: NOT enrolled, per this ticket's own Scope

Standalone, like `StrictOverload` and for the same reason — it changes which
BODY a call binds to, so enrolling it changes what the corpora `--strict-fpc` is
*"proven to compile"* resolve to. That call needs those corpora re-measured and
is deliberately not made here. **A consequence worth stating: `--strict-fpc`
alone does not yet reproduce FPC's overload widths**, so this ticket's Gate line
("under `--strict-fpc` the table matches") is satisfied by
`--strict-overload-width` instead, which is what its Scope section asked for.

### Downstream: Track B is unblocked

[[bug-b-inttohex-of-a-negative-integer-prints-16-digits]]'s **14-row FPC diff
passes verbatim under the flag** — `Integer` −1/−255/MinInt/positive, `digits` 2
and 16, `Int64`, `Byte`, `Word`, `Cardinal` and the three literal rows,
byte-identical to FPC. Its RTL side needed nothing: the `Int64`/`LongInt`/
`LongWord` family it already declares is the platonic one, and the `LongInt`
body's mask is what makes the answer right once that body is selected. Its
`blocked-by` is cleared and it is out of `blocked/`.

### Verified

`test/test_strict_overload_width.pas` asserts BOTH modes from one source (the
flag exists precisely because the answers differ, so the unflagged row is the
guarantee the default did not move); both assertions are wired into the
Makefile. Flagged output byte-identical to FPC; unflagged output byte-identical
to `pinned`. `tools/gate.sh quick` GREEN.

Docs row filed as [[task-d-document-the-strict-overload-width-flag]] —
`docs/**` is Track D's lane, not Track A's.

## Log
- 2026-08-15 — resolved, commit d75deb89a.
