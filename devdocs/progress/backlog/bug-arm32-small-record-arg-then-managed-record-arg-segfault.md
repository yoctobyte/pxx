# arm32: a ≤8-byte by-value record call immediately followed by a managed-field record call segfaults

- **Type:** bug (arm32 backend — codegen, record-by-value call ABI) — Track A
- **Status:** backlog
- **Severity:** medium — cross-target only (arm32), narrow trigger shape, but a
  clean SIGSEGV with no diagnostic.
- **Opened:** 2026-07-01 (found while cross-verifying the fix for
  [[bug-byvalue-record-managed-field-aliases-caller]] on arm32/aarch64/i386/
  riscv32 — confirmed pre-existing on the unmodified pre-fix binary, unrelated
  to that fix)

## Symptom

On the arm32 target only, calling a procedure with a small (≤8-byte) by-value
record argument, immediately followed by calling a (separate) procedure with a
by-value record argument that has a managed field (e.g. `string`), segfaults
on the SECOND call:

```pascal
program arm_iso5;
type
  TPlain = record a, b: integer; end;            { 8 bytes }
  TMan   = record a: integer; s: string; end;    { 16 bytes, managed field }
procedure modPlain(r: TPlain); begin r.a := 999; r.b := 888; end;
procedure modMan(r: TMan); begin r.a := 999; r.s := 'changed'; end;
var
  p: TPlain;
  m: TMan;
begin
  p.a := 1; p.b := 2;
  modPlain(p);
  writeln(p.a, ',', p.b);      { prints fine: 1,2 }
  m.a := 1; m.s := 'orig'; modMan(m);
  writeln(m.a, ',', m.s);      { never reached: SIGSEGV }
end.
```

Compiled `--target=arm32` and run under `tools/run_target.sh arm32`: prints
`1,2` then crashes (exit 139 / `qemu: uncaught target signal 11`) before
printing anything from the second `writeln`.

## Isolation (against stable v134, and confirmed pre-existing on the v134
baseline before the aliasing fix landed — same crash either way)

| Sequence | arm32 result |
| --- | --- |
| `modMan(m)` alone (managed record call, no preceding small-record call) | **OK** |
| `modBig(b)` (12-byte non-managed record, no temp needed either way) then `modMan(m)` | **OK** |
| `modPlain(p)` (8-byte record, exactly at the "no temp needed" size threshold) then `modMan(m)` | **SIGSEGV** |
| Same program, x86-64 native | OK |
| Same program, `--target=aarch64` under qemu | OK |
| Same program, `--target=i386` | rejected at compile time: `only ordinal/pointer parameters supported yet` (pre-existing, known, unrelated gap — record-by-value params aren't implemented on i386 yet) |
| Same program, `--target=riscv32` | rejected at compile time: `managed aggregate locals not yet supported` (pre-existing, known, unrelated gap) |

So this is narrower than "record-by-value is broken on arm32" (plenty of
shapes work — a managed-record call on its own, and a non-managed >8-byte
record call followed by a managed-record call, both run fine). The specific
trigger is a record **exactly at the ≤8-byte "pass as a plain value, no
temp" threshold** (`compiler/ir.inc`, `IRLowerCallArg`'s
`if RecSize(argRecId) > 8 then needTemp := True` branch — `TPlain` takes the
`RecSize <= 8`, no-temp path) immediately preceding a call that DOES need a
temp+`IR_COPY_REC_MANAGED`. Smells like the small-record call leaves some
piece of arm32 codegen state (a register, a scratch stack slot, an argument-
marshalling assumption) inconsistent for the following call's temp/copy
machinery — but not root-caused beyond this isolation.

## Direction

Compare arm32's `IR_ARG`/call-marshalling codegen for the `RecSize <= 8`
plain-value path (`ir_codegen_arm32.inc`) against x86-64/aarch64's equivalent
(which don't reproduce) for what register/stack state the small-record path
leaves behind, and whether the very next call's `IR_COPY_REC_MANAGED` /
temp-argument setup on arm32 makes an assumption that path violates. Note
[[bug-nested-dynarray-cross-segfault]] and other arm32/i386-32-bit-target
codegen gaps already open — may or may not share a root cause (register
allocation / stack layout assumptions unique to the 32-bit backends), but
filing separately since the symptom (specific two-call sequence) and area
(record-by-value ABI, not dynarray handles) are distinct.

## Acceptance

- The exact repro above runs correctly on arm32 (prints `1,2` then
  `999,changed`).
- A regression test added covering this call sequence, wired into
  `make test-arm32` (or wherever arm32 cross regression tests for record
  params live).
- Confirm no similar latent issue on i386/riscv32 once those targets gain
  record-by-value-with-managed-fields support (tracked separately, not part
  of this ticket — they currently reject the construct outright rather than
  miscompiling it).

## Log
- 2026-07-01 — Opened while cross-verifying the fix for
  bug-byvalue-record-managed-field-aliases-caller. Confirmed pre-existing on
  the pre-fix v134 baseline (`git stash` back to before the fix, same crash)
  — this bug predates that work and is unrelated to it. Not investigated
  further this session — out of scope for the pass that found it.
