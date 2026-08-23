program test_pchar_from_a_string_literal;
{ `p := 'literal'` where p is a PChar, and the comparison that goes with it.

  Three defects, all silent, all pre-existing (they reproduce with the pinned
  binary):

  1. The assignment stored the literal's HANDLE, which points at the 8-byte
     Pascal length prefix -- so `WriteLn(p)` printed nothing (char 0 is the
     prefix's low byte, then a NUL) and `Length(AnsiString(p))` answered 1.
     The call-ARGUMENT path already applied the +8 skip, which is why
     `Show('lit')` printed the text and `p := 'lit'; Show(p)` did not: one
     marshalling rule, applied at one of its two boundaries. The idiom is
     everywhere in C bindings.

  2. A ONE-CHARACTER literal is an AN_INT_LIT tagged tyChar, not a string node,
     so `p := 'e'` stored the ordinal 101 into the pointer and the next
     `WriteLn(p)` dereferenced address 101 and SEGFAULTED.

  3. `p = 'alpha'` compared the two POINTERS. It answered True only when p had
     been assigned that very literal and so held the same data-section handle;
     the same text built at run time answered False. Fixing (1) removed the
     coincidence and made the defect visible, which is the honest order to
     find it in.

  bug-p-a-string-literal-assigned-to-a-pchar-is-empty

  Every row below is byte-identical to fpc 3.2.2 -Mobjfpc -O1, on x86-64, i386,
  aarch64, arm32 and riscv32. }
type
  TRec = record f: PChar; end;
var
  fails: Integer;
  p: PChar;
  r: TRec;
  arr: array[0..1] of PChar;
  dyn: array of PChar;
  s: AnsiString;

procedure ChkS(const what, got, want: AnsiString);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got [', got, '] want [', want, ']');
    fails := fails + 1;
  end;
end;

procedure ChkI(const what: AnsiString; got, want: Int64);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got ', got, ' want ', want);
    fails := fails + 1;
  end;
end;

procedure Show(q: PChar);
begin
  { the ARGUMENT boundary, which was always right -- here so a change to the
    shared marshalling rule cannot fix one side and break the other }
  ChkS('literal as an argument', AnsiString(q), 'litarg');
end;

begin
  fails := 0;

  p := 'alpha';
  ChkS('assign to a PChar var', AnsiString(p), 'alpha');
  ChkI('and its length', Length(AnsiString(p)), 5);
  ChkS('and it indexes', p[1], 'l');

  r.f := 'beta';
  ChkS('assign to a PChar field', AnsiString(r.f), 'beta');

  arr[1] := 'gamma';
  ChkS('assign to a static array element', AnsiString(arr[1]), 'gamma');

  SetLength(dyn, 1);
  dyn[0] := 'delta';
  ChkS('assign to a dynamic array element', AnsiString(dyn[0]), 'delta');

  Show('litarg');

  { the one-character literal, which used to segfault on the next read }
  p := 'e';
  ChkS('one-char literal', AnsiString(p), 'e');
  ChkI('one-char length', Length(AnsiString(p)), 1);

  { and the empty one }
  p := '';
  ChkS('empty literal', AnsiString(p), '');
  ChkI('empty length', Length(AnsiString(p)), 0);

  { comparison is by CONTENT, both when the pointer happens to hold the very
    literal it is compared against and when it does not }
  p := 'alpha';
  if not (p = 'alpha') then
  begin writeln('FAIL literal-assigned PChar = same literal'); fails := fails + 1; end;
  if p <> 'alpha' then
  begin writeln('FAIL literal-assigned PChar <> same literal'); fails := fails + 1; end;
  if p = 'beta' then
  begin writeln('FAIL PChar = a different literal'); fails := fails + 1; end;

  s := 'alp';
  s := s + 'ha';          { same text, built at run time: a DIFFERENT pointer }
  p := PChar(s);
  if not (p = 'alpha') then
  begin writeln('FAIL runtime-built PChar = literal'); fails := fails + 1; end;
  if p = 'alphb' then
  begin writeln('FAIL runtime-built PChar = a different literal'); fails := fails + 1; end;

  { concat, the sibling context of the comparison }
  ChkS('literal + PChar', 'x' + AnsiString(p), 'xalpha');

  if fails = 0 then writeln('ALL OK') else writeln(fails, ' FAILURES');
end.
