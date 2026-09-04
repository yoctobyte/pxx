program test_tmethod_record_roundtrip;
{ System.TMethod: the record that names the two halves a `procedure of object`
  value already IS. FPC/Delphi declare it in `system`, so this program has no
  `uses` on purpose -- needing one would be the bug.

  What is asserted, in the order real code does it: take a live method pointer
  apart, read Self back out of Data, rebuild a callable value from the two words
  and CALL THROUGH IT, compare two handlers for identity, and detach one.

  The size row asserts a RELATION (`SizeOf(TMethod) = 2 * SizeOf(Pointer)`) and
  never a constant. A method pointer is two pointers, so it is 16 bytes on
  x86-64/aarch64 and 8 on i386/arm32/riscv32/xtensa; every gate here runs on the
  64-bit host, where a hard-coded 16 is right for the wrong reason. That is
  exactly bug-a-method-pointer-record-is-hard-sized-16-bytes-on-32-bit-targets,
  and a relation carries no expected width, so this row prints a different
  correct number on each target and still passes.

  Oracle: fpc 3.2.2 -Mdelphi -O1, byte-identical output.
  feature-p-tmethod-record-for-method-pointers }
{$mode delphi}
type
  TSel = procedure of object;
  TSvc = class
    procedure Pick;
    procedure Other;
  end;
procedure TSvc.Pick;  begin writeln('picked'); end;
procedure TSvc.Other; begin writeln('other'); end;
var s: TSvc; e1, e2, e3: TSel; m: TMethod;
begin
  s := TSvc.Create;
  e1 := s.Pick;
  e3 := s.Other;

  { apart }
  m := TMethod(e1);
  writeln('data-is-self ', Ord(m.Data = Pointer(s)));
  writeln('code-nonnil  ', Ord(m.Code <> nil));

  { rebuilt from the two words, then CALLED -- not merely asserted non-nil }
  e2 := TSel(m);
  e2();

  { two handlers compared, the way an event list looks for one to detach }
  writeln('e1=e2 ', Ord(TMethod(e1).Code = TMethod(e2).Code));
  writeln('e1=e3 ', Ord(TMethod(e1).Code = TMethod(e3).Code));

  { detach }
  m.Code := nil; m.Data := nil;
  e3 := TSel(m);
  writeln('detached ', Ord(TMethod(e3).Code = nil));

  { a RELATION, never a per-target constant }
  writeln('rel ', Ord(SizeOf(TMethod) = 2 * SizeOf(Pointer)));
end.
