program test_cast_to_array_type;
{$mode objfpc}{$H+}
{ `TArr(aa)[1]` -- a value cast to a NAMED ARRAY TYPE.

  Arrays were the ONLY type kind with no cast at all. Record, string alias,
  pointer alias, class, integer alias, enum, set and procedural all worked; all
  three array flavours answered `undefined variable (TArr)`, because the NAME
  never resolved -- so this was never a postfix bug despite being found while
  tabulating postfix chains.

  Implemented by MINTING an implicit `^TArr` alias (EnsureArrayPtrAlias) and
  reusing the pointer-alias path, because FPC's value cast to an array type IS
  the in-place reinterpret `PArr(@aa)^` already spells. From the cast node
  onward this is byte-for-byte what the PArr spelling produces, which is why it
  adds no sixth postfix walker.

  Rows that can actually FAIL, and what each one guards:

  * `wrote=` is the load-bearing row. A reinterpret must hit the ORIGINAL
    storage, so a materialising implementation prints 30 here, not 42, while
    every read-only row above it still passes.
  * `lo=` over `array[2..4]` caught a PRE-EXISTING bug in the path this
    delegates to: the pointer-alias cast's private postfix loop knew the element
    KIND but not the pointee's low BOUND, so `PLo(@lo)^[3]` answered 0 against
    fpc's 99 -- silently, and only for an INLINE cast, since the same line
    through a pointer VARIABLE goes through the shared loop and was always
    right. Fixed by asking the shared DerefPtrArrayInfo here too.
  * `char=` guards the sibling defect fixed in 5c26f7a46; a Char element is the
    one kind that took the -2 PChar adapter and lost its array row.
  * `nd=` guards the N-D exclusion on that new fold: BuildFlatNDIndex already
    subtracts every dimension's low bound, so folding again would index
    (i - 2*lo0) -- correct only for the lo=0 case that hides it.
  * `same=` is the extent boundary this ticket's gate asks about: a cast to a
    DIFFERENT named type of the same shape. FPC allows it; so do we.
  * `rec=`/`stra=` are the neighbouring cast kinds, here so a change to the
    cast dispatch cannot fix arrays by breaking them.

  .expected IS fpc 3.2.2's own output on this source.
  bug-p-a-cast-to-an-array-type-is-not-recognised }
type
  TRek = record a: Integer; end;
  TStrA = AnsiString;
  TArr = array[0..3] of Integer;   PArr2 = ^TArr;
  TCharA = array[0..3] of Char;
  TDyn = array of Integer;
  TLo = array[2..4] of Integer;
  TSame = array[0..3] of Integer;
  TND = array[0..1, 0..1] of Integer;
var
  r: TRek; ss: TStrA; aa: TArr; ca: TCharA; dy: TDyn; lo: TLo; nd: TND;
  n: Integer;
begin
  r.a := 7; ss := 'xy';
  aa[0]:=0; aa[1]:=10; aa[2]:=20; aa[3]:=30;
  ca[1]:='b'; lo[3]:=99;
  SetLength(dy,4); dy[1]:=77;
  nd[1,1] := 55;
  WriteLn('rec  =', TRek(r).a);
  WriteLn('stra =', TStrA(ss)[1]);
  WriteLn('arr  =', TArr(aa)[1]);
  WriteLn('char =', TCharA(ca)[1]);
  WriteLn('dyn  =', TDyn(dy)[1]);
  WriteLn('lo   =', TLo(lo)[3]);
  WriteLn('nd   =', TND(nd)[1,1]);
  { same-extent reinterpret of a DIFFERENT named type -- FPC allows it }
  WriteLn('same =', TSame(aa)[2]);
  { WRITE through the cast: it is an in-place reinterpret, so this must hit aa }
  TArr(aa)[3] := 42;
  WriteLn('wrote=', aa[3]);
  { in the four syntactic contexts the ticket names }
  n := TArr(aa)[1];             WriteLn('rhs  =', n);
  WriteLn('paren=', (TArr(aa)[1]));
  WriteLn('arg  =', Abs(TArr(aa)[1]));
  if (TArr(aa)[1] > 0) and (TArr(aa)[2] > 0) then WriteLn('and  =ok');
end.
