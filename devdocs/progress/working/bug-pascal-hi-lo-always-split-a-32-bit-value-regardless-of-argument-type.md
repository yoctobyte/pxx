---
track: A
prio: 60
type: bug
summary: "Hi()/Lo() are declared only for Cardinal and QWord, so every narrower type widens to the 32-bit overload: hi(word($1234)) gives 0 where FPC gives $12, and an Int64 argument is TRUNCATED to 32 bits first. Silent wrong value"
status: working
owner: track-A-S
---

# `Hi` / `Lo` always split a 32-bit value, whatever the argument type

- **Type:** bug (SILENT wrong value — FPC parity) — **Track A** (the fix is in
  `compiler/builtin/builtin.pas`, which is A's ground and forces a repin)
- **Found:** 2026-08-02 by an extended differential sweep against the FPC oracle,
  in the shape of `tools/fpc_diff_probe.sh`.
- Silent: no error, no warning, a plausible number comes back.

## Measured — the whole table, against FPC

```pascal
var b: byte;     begin b := $AB;               writeln(hi(b), '|', lo(b)); end.
var w: word;     begin w := $1234;             writeln(hi(w), '|', lo(w)); end.
var l: longint;  begin l := $12345678;         writeln(hi(l), '|', lo(l)); end.
var q: int64;    begin q := $1122334455667788; writeln(hi(q), '|', lo(q)); end.
```

| argument | FPC | pxx | |
| --- | --- | --- | --- |
| `byte` `$AB` | `10 \| 11` (nibbles `$A`,`$B`) | `0 \| 171` | **wrong** |
| `word` `$1234` | `18 \| 52` (bytes `$12`,`$34`) | `0 \| 4660` | **wrong** |
| `smallint` `$1234` | `18 \| 52` | `0 \| 4660` | **wrong** |
| integer literal `$1234` | `18 \| 52` | `0 \| 4660` | **wrong** |
| `longint` `$12345678` | `4660 \| 22136` (words) | `4660 \| 22136` | ok |
| `int64` `$1122334455667788` | `287454020 \| 1432778632` (longwords `$11223344`,`$55667788`) | `21862 \| 30600` | **wrong** |

## The rule pxx is missing

FPC's `Hi`/`Lo` split the argument into **halves sized by the argument's own
type** — nibbles for a byte, bytes for a 16-bit type, words for a 32-bit type,
longwords for a 64-bit type. pxx splits a 32-bit value in every case.

That single sentence explains every row:

- narrower types (`byte`, `word`, `smallint`, an untyped integer literal) widen
  to the `Cardinal` overload, so they get **word** halves — the high half of a
  zero-extended byte or word is always `0`, which is the `hi(...) = 0` column;
- `longint` matches by coincidence — it IS the 32-bit case;
- `int64` is the interesting one: pxx returned `$5566 | $7788`, i.e. it took the
  **low 32 bits** and split those into words. So the `QWord` overload is not
  being selected at all; the argument is truncated into the `Cardinal` one.
  That is a second, independent fault — even adding the narrow overloads leaves
  Int64 wrong.

## Cause — read from the source, not inferred

`compiler/builtin/builtin.pas` declares exactly four:

```pascal
function Lo(v: Cardinal): Word;      { v and $FFFF }
function Lo(v: QWord): Cardinal;     { v and $FFFFFFFF }
function Hi(v: Cardinal): Word;      { (v shr 16) and $FFFF }
function Hi(v: QWord): Cardinal;     { (v shr 32) and $FFFFFFFF }
```

These are ordinary overloaded Pascal functions, not compiler intrinsics, so
resolution is by argument width — and a `Byte`/`Word`/`SmallInt` argument
converts to `Cardinal` cleanly, so the narrow case never had a candidate to
prefer. In FPC they are intrinsics that inspect the argument's declared type,
which is the behaviour being missed.

## The fix

Add the narrow overloads and make the 64-bit one actually reachable:

```pascal
function Lo(v: Byte): Byte;       { v and $0F }
function Hi(v: Byte): Byte;       { (v shr 4) and $0F }
function Lo(v: Word): Byte;       { v and $FF }
function Hi(v: Word): Byte;       { (v shr 8) and $FF }
```

Then diagnose the Int64 selection separately — the `QWord` overload exists and
is correct, so this is overload resolution preferring a narrowing conversion to
`Cardinal` over the exact-width `QWord` candidate. That preference is itself
worth checking beyond `Hi`/`Lo`: if a 64-bit argument silently picks a 32-bit
overload in general, this bug has siblings. See
[[project_builtin_overload_shadows_used_unit]] for the neighbouring hazard
(builtin overloads competing with a used unit's routine, steered by argument
width) — same resolution machinery.

Signed types need thought, not just a cast: `Hi`/`Lo` are bit operations, so a
negative `SmallInt` should split its two's-complement representation. FPC's
result type is unsigned; match that.

## Blast radius — small, checked

Nothing in `compiler/**` or `lib/rtl/**` calls `Hi` or `Lo` (grepped; the only
matches are `lo(Alo*Bhi)`-style comments in the 32-bit codegen backends). So the
overload set can change without moving the self-host compiler's own behaviour.

**But the file is `compiler/builtin/builtin.pas`, so this needs
`make stabilize` + `make pin` for the gate fixedpoint** (see
[[project_builtin_change_needs_repin_for_gate_fixedpoint]]) — which moves the
ground under every track building against `$(PXX_STABLE)`. That is why this was
filed rather than fixed on the spot during a bug hunt: the change is small, the
repin is the deliberate part and should be a deliberate act.

## Gate

A Pascal test diffed against FPC over the full table above — `byte`, `word`,
`shortint`, `smallint`, `longint`, `cardinal`, `int64`, `qword`, an untyped
literal, and a negative value of each signed type — plus `make test` and the
self-host fixedpoint, then `stabilize` + `pin`.

## DONE 2026-08-02 — every TYPED argument now matches FPC; Swap fixed too

### What the fix turned out to be — two bugs, and the second is the bigger one

Adding the missing narrow overloads (the ticket's plan) made the *typed* rows
right immediately, and made the literal rows **worse**: `hi($1234)` went from
`0|4660` to `3|4`. The literal was binding to the new `Lo(Byte)` overload and
being TRUNCATED to `$34` first.

That is not a Hi/Lo problem. Measured on a plain program with no builtin
involved:

```pascal
procedure p(v: byte); overload;  procedure p(v: word); overload;
procedure p(v: longint); overload;  procedure p(v: int64); overload;
p(40000);        { FPC: word 40000     pxx: byte 64 }
```

`MatchProcCall` took the first COMPATIBLE candidate in hash-chain order, so
whichever narrow overload happened to come first won and silently dropped the
high bits — a wrong value in ordinary user code, no diagnostic, nothing to do
with Hi/Lo. Same shape as the fpjson `CreateJSON(Data: Boolean)` incident that
`TypesCompatible` already carries a guard for.

Fixed with **Phase 1d** in `MatchProcCall`: a compatible match that does not
narrow an integer argument, tried before the general compatible phase, so a
lossless candidate beats a truncating one whatever the declaration order.
`ArgNarrowsInt` ranks, it does not reject — a narrowing candidate still wins
when it is the only one that matches (`q(v: Byte)` called with an Integer).

### Then the ticket's own fix

One overload per integer type for `Lo`, `Hi` **and `Swap`** — Swap has the
identical bug (`swap(word($1234))` gave 305397760 for FPC's 13330, and an Int64
argument was truncated), lives in the same file, and needs the same repin, so
fixing it separately would have cost a second repin for two lines.

Semantics measured from FPC, not assumed — including the two rows that read as
warts and would have been guessed wrong:

- **ShortInt is not split into nibbles the way Byte is.** FPC sign-extends it to
  16 bits first: `hi(shortint(-86))` = 255, not 10.
- **Swap has no nibble form at all**: a 1-byte argument widens to 16 bits and
  swaps ITS bytes, so `swap(byte($AB))` = `$AB00` = 43776, a Word — and the
  result keeps the argument's signedness (`swap(shortint(-86))` = -21761).

### Result — the ticket's table, re-measured

Every typed row matches FPC exactly: byte, shortint (both signs), word,
smallint, longint (both signs), cardinal, int64 (including -1), qword, and a
`Byte(200)` / `Word($1234)` cast. Same for Swap.

**Not matching, and split out:** an *untyped literal* still types as LongInt, so
`hi($1234)` = `0|4660` where FPC says `18|52`. That is pxx's literal typing, not
Hi/Lo — FPC gives a constant the smallest type that holds it. Filed as
[[bug-a-integer-literal-not-typed-by-its-value-for-overload-resolution]] with
the measured table. It is no longer a wrong *value*, only a wrong candidate, and
a cast gives FPC's answer today.

### Tests + gate

- `test/test_hilo_swap.pas` — the full FPC-measured table, expectations diffed
  against a real FPC run, wired into `make test`.
- `test/test_overload_no_narrowing.pas` — the truncation repro plus the
  only-narrow-candidate case, also in `make test`.
- Self-host fixedpoint went RED as the ticket predicted, and for exactly the
  predicted reason: the pinned stable ships its own frozen
  `stable_linux_amd64/default/builtin/builtin.pas`, so the seed-built compiler
  lacked the new overloads (the map diff shows only the 18 new Lo/Hi/Swap
  procs — the resolution change did NOT alter the compiler's own build).
  `make stabilize` + `make pin` -> **v240**, gate GREEN after.
- `tools/gate.sh quick` GREEN, FPC seed build clean.
