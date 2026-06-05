program test_managed_setlength_var;

{ SetLength on a managed string passed by reference (`var`/`out`) must resize the
  CALLER's string, not a local copy. The specialId-102 SetLength codegen used to
  publish the new data pointer (and read the old one) straight into the param's
  own slot; for an IsRef param that slot holds the ADDRESS of the caller's handle,
  so the resize never reached the caller (silent no-op). The fix derefs the ref
  param at both the old-pointer read and the new-pointer publish (shrink, grow,
  and the zero-length release path). Each check prints 1 on success. }

{$define PXX_MANAGED_STRING}

procedure Shrink(var s: AnsiString);
begin
  SetLength(s, 3);
end;

procedure Grow(var s: AnsiString);
begin
  SetLength(s, 6);
end;

procedure Empty(var s: AnsiString);
begin
  SetLength(s, 0);
end;

var
  s: AnsiString;
begin
  { shrink through var: caller sees the shorter length and prefix }
  s := 'hello';
  Shrink(s);
  if Length(s) = 3 then writeln('1') else writeln('0');
  if s = 'hel' then writeln('1') else writeln('0');

  { grow through var: caller sees the longer length, prefix preserved }
  s := 'hi';
  Grow(s);
  if Length(s) = 6 then writeln('1') else writeln('0');
  if (s[1] = 'h') and (s[2] = 'i') then writeln('1') else writeln('0');

  { zero through var: caller sees the empty string }
  s := 'gone';
  Empty(s);
  if Length(s) = 0 then writeln('1') else writeln('0');

  { plain-local SetLength still works (no regression) }
  s := 'world';
  SetLength(s, 2);
  if (Length(s) = 2) and (s = 'wo') then writeln('1') else writeln('0');
end.
