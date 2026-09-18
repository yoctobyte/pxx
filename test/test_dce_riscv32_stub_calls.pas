{ DCE MUST RE-AIM THE CODE->CODE REFERENCES THAT ARE NOT CALLS TO A PROC.

  WHAT BROKE (2026-09-18, the first target after x86-64). dce.inc refused every
  other target with `target is not x86-64`, and that one-line reason was exactly
  right about two things nobody had separated:

  1. The pass re-aimed every recorded CodeRef with
     `Patch32(pos, target - (pos + 4))` -- an x86-64 rel32 -- and on riscv32 the
     program entry jump's slot is a JAL, whose displacement is scattered across
     the instruction WORD. It wrote the new offset 32988 as a plain
     little-endian word over `5394006f`, so the program ran four instructions of
     the entry stub and fell into `c.lbu a5,1(s1)` followed by an illegal
     instruction. SIGSEGV at si_addr=0x1, before any syscall.

  2. EmitRiscv32CallToCode -- the SIGINT/SIGTERM install, the coroutine switch,
     the signal sethook, and the exception setjmp/raise/longjmp entry points,
     ten sites -- emitted its call with no CallFix and no CodeRef, on the stated
     premise that "the target is final at emit time". True of the TARGET and
     false of the SITE: DCE deletes dead bodies and every call site after a hole
     slides down. Measured: the main body's SIGINT install ran as
     `jal ra,-265220` into unmapped memory at 0x0800f588.

  Both faults are the same class as the ARM SIGILL in PatchProgramEntryJump's
  own header note -- a raw byte offset written over a branch WORD -- and the
  second is the same class as the xtensa note at symtab.inc:17878, which says
  outright that its sites "need their own fixup list" before DCE grows an arm.

  WHY THE SIZE ASSERTION IS PART OF THE TEST. Equality of output alone is
  satisfied by a pass that dropped NOTHING, which is precisely what --dce did on
  this target the day before. The row asserts the image got smaller as well as
  that it still answers.

  WHY THE EXIT STATUS IS ASSERTED. Both failures above are SIGSEGV, rc=139, and
  the first one prints nothing at all -- a row comparing only stdout reports an
  empty string against an expected one, which reads like a build problem rather
  than a crash.

  The try/except blocks are load-bearing: they are what reaches ExcSetJmpAddr,
  ExcRaiseAddr and the reg_zero ExcLongJmpAddr tail jump, three of the ten
  unrecorded sites. The bare program body reaches the other seven on its own,
  because the SIGINT/SIGTERM install is emitted unconditionally. }
program test_dce_riscv32_stub_calls;
uses sysutils;
var i, acc: Integer;
    s: AnsiString;
begin
  acc := 0;
  for i := 1 to 10 do acc := acc + i * i;
  s := '';
  for i := 1 to 3 do s := s + IntToStr(i) + ',';
  try
    raise Exception.Create('boom');
  except
    on E: Exception do s := s + E.Message;
  end;
  try
    i := 0;
    acc := acc div i;
  except
    s := s + '/div0';
  end;
  WriteLn('DCERV32 ', acc, ' ', s);
end.
