# arm32: by-value record params over 4 bytes drop their high word (ABI gap)

<!-- was: "arm32: a ≤8-byte by-value record call immediately followed by a
     managed-field record call segfaults" — renamed once the root cause
     turned out to be the already-known >4-byte record-arg ABI gap, not a
     two-call interaction. -->


- **Type:** bug (arm32 backend — codegen, record-by-value call ABI) — Track A
- **Status:** done — fixed pin v137, 2026-07-01/02
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
- 2026-07-01 (later, same session) — Root-caused. This is the SAME gap
  [[bug-aarch64-arm32-record-temp-byvalue-arg]] (done, v65) explicitly
  flagged as a deferred residual: *"arm32 records > 4 bytes: the arm32
  by-value record-param marshalling/prologue only carries the low 4 bytes
  ... a >4-byte record arg is wrong on arm32. Needs the arm32 record-param
  ABI widened to r0:r1 (caller + prologue)"* — `TPlain` (two `Integer`
  fields, 8 bytes) is exactly this shape.

  Confirmed three separate spots in `ir_codegen_arm32.inc` all still only
  handle a *4-byte* by-value record, silently dropping the high word for a
  5-8 byte one:
  1. `IR_LOAD_SYM` (loading a record VALUE from a plain variable, e.g.
     `modPlain(p)`'s argument): gates 64-bit handling on `Is64BitArm32(tk)`,
     which only recognizes `tyInt64`/`tyUInt64` — a same-size `tyRecord`
     falls through to the generic 1-word `EmitLoadVarArm32`.
  2. `IR_LOAD_MEM`'s own comment already says as much: *"tyRecord (<=4-byte
     by-value record) loads its packed bytes into r0 ... Records >4 bytes
     need the arm32 record-param marshalling widened"*.
  3. The generic by-value call-argument loop (`IR_CALL`, the "word-based
     argument passing" section) has explicit 2-word handling for
     `tyAnsiString`/`tyInt64`/`tyUInt64`/float params but NO case for a
     plain by-value `tyRecord` param — it falls to the 1-word `else`
     branch regardless of `RecSize`.

  This means `modPlain(p)` only ever pushes ONE word for `p`'s 8 bytes (the
  `a` field; `b` is silently dropped) — a real, separate data-correctness
  bug in its own right, independent of whatever then causes the SECOND
  call to crash. Whether that single missing word also desyncs the stack
  balance for everything after `modPlain` returns (my working theory for
  why the *next* call specifically crashes) is not yet confirmed with a
  memory/register trace — flagging as the most likely mechanism, not a
  proven one.

  **Not attempted this session**: fixing this properly means widening the
  arm32 by-value record ABI at all three points above (caller value-load,
  caller arg-push, and very likely the CALLEE's prologue/param-reception
  path too, which I have not yet located) — real, non-trivial call-ABI
  surgery with a large blast radius (touches every by-value record call on
  arm32), late in a solo overnight pass with no one to sanity-check a
  mistake here. Parking with this much narrower, concrete root cause
  instead of the vague "investigate the two-call interaction" framing this
  ticket opened with — whoever picks it up next should start from the
  three call sites above, not re-derive them.

## Fixed (2026-07-01/02, pin v137)

Came back to this the same session after landing the nested-dynarray fix,
since the root cause was now precise rather than vague. Widened all three
call sites identified above (`IR_LOAD_SYM`, the by-value call-arg push loop,
and — found by tracing the actual prologue spill code in `parser.inc` — the
callee's param-spill loop, a fourth site not yet located when this ticket
was first parked) to treat a plain by-value `tyRecord` param with
`RecSize` in `(4, 8]` as two words, exactly mirroring the existing
Int64/Double handling already proven correct at every register/stack
boundary shape.

**A fix at just those sites regressed a case that used to merely lose data**:
a record arg mixed among scalar params (`f1(x: integer; r: TPlain; y:
integer)`) now printed `x=8` instead of `1` — the record's second word
correctly loaded into registers, but then WRITTEN past the end of the
record's own 4-byte frame slot into the adjacent parameter's slot,
corrupting it. Root cause: `compiler/symtab.inc`'s `AllocParam` (shared,
target-independent!) always reserved exactly `TARGET_PTR_SIZE` bytes for
ANY record param, which happens to be 8 on x86-64/aarch64 (already enough
for any ≤8-byte record — invisible there) but only 4 on arm32/i386. Widened
the reservation to the real `RecSize` (capped at 8, floored at
`TARGET_PTR_SIZE`) for exactly this case — verified as a no-op on 64-bit
targets via self-host byte-identical (the branch computes the identical
value there), so only 32-bit targets actually change.

This also almost certainly explains why this ticket's ORIGINAL two-call
crash symptom existed at all: re-running the exact original repro
(`modPlain(p)` then `modMan(m)`) after the full fix, the crash is gone and
output matches the x86-64 oracle exactly (`1,2` then `1,orig`) — strong
retroactive confirmation that the "silently drops data + (once partially
fixed) corrupts the adjacent slot" bug was the real mechanism, not a
separate register/stack-state issue from the small-record call as
originally hypothesized in the Direction section above.

Verified against the x86-64 oracle for: a lone record arg, a record BEFORE
other scalar params, a record straddling the r0-r3/stack boundary, a record
entirely on the stack, and a record with an odd (non-power-of-2, e.g. 5 or
7 conceptual) byte size. `test/test_arm32_record_byval_wide.pas` added,
wired into both `test-arm32` and `test-aarch64` (i386 still rejects any
by-value record param outright — separate, pre-existing, unaffected). Full
`make test` + all four cross suites (i386/arm32/aarch64/riscv32) green.
