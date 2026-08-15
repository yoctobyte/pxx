---
track: A
prio: 70
type: bug
blocked-by: []
summary: "On i386 ONLY, any access through a by-reference float parameter (`var r: Double` or `var r: Single`, and `out` likewise) segfaults on the first read or write inside the callee. Five-line repro. x86-64, aarch64, arm32 and riscv32 are all correct. Every optimization level, -O0 through -O3. Declaring the parameter and never touching it is fine, so it is the deref, not the prologue."
---

# i386: reading or writing through a `var Double` parameter faults

- **Type:** bug (i386 backend — **Track A**). Filed by Track B, which found it
  and does not edit the backends.
- **Found:** 2026-08-15, cross-verifying the new fast trig path under qemu.
  `pinned v339` (`f11e0ed9816e`), tree at `eaffab768`.
- **Severity:** a SEGFAULT, not a wrong value, and on a construct as ordinary as
  `procedure Split(x: Double; var hi, lo: Double)`. Nothing in the current i386
  test set happens to pass a float by reference, which is the only reason this
  has stayed invisible.

## Repro — five lines, no units

```pascal
program c1;
procedure F(var r: Double);
begin r := 1.0; end;
var a: Double;
begin a := 0.0; F(a); writeln(a:0:5); end.
```

```
$ pinned --target=i386 c1.pas c1-i386 && qemu-i386-static c1-i386
qemu: uncaught target signal 11 (Segmentation fault) - core dumped

$ pinned c1.pas c1-x64 && ./c1-x64          # x86-64
1.00000
$ pinned --target=arm32 ... ; --target=aarch64 ... ; --target=riscv32 ...
1.00000   (all three)
```

## The boundary, measured

| variation | i386 |
| --- | --- |
| `var r: Double`, written | **faults** |
| `var r: Double`, only READ (`t := r`) | **faults** |
| `out r: Double`, written | **faults** |
| `var r: Single`, written | **faults** |
| `var r: Double`, declared and never touched | ok |
| `var r: Integer`, written | ok |
| `var r: TDd` (a RECORD of two Doubles), written | ok |
| by-VALUE `x: Double` | ok |
| `-O0` / `-O1` / `-O2` / `-O3` | faults at every level |

Two rows carry the diagnosis. **Never touching the parameter is fine**, so the
prologue and the call sequence are not the problem — the fault is on the
dereference itself. And a **record of two Doubles by reference works**, so the
reference is being passed and stored correctly; it is specifically the
*float-typed* load/store through it that goes wrong. That points at the i386
float load/store path taking the parameter's slot as the value's address in one
case and as the address's address in the other — i.e. a missing (or doubled)
indirection when the base is a by-ref parameter rather than a local.

Faulting instruction is inside the callee, before the assignment completes:

```pascal
procedure F(var r: Double);
begin writeln('enter'); r := 1.0; writeln('assigned'); end;
```
prints `enter` and dies — `assigned` never appears.

## Why it surfaced now

`lib/rtl/math.pas`'s new default (fast) trig path calls

```pascal
procedure SinCosFast(x: Double; var sn, cs: Double);
```

so on i386, `Sin`/`Cos`/`Tan` now segfault in the default mode. The
`-dPXX_FLOAT_EXACT` path is unaffected only by luck: it passes `var sn, cs: TDd`,
and records happen to be the row that works.

## Fix direction

The i386 backend's address computation for a symbol that is a by-reference
parameter, on the float load/store path specifically. Compare against the
ordinal path in the same place, which handles the identical shape correctly, and
against the record path, which also works — the ordinal and record cases both
already do whatever the float case is missing.

## Gate

`make test` + self-host byte-identical, plus the repro above running under
`qemu-i386-static` on all four rows (read, write, `out`, `Single`), plus
`test/lib_math_fast_tolerance.pas` cross-built for i386 printing `MATHFAST OK`
— it already does on aarch64 and arm32.
