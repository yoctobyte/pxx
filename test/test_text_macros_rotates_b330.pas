{ FPC {$MACRO ON} text macros + System bit rotates + IntN cast names (b330).

  - `{$define name := replacement}` splices the replacement wherever the bare
    identifier appears later (generics.hashes builds its Jenkins mixers this
    way). Bodies flatten to one line and the directive blanks to spaces with
    newlines kept, so line numbers downstream are unchanged. Unit-scoped, no
    parameters, no recursion — FPC's plain form.
  - RolDWord/RorDWord/RolQWord/RorQWord: System intrinsics via builtin
    soft-alias helpers (a user routine of the same name still wins).
  - Int8/Int16/Int32 as value-cast type names (UInt* variants already worked).
  Verified against FPC. }
program test_text_macros_rotates_b330;
{$mode objfpc}{$h+}
{$MACRO ON}

{$define bump :=
  a += 1;
  b += a}

var
  a: Integer = 0;
  b: Integer = 0;
begin
  bump;
  bump;
  Writeln('a=', a, ' b=', b);
  Writeln('rol=', RolDWord($80000001, 1));
  Writeln('ror=', RorDWord($80000001, 1));
  Writeln('rolq=', RolQWord(QWord($8000000000000001), 4));
  Writeln('i8=', Int8($1FF));
  Writeln('i16=', Int16($1FFFF));
  Writeln('i32=', Int32($1FFFFFFFF));
end.
