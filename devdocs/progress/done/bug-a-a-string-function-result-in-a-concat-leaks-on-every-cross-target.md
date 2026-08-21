---
track: A
prio: 45
type: bug
blocked-by: []
summary: "`s := 'lit' + F(x)` where F returns a string leaks the function-result temp on i386, arm32, aarch64 AND riscv32 — ~320 bytes per evaluation, flat on x86-64. Neither half leaks alone: a literal+literal concat is flat and a bare `s := F(x)` is flat; it is the concat of a literal with a CALL RESULT that never releases the temp."
status: done
owner: claude-A
---

# A string function result inside a concat leaks on every cross target

- **Track A** (the four cross backends' concat/temp lowering).
- Found 2026-08-21 while measuring the dyn-array scope-exit release
  ([[bug-a-no-dyn-array-scope-exit-release-on-four-backends]]) — it was the
  residual that stayed after that leak was closed, and it turned out to have
  nothing to do with arrays.

## Repro — minimal, no array involved

```pascal
program lk;
function Mk(i: Integer): string;
begin
  Mk := 'val';
end;
procedure Churn;
var s: string; i: Integer;
begin
  for i := 0 to 7 do s := 'e-' + Mk(i);
end;
var k: Integer;
begin
  for k := 1 to 200000 do Churn;
  Writeln('done');
end.
```

Peak RSS, 200k x 8 evaluations (`/usr/bin/time -f %M`, cross runs under
`tools/run_target.sh`; the emulator's own floor is ~7 MB):

| target | peak RSS |
| --- | --- |
| x86-64 | **392 KB** (flat) |
| i386 | 62.3 MB |
| arm32 | 68.8 MB |
| aarch64 | 69.9 MB |
| riscv32 | 68.6 MB |

Linear in the call count — arm32 measured at 25k / 200k / 400k iterations gives
16.5 MB / 71.2 MB / 133.8 MB. About **320 bytes per evaluation**.

Pre-existing, not a regression: `stable_linux_amd64/default/pinned` measures
68.8 MB on arm32 for the same program.

## It is specifically literal + CALL RESULT

Both halves are individually flat on the same targets, which is what makes this
a narrow bug rather than "concat leaks":

| program | arm32 | aarch64 |
| --- | --- | --- |
| `s := 'element-' + 'x'` | 7.6 MB (floor) | 7.3 MB (floor) |
| `s := IntToStr(i)` | 8.9 MB (floor) | 7.8 MB (floor) |
| `s := 'e-' + IntToStr(i)` | **71.2 MB** | **69.8 MB** |
| `s := 'e-' + Mk(i)` (user fn) | **68.8 MB** | **69.9 MB** |

So it is not IntToStr and not the RTL — a plain user function returning a string
leaks the same way. The +1 the callee hands back is dropped on the floor once
the concat has consumed the temp.

## Where to look

x86-64 releases that temp; the four others do not. Compare how the x86-64
concat lowering disposes of a call-result operand against each cross backend's,
and look for the "fresh call result already carries +1, do not retain, DO
release after use" pairing — the retain side of that carve-out is present on
these backends (the IR_STORE_SYM / IR_STORE_DYN dyn-array arms all test
`IRKind = IR_CALL`), which suggests the release side is what is missing.

Expect it to be one shared decision rather than four: the same 320-byte
signature on all four targets, with x86-64 the only one that differs, is the
signature of one arm that exists in exactly one backend.

## Gate

The repro above flat (at the ~7 MB emulator floor) on i386 / arm32 / aarch64 /
riscv32; x86-64 unchanged at 392 KB; the dyn-array + interface cross
differential (53 tests x 4 targets) no worse than its recorded baseline;
self-host fixedpoint + `tools/gate.sh quick`.

## RESOLVED 2026-08-21 — it was a predicate copied five times, four of them short

`ir_codegen.inc` already carries the answer, and its comment already says why:

```pascal
{ Does this IR node produce a managed string that is ALREADY owned (+1) by
  whoever receives it, so storing it MOVES rather than retains? A concat result
  and a user CALL result both are — and a call is a call whether it is direct,
  virtual or indirect. Three stores carried this discrimination and all three
  listed IR_CALL only ... One predicate, so the next call kind is added in one
  place. }
function IRNodeOwnsManagedStr(n: Integer): Boolean;
```

The four cross backends never called it. Each had hand-rolled

```pascal
if (IRKind[left] = IR_BINOP) and (IntToTypeKind(IRTk[left]) = tyAnsiString) then
```

— six times per backend (concat, string equality, and the ordered arm added
earlier today), 24 sites, every one of them listing IR_BINOP only. A nested
concat's temp was released; a CALL result never was.

x86-64 had the right SET of kinds but spelled out inline rather than through the
predicate — a fifth copy — and its comment described this exact leak as fixed:
*"Without the call arm every `"x" + f()` leaked f's result once per evaluation."*
It was fixed on one target out of five.

### Fix

All 24 cross sites now ask
`(IntToTypeKind(IRTk[X]) = tyAnsiString) and IRNodeOwnsManagedStr(X)`, and
x86-64's two inline copies were replaced by the same expression (equivalent
under the `tyAnsiString` conjunct, and the self-host fixedpoint proves the
binary is byte-identical). The predicate is forwarded in `compiler.pas` because
the backends are included before `ir_codegen.inc`.

Six copies of one question became one.

### Measured — 200k x 8 evaluations, peak RSS (emulator floor ~7 MB)

| program | target | before | after |
| --- | --- | --- | --- |
| `s := 'e-' + Mk(i)` (user fn) | i386 | 62.3 MB | **7.8 MB** |
| | arm32 | 68.8 MB | **7.7 MB** |
| | aarch64 | 69.9 MB | **7.7 MB** |
| | riscv32 | 68.6 MB | **7.7 MB** |
| `s := 'e-' + IntToStr(i)` | i386 | 62.6 MB | **7.7 MB** |
| | arm32 | 71.2 MB | **8.8 MB** |
| | aarch64 | 69.8 MB | **7.7 MB** |
| | riscv32 | 68.8 MB | **7.5 MB** |
| `a[i] := 'element-' + IntToStr(i)`, 8-elem local dyn array | riscv32 | 68.7 MB | **7.7 MB** |
| same, **400k** iterations | riscv32 | — | **7.8 MB** (flat) |

x86-64 unchanged at 392 KB throughout.

### Cross differential

53-test dyn-array + interface family: **broke 0**. Zero newly-fixed is the
expected result — a leak produces no output, which is exactly why this survived
in the first place and why the RSS numbers above are the real gate.

### Gate

`tools/gate.sh quick` GREEN (self-host fixedpoint byte-identical, which also
confirms the x86-64 refactor changed no code).

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
