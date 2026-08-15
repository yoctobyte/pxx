---
track: A
prio: 70
type: bug
blocked-by: []
summary: "On i386 ONLY, any access through a by-reference float parameter (`var r: Double` or `var r: Single`, and `out` likewise) segfaults on the first read or write inside the callee. Five-line repro. x86-64, aarch64, arm32 and riscv32 are all correct. Every optimization level, -O0 through -O3. Declaring the parameter and never touching it is fine, so it is the deref, not the prologue."
status: done
owner: claude-A-N
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

## RESOLVED — it was the CALLER and the PROLOGUE, not the deref

The ticket's diagnosis ("a missing indirection on the float load/store path")
was wrong, and the row that misled it is the one it leaned on: *never touching
the parameter is fine*. That is equally consistent with a **caller** bug,
because i386 cdecl has the caller clean its own pushes — a mis-sized argument
never disturbs a callee that ignores it. Measured instead of reasoned
(`objdump -D -b binary -m i386`, since pxx binaries carry no sections):

```
mov  $0x805d728,%eax     ; &a — correct
cvtsi2sd %eax,%xmm0      ; the ADDRESS converted to a double
sub  $0x8,%esp
movsd %xmm0,(%esp)       ; pushed as an 8-byte VALUE
call F
```

and inside `F`, the prologue spilled **8 bytes** of that into a 4-byte slot:
with `r` at `[ebp-4]`, the second dword landed on `[ebp+0]` — the **saved
ebp**. The store path itself (`ir_codegen386.inc` IR_STORE_SYM, float leg) was
already correct: it has a proper `skParam`+`IsRef` branch that derefs.

One concept — "a by-ref float param is a pointer, not a value" — was missing at
**three** sites, all of which take the float branch on the param's declared
TypeKind without asking whether it is by reference:

1. `compiler/ir_codegen386.inc`, internal call arg marshalling — took the float
   path (cvtsi2sd + 8-byte push) for a `var Double`/`var Single`.
2. `compiler/ir_codegen386.inc`, **external cdecl** call — same shape, in both
   the `argBytes` accounting and the arg-slot store, so any
   `procedure f(var d: Double); cdecl; external` was mis-marshalled too. Fixed
   with the sibling grep, not because a ticket reported it.
3. `compiler/parser.inc`, the i386 callee prologue param spill — the
   `TypeKind = tyDouble` branch copied two dwords. Its own `sz` walk already
   counted a by-ref param as ONE word (via `pbyref[j]`), so the two halves of
   the same loop disagreed.

Guard shape is `IsArray or not IsRef`, matching the 64-bit by-value branch
alongside it — an open array of Double keeps the 8-byte push that both sides
already agree on.

**Verified** (sha of the binary: self-hosted fixedpoint at this commit):
all four rows plus a two-`var`-param split run under `qemu-i386-static` and
match the x86-64 oracle byte for byte; arm32 / aarch64 / riscv32 unchanged;
`test/lib_math_fast_tolerance.pas` on i386 prints `MATHFAST OK` (44 rows);
the external-cdecl marshalling checked by disassembly (`modf(double, double*)`
→ double at `[esp+0]`, pointer at `[esp+8]`, 12-byte arg block). Regression
rows added to `test/test_i386_float_params.pas`, which the Makefile already
runs as an i386-vs-x86-64 differential. `tools/gate.sh quick` GREEN.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
