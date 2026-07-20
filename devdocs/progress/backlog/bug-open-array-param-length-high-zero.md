---
prio: 65  # auto — silent wrong value on a core Pascal idiom; loops over open arrays just don't run
track: P
---

# `Length()` / `High()` on an open-array parameter return 0 / -1

- **Type:** bug — **Track P** (Pascal frontend; open-array parameter lowering).
  May be the shared open-array descriptor / ABI rather than the frontend, in
  which case it belongs to A — the two live next to each other.
- **Status:** backlog — filed 2026-07-20.
- **Found by:** Track B, writing `lib/rtl/truststore.pas`
  ([[feature-tls-system-trust-store]]) — a `for i := 0 to High(a)` style bound
  over an open-array out-parameter silently produced an empty result.

## Repro

```pascal
program OA;
procedure P(var a: array of AnsiString);
begin
  writeln('Length(open array) = ', Length(a), '  High = ', High(a));
end;
var arr: array[0..9] of AnsiString;
begin
  P(arr);
end.
```
```
Length(open array) = 0  High = -1
```

FPC prints `10` and `9`. The array passed is a fixed `array[0..9]`, so the
bounds are statically known at the call site; they are simply not reaching the
callee.

## Why it matters

`Length(a)` / `High(a)` inside a routine taking `array of T` is *the* idiomatic
way to write a bounds-safe helper in Pascal — it is how every "fill this buffer,
tell me how many" API is written. With this bug:

- `for i := 0 to High(a) do ...` iterates **zero times**.
- `while (n < Length(a)) ...` exits immediately.
- A capacity check `if n >= Length(a) then Break` fires on the first element.

All three fail **silently and plausibly**: the function returns 0 results, which
reads as "nothing found" rather than "the loop never ran". In the case that
found it, a PEM bundle with 121 certificates parsed to 0 anchors, and the
natural next suspicion was the parser, not the loop bound. That is the expensive
kind of bug — it sends you looking at the wrong component.

It is also a **security-relevant shape** in this instance: the consumer is a TLS
trust store, and "loaded 0 trusted roots" happens to fail closed here only
because the code explicitly treats an empty store as trusting nothing. Written
slightly differently — say, "no roots loaded, skip verification" — the same bug
would fail open.

## Scope to check

- `const a: array of T` and by-value `a: array of T`, not just `var`.
- Whether a **dynamic** array passed to an open-array parameter behaves (it may
  well work, since it carries its own length — worth knowing, because it would
  explain why this has not been hit before).
- `Low(a)` — presumably 0 and correct, but confirm.
- Open arrays of records / of a managed type (AnsiString here) vs of simple
  scalars, in case the descriptor differs.
- Array-of-const (`array of const`) is a separate mechanism; check whether it
  shares the defect.

## Workaround in the meantime

Pass the capacity explicitly as a second parameter. `lib/rtl/truststore.pas`
does this (`PemSplit(..., ders, cap)`) with a comment pointing here; it is a
defensible API on its own terms, which is why it was preferred over indexing
tricks, but it should revert to `Length(ders)` once this is fixed.

## Acceptance

- The repro prints `10` / `9`.
- A regression test covering `Length`/`High`/`Low` for `var`, `const` and
  by-value open-array parameters, over both a fixed array and a dynamic array
  argument, for a scalar and a managed element type.
- Gate: `make test` + self-host byte-identical.

## Links
[[feature-tls-system-trust-store]] · `lib/rtl/truststore.pas` (the workaround
and its comment).

## Log
- 2026-07-20 — Filed from Track B with the repro above.
