{ Frozen inline strings (string[N] = tyFixedString) on the CROSS backends.

  The string model grew tyFixedString / tyShortString beside the legacy tyString, and
  TypeIsFrozenString exists precisely so codegen can ask "is this an inline [len:8][chars]
  string?" instead of testing `= tyString`. x86-64 was widened to the predicate; aarch64,
  arm32 and i386 were NOT, in four separate dispatches -- so on those targets a string[N]:

    - stored its own ADDRESS into the buffer instead of copying [len][chars],
    - reported Length() = 0 (the frozen branch missed, so it read a dynarray count at
      [handle-8]),
    - and, passed to a MANAGED string parameter, handed over the raw buffer address as if
      it were a heap handle -- the callee then read the 8 bytes BEFORE the buffer as a
      length. That is what segfaulted test_lfm on aarch64: TypInfo's GetEnumValue does
      CompareText(sp^, name) where sp^ is an interned enum-member name inside an RTTI blob.

  Every one of these was SILENT on the target and invisible on x86-64. Run this on every
  backend, not just the host. }
program test_frozen_string_cross_b305;

type
  TF = string[255];
  PF = ^TF;

function ByValue(const s: string): Integer;   { a MANAGED string parameter }
begin
  ByValue := Length(s);
end;

function FirstChar(const s: string): Char;
begin
  if Length(s) = 0 then FirstChar := '?' else FirstChar := s[1];
end;

var
  f: TF;
  pf: PF;
  m: string;
begin
  f := 'hello';
  pf := @f;

  { store + the inline length prefix }
  writeln('len=', Length(f));
  writeln('f=', f);

  { frozen -> managed assignment }
  m := f;
  writeln('assigned=', m, ' len=', Length(m));

  { frozen variable passed to a managed parameter }
  writeln('byvalue=', ByValue(f));
  writeln('first=', FirstChar(f));

  { frozen reached through a pointer deref, both as a value and as an argument }
  m := pf^;
  writeln('deref=', m);
  writeln('deref-arg=', ByValue(pf^));

  { reassignment must not leak the old length }
  f := 'hi';
  writeln('re-len=', Length(f), ' re=', f, ' re-arg=', ByValue(f));
end.
