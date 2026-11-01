---
track: A
prio: 60
type: bug
blocked-by: []
summary: "riscv32 only: indexing a `var` or `out` dynamic-array PARAMETER (read, write, or `@f[i]`) uses the wrong base — reads return garbage and writes land in foreign memory (silent corruption, later a segfault). const/value dyn-array params, static arrays, strings and record fields are correct. x86-64, i386, arm32 and aarch64 are all correct on the same source. Repro below, measured 2026-09-30 with pinned v398 and compiler/pascal26 at e9040c821."
status: done
owner: ""
---

# riscv32: indexing a `var`/`out` dynamic-array parameter uses the wrong base

- **Type:** bug (riscv32 backend codegen, silent wrong code) — **Track A**, tag **S**.
- **Filed:** 2026-09-30 from an ESP32-C3 app (`~/museum_landkaart`, a WS2811 LED
  controller) whose frame buffer is a `var f: TFrame` parameter. Found because
  the app's host tests are also run under `qemu-riscv32`.
- **Impact:** any ESP32-C3 program that fills a buffer through a `var` dyn-array
  parameter corrupts memory. No diagnostic, no crash at the site.

## Repro

```pascal
program r3;
type TFrame = array of Byte;
     TIA = array of Integer;
procedure A(var f: TFrame; px: Integer; v: Integer); begin f[px*3] := v; end;
procedure B(var f: TFrame; v: Integer); begin f[6] := v; end;
procedure C(var f: TFrame; px: Integer; v: Integer); var i: Integer; begin i := px*3; f[i] := v; end;
procedure D(f: TFrame; px: Integer; v: Integer); begin f[px*3] := v; end;
procedure E(var f: TIA; px: Integer; v: Integer); begin f[px*3] := v; end;
procedure F2(var f: TFrame; px: Integer; v: Byte); begin f[px*3] := v; end;
var f: TFrame; g: TIA;
begin
  SetLength(f, 90); SetLength(g, 90);
  A(f, 2, 7); write('A=', f[6]);
  B(f, 8); write(' B=', f[6]);
  C(f, 2, 9); write(' C=', f[6]);
  D(f, 2, 10); write(' D=', f[6]);
  E(g, 2, 11); write(' E=', g[6]);
  F2(f, 2, 12); write(' F=', f[6]);
  f[6] := 13; writeln(' direct=', f[6]);
end.
```

```
x86-64 / i386 / arm32 / aarch64:  A=7 B=8 C=9 D=10 E=11 F=12 direct=13
riscv32 (qemu-riscv32):           A=0 B=0 C=0 D=10 E=0 F=10 direct=13
```

## Boundary (varied shapes, same session)

| shape | riscv32 |
| --- | --- |
| `var f: array of T` — `f[i] := v` | **wrong** (store lost / misdirected) |
| `var f` — `Result := f[i]` | **wrong** (reads 0) |
| `out f` — `SetLength(f,n); f[i] := v` | **wrong** |
| `var f` — `SetLength(f,n); f[i] := v` | **wrong** (length right, element wrong) |
| `var f` — `p := @f[0]; p[i] := v` | **wrong** |
| `const f` / value `f` — read or write | correct |
| `var s: array[0..9] of Byte` (static) | correct |
| `var s: AnsiString` — `s[i] := c` | correct |
| `var r: TRec` — `r.a[i] := v` (dyn-array field) | correct |

The IR for `B` is target-neutral and looks right
(`PXXDBG=a.ir:B`: `lea [sym=f]` → `index lo=0 size=1` → `store_mem`), so the
missing dereference is in the riscv32 lowering of `index` whose base is the
`lea` of a by-reference dyn-array parameter: it appears to take the parameter
slot (pointer to the caller's variable) as the data pointer, one indirection
short.

## Acceptance

The repro prints the x86-64 line under `qemu-riscv32`; a test pinning it runs on
riscv32 (and xtensa, which is worth checking for the same shape).

## Resolution (2026-11-01)

No longer reproduces. On master 6ce28aeef0 the repro prints the x86-64 line on
riscv32 and also on xtensa (call0 and windowed). The ticket was filed against
v398, and the October riscv32 lowering work (load/store field offsets, slot
words in one lw, 0464cc9378) superseded the broken path. No single commit is
named as the fix: none was bisected. The ticket was never committed, so nothing
tracked it until now.

Regression test: test/test_a_var_dynarray_parameter_indexes_its_own_data.pas
(+ .expected, identical to FPC 3.2.2). It covers every shape in the boundary
table: var write/read, out + SetLength, var + SetLength, and @f[i]. It runs in
test-core on riscv32 and xtensa-windowed.
