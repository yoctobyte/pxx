{ Low(x) / High(x) over an ordinal VARIABLE and over a named ARRAY TYPE.

  Before bug-a-low-high-of-an-ordinal-variable-answer-0-and-minus-1:

  - Low/High of ANY ordinal variable answered 0 and -1. Not a random pair --
    it is `Length(x) - 1` reached through the fallback at the bottom of both
    intrinsics, since a scalar has no [data-8] length header. So
    `for i := Low(x) to High(x)` ran ZERO times, silently, because 0..-1 is a
    legal empty range.
  - Low/High of a named ARRAY TYPE was `undefined variable (TA)`, so the same
    loop over a type name did not compile at all and needed a dummy variable.

  Every expected value below is fpc 3.2.2 -Mobjfpc -O1's. }
program test_low_high_of_ordinal_and_array_type;

type
  TSubInt  = 3..7;
  TSubChar = 'a'..'e';
  TEnum    = (eA, eB, eC);
  TArr     = array[5..9] of Integer;
  TArrNeg  = array[-3..3] of Byte;
  TArr2D   = array[0..2, 0..3] of Integer;
  TDyn     = array of Integer;

const
  KSpan = High(TArr) - Low(TArr) + 1;   { a const context, not just an expression }

var
  b: Byte; sb: ShortInt; w: Word; sm: SmallInt; n: Integer; q: Int64;
  ch: Char; bo: Boolean; en: TEnum; si: TSubInt; sc: TSubChar;
  a: TArr; d: TDyn;
  buf: array[Low(TArr)..High(TArr)] of Integer;   { bounds FROM the type name }
  i, trips: Integer;
  fails: Integer;

procedure Chk(const nm: string; got, want: Int64);
begin
  if got = want then WriteLn(nm, ' ok')
  else begin WriteLn(nm, ' FAIL got=', got, ' want=', want); Inc(fails); end;
end;

begin
  fails := 0;

  { ordinal VARIABLES -- every one of these answered 0 / -1 }
  Chk('byte.lo', Low(b), 0);            Chk('byte.hi', High(b), 255);
  Chk('shortint.lo', Low(sb), -128);    Chk('shortint.hi', High(sb), 127);
  Chk('word.lo', Low(w), 0);            Chk('word.hi', High(w), 65535);
  Chk('smallint.lo', Low(sm), -32768);  Chk('smallint.hi', High(sm), 32767);
  Chk('int.lo', Low(n), -2147483648);   Chk('int.hi', High(n), 2147483647);
  Chk('i64.hi', High(q), 9223372036854775807);
  Chk('char.lo', Ord(Low(ch)), 0);      Chk('char.hi', Ord(High(ch)), 255);
  Chk('bool.lo', Ord(Low(bo)), 0);      Chk('bool.hi', Ord(High(bo)), 1);
  Chk('enum.lo', Ord(Low(en)), 0);      Chk('enum.hi', Ord(High(en)), 2);

  { a named subrange variable answers ITS bounds, not the base type's -- the
    rule the type NAME already followed and the variable never reached }
  Chk('subint.lo', Low(si), 3);         Chk('subint.hi', High(si), 7);
  Chk('subchar.lo', Ord(Low(sc)), 97);  Chk('subchar.hi', Ord(High(sc)), 101);

  { the bound keeps the operand's TYPE, so it prints like fpc's: Low(Char) is
    #0 and not 0, Low(Boolean) is FALSE and not 0 }
  if Low(ch) = #0 then WriteLn('char.istype ok')
  else begin WriteLn('char.istype FAIL'); Inc(fails); end;
  if (Low(bo) = False) and (High(bo) = True) then WriteLn('bool.istype ok')
  else begin WriteLn('bool.istype FAIL'); Inc(fails); end;
  if (Low(sc) = 'a') and (High(sc) = 'e') then WriteLn('subchar.istype ok')
  else begin WriteLn('subchar.istype FAIL'); Inc(fails); end;

  { the loop the 0/-1 answer silently emptied }
  trips := 0;
  for i := Low(b) to 3 do Inc(trips);
  Chk('loop.trips', trips, 4);

  { named ARRAY TYPES -- all of these were "undefined variable" }
  Chk('arr.lo', Low(TArr), 5);          Chk('arr.hi', High(TArr), 9);
  Chk('arrneg.lo', Low(TArrNeg), -3);   Chk('arrneg.hi', High(TArrNeg), 3);
  { an N-D type reports the FIRST dimension, like fpc }
  Chk('arr2d.lo', Low(TArr2D), 0);      Chk('arr2d.hi', High(TArr2D), 2);
  { a dynamic type has Low = 0; High(TDyn) is a compile error in fpc and is
    refused here too -- there is no length until an instance exists, and
    answering would put a wrong bound in `for i := Low(T) to High(T)` }
  Chk('dyn.lo', Low(TDyn), 0);
  Chk('const.span', KSpan, 5);
  Chk('declbound.lo', Low(buf), 5);     Chk('declbound.hi', High(buf), 9);

  { the array-VARIABLE arms must not have moved }
  Chk('arrvar.lo', Low(a), 5);          Chk('arrvar.hi', High(a), 9);
  SetLength(d, 3);
  Chk('dynvar.lo', Low(d), 0);          Chk('dynvar.hi', High(d), 2);
  SetLength(d, 0);
  Chk('dynempty.hi', High(d), -1);

  for i := Low(TArr) to High(TArr) do a[i] := i;
  Chk('typeloop', a[5] + a[9], 14);

  if fails = 0 then WriteLn('ALL OK') else WriteLn('FAILURES ', fails);
end.
