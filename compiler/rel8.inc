{ SPDX-License-Identifier: MPL-2.0 }
{ rel8.inc — range-checked one-byte jump displacements.

  Carved out of emit.inc so it can be TESTED. The whole point of these three
  routines is that they REFUSE an out-of-range displacement, and a refusal
  nobody has watched fire is exactly what this repo already has open examples
  of. emit.inc is 1338 lines with Procs/Syms/Strs/TargetArch behind it; a
  harness including THAT would need ~30 mocks and would rot the way
  test_asm_emit_rv32.pas did three times. This file needs five: Code, CodeLen,
  EmitB, Error, AIntToStr.

  Included from compiler.pas immediately after emit.inc — EmitRel8 calls EmitB.
  The exercising harness is test/test_rel8_guard.pas, wired into test-core.
  bug-a-a-rel8-jump-patch-truncates-silently-when-its-span-grows }

{ ---- rel8 jump displacements, RANGE-CHECKED ---------------------------------
  A one-byte jump displacement is a SIGNED int8, and every hand-rolled store of
  one truncated without a word of complaint. `Byte(181)` is stored as 181 and
  decoded as -75, so a forward jump meant to skip 181 bytes goes 75 bytes
  BACKWARDS -- into the middle of an instruction, since nothing constrains the
  landing site to an instruction boundary.

  MEASURED, not reasoned: growing EmitSyscall from 2 bytes to ~140 put
  symtab.inc:9789's `jns` 181 bytes from its target. The program faulted at
  rip=0x411115, which is mid-`add $0x80,%rsp` -- an address linear execution
  cannot produce. Scanning for a rel8 targeting it found exactly one, at
  0x41115e, displacement -75. 181-256 = -75 exactly.
  bug-a-a-rel8-jump-patch-truncates-silently-when-its-span-grows

  ERROR RATHER THAN AUTO-WIDEN, deliberately. Widening to rel32 moves every
  downstream offset, and these sites differ in whether they can absorb that --
  several are inside hand-counted sequences whose other displacements would
  need re-deriving. So the limit becomes LOUD at compile time and the emitter's
  author picks the fix. This costs nothing at runtime and cannot change a byte
  of output: an in-range displacement stores exactly what the old expression
  stored, and an out-of-range one used to produce a wrong program.

  THREE SPELLINGS OF THE SAME STORE, and that is the reason these exist as
  named helpers rather than as a review rule. The defect was filed against two
  of them (`Code[p] := Byte(...)` and `EmitB(Byte(...))`) and a census turned up
  a third: `Patch8(p, CodeLen - (p + 1))`, whose `v: Byte` parameter truncates
  at the CALL. That one is the dangerous spelling precisely because it already
  looks like a checked helper -- a fix aimed at the two `Byte(` forms would
  have left all 21 of its call sites silently truncating, and the comment
  saying "all sites converted" would have been false.
  Compare bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire:
  an invariant calibrated to a SPELLING reports clean forever. }
procedure CheckRel8(d: Integer; const what: AnsiString);
begin
  if (d < -128) or (d > 127) then
    Error('rel8 ' + what + ' displacement ' + AIntToStr(d) + ' does not fit a '
        + 'signed one-byte field (-128..127); this jump must be widened to '
        + 'rel32. An emitter between the jump and its target has grown.');
end;

{ Fill a forward rel8 placeholder emitted earlier at patchPos. The displacement
  is measured from the byte AFTER the placeholder, which is where the CPU
  measures it from. }
procedure PatchRel8(patchPos: Integer);
var d: Integer;
begin
  d := CodeLen - (patchPos + 1);
  CheckRel8(d, 'forward jump');
  Code[patchPos] := Byte(d);
end;

{ Emit the displacement byte of a BACKWARD jump to an already-known target.
  Called with CodeLen still pointing at the displacement byte itself, exactly
  as the `EmitB(Byte(target - (CodeLen + 1)))` idiom it replaces. }
procedure EmitRel8(target: Integer);
var d: Integer;
begin
  d := target - (CodeLen + 1);
  CheckRel8(d, 'back edge');
  EmitB(Byte(d));
end;
