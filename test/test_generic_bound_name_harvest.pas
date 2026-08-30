{ regression-test-pascal-conformance-shard0-6-2

  The specialization pre-pass harvests "bound names" -- the parameter names of a
  generic DECLARATION -- so it can avoid rewriting a later occurrence of one of
  them into a concrete specialization. It harvested from a `Name<...>` group
  followed by `=` without first checking that the group was a declaration's
  left-hand side, so a typed const whose group is also followed by `=` donated
  its ARGUMENTS to the bound-name set. Every later use of that name was then
  treated as a template parameter and left unspecialized.

  WHY THIS FILE IS SPELLED THE WAY IT IS. The harvest records a name only when
  the lexer gives it kind tkIdent. The lexer hands exactly ten spellings a
  dedicated token kind -- boolean, byte, char, double, extended, integer,
  longword, real, single, string (ten spellings over nine kinds; `byte` shares
  tkInteger_T with `integer`) -- and those are structurally unable to enter the
  set. Every other type name, including all of the width-specific integers and
  any user alias, stays tkIdent and is harvestable.

  So the failing set and the passing set are two disjoint lists of NAMES, and a
  test that reaches for the idiomatic `Integer` passes over a live defect. This
  file gates on the failing set: LongInt, Cardinal, Int64, QWord, SmallInt,
  Word, ShortInt and a user alias, with Integer and Char alongside as the
  controls that were never at risk.

  WHAT THIS FILE ALONE DOES NOT SHOW. Run against the pre-fix compiler it stops
  at the FIRST typed const, line 41, so it demonstrates LongInt and merely
  asserts the other seven. The per-name split was measured separately, one name
  per program, baseline a60f92ba830a vs fixed 22c67e5ea61e:

    fail before / ok after : LongInt Cardinal Int64 QWord SmallInt Word
                             ShortInt TMyAlias        (8 of 8)
    ok before  / ok after  : Integer Char Byte LongWord Boolean Double Single
                             (7 of 7 -- the dedicated-kind spellings)

  Forward protection is still per-name: any one of the eight regressing on its
  own makes this file fail.

  Oracle: FPC prints the same line. }
program test_generic_bound_name_harvest;

{$MODE OBJFPC}

type
  TMyAlias = LongInt;

  generic TCell<T> = record
    V: T;
  end;

const
  { The trap itself: each of these is a typed const whose specialization group
    is followed by `=`. Before the fix each one donated its argument name to the
    bound-name set, and the width-specific spellings then stopped resolving. }
  CLongInt:  ^specialize TCell<LongInt>  = Nil;
  CCardinal: ^specialize TCell<Cardinal> = Nil;
  CInt64:    ^specialize TCell<Int64>    = Nil;
  CQWord:    ^specialize TCell<QWord>    = Nil;
  CSmallInt: ^specialize TCell<SmallInt> = Nil;
  CWord:     ^specialize TCell<Word>     = Nil;
  CShortInt: ^specialize TCell<ShortInt> = Nil;
  CAlias:    ^specialize TCell<TMyAlias> = Nil;
  { Controls: dedicated token kinds, structurally unharvestable. }
  CInteger:  ^specialize TCell<Integer>  = Nil;
  CChar:     ^specialize TCell<Char>     = Nil;

var
  { The same names again as ordinary variables, which is where a suppressed
    rewrite surfaces as `unknown type` rather than as a silent wrong value. }
  vLongInt:  specialize TCell<LongInt>;
  vCardinal: specialize TCell<Cardinal>;
  vInt64:    specialize TCell<Int64>;
  vQWord:    specialize TCell<QWord>;
  vSmallInt: specialize TCell<SmallInt>;
  vWord:     specialize TCell<Word>;
  vShortInt: specialize TCell<ShortInt>;
  vAlias:    specialize TCell<TMyAlias>;
  vInteger:  specialize TCell<Integer>;
  vChar:     specialize TCell<Char>;
  n: LongInt;

begin
  vLongInt.V  := 1;
  vCardinal.V := 2;
  vInt64.V    := 3;
  vQWord.V    := 4;
  vSmallInt.V := 5;
  vWord.V     := 6;
  vShortInt.V := 7;
  vAlias.V    := 8;
  vInteger.V  := 9;
  vChar.V     := 'A';

  n := vLongInt.V + vCardinal.V + vInt64.V + LongInt(vQWord.V)
     + vSmallInt.V + vWord.V + vShortInt.V + vAlias.V + vInteger.V;

  writeln('boundharvest ', n, ' ', vChar.V, ' ',
          Ord(CLongInt = Nil), Ord(CCardinal = Nil), Ord(CInt64 = Nil),
          Ord(CQWord = Nil), Ord(CSmallInt = Nil), Ord(CWord = Nil),
          Ord(CShortInt = Nil), Ord(CAlias = Nil), Ord(CInteger = Nil),
          Ord(CChar = Nil));
end.
