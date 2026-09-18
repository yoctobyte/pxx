---
slug: bug-a-xtensa-unaligned-packed-record-field-access-faults
track: A
prio: 40
type: bug
status: new
created: 2026-09-18
found-by: frankH
owner: ""
summary: "Any access to a packed-record field that is not naturally aligned dies with SIGBUS on xtensa: `packed record B: Byte; I: Integer; W: Word; end` and `r.I := n` -> `qemu: uncaught target signal 7 (Bus error)`. xtensa's l32i/s32i fault on a misaligned word; the backend emits them for a packed field at offset 1. Measured 2026-09-18 with HEAD 316bbefd65cd and with the typed-const-record change alike, --platform=posix. A packed field needs byte-wise (or l8ui-composed) access on this target. Other strict-alignment targets not checked."
---

# Unaligned packed-record field access faults on xtensa

```pascal
program PK;
type TPk = packed record B: Byte; I: Integer; W: Word; end;
var r: TPk; n: Integer;
begin
  n := 5; r.B := 1; r.I := n; r.W := 3;
  WriteLn('I=', r.I);
end.
```

`--target=xtensa --platform=posix --xtensa-soft-mulhigh`, run under
`tools/run_target.sh xtensa`: `qemu: uncaught target signal 7 (Bus error)`.
x86-64 prints `I=5`.

`packed record` exists precisely to put fields at unaligned offsets (wire
formats, file headers), so this breaks real code on the ESP family, not an edge
case. The same class as the data-section alignment defect
(bug-a-a-perf-commit-silently-fixed-41-xtensa-windowed-divergences-and-nobody-knows-why),
one level down: there the section base was misaligned, here the field is by
design.

Found while differentially checking typed-const record baking. A packed record
CONST no longer faults at startup, because its bytes are baked now, but any
runtime access to `I` still faults.

Not checked: riscv32 (qemu tolerates misaligned access there, silicon may trap)
and arm32 (LDR alignment depends on SCTLR.A).
