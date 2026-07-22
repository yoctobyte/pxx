---
track: A
prio: 70
type: bug
---

# aarch64: repeated string concat inside a function LEAKS

Found while leak-checking promotable-int variant integration 2026-07-20.
**Not promo-specific** — this is ordinary Pascal on aarch64 and affects any
string-building code.

## Repro

```pascal
program p;
function Build: AnsiString;
var s: AnsiString; i: Integer;
begin
  s := '';
  for i := 1 to 20 do s := s + '123456789';
  Build := s;
end;
var k: Integer; r: AnsiString;
begin
  for k := 1 to 20000 do r := Build;
  Writeln('done');
end.
```

| target | max RSS |
| --- | --- |
| x86-64 | 264 KB (flat) |
| aarch64 (qemu) | 10.5 MB, against a ~6.4 MB qemu baseline |

Growth scales with the iteration count, so it is a leak, not a high-water mark.

## What it is NOT

Narrowed by elimination, all measured on both targets:

- NOT the managed store through a typed pointer (`PStr(@buf)^ := s` in a loop is
  flat on aarch64).
- NOT returning a record containing a dynamic array by value (that grows
  comparably on BOTH targets — ~+1.4 MB x86-64 vs ~+1.7 MB aarch64 over 20k
  calls, so whatever that is, it is not target-specific).
- NOT promotable-int specific: the promo copy path (`b := a` on two promo
  variables, no strings) is flat on aarch64.

So the suspect is the intermediate temporaries of `s := s + <literal>` inside a
function body — the concat result temp, or the function-result AnsiString — not
being released on the aarch64 path.

## Impact

Any aarch64 program that builds strings in a loop. It surfaced through the
promotable int because its `BToStr` renders a bignum by repeated concatenation,
so a promo→variant boxing loop on aarch64 grows ~70 bytes per iteration while
the same loop on x86-64 is flat. Promotable int is left ENABLED on aarch64: the
values it produces are exact and it does not crash, so gating the target would
remove working functionality to hide a defect that is not its own.

## Gate

The repro above flat on aarch64, `--tier quick` + self-host byte-identical +
cross. Worth checking arm32/riscv32 for the same shape once found.

## Log
- 2026-07-22 — resolved, commit c46ba554.
