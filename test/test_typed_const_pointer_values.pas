{ Typed constants whose slot is a POINTER, and the named-array-type alias that
  has to carry the pointee kind for any of it to work.

  Two defects, one family, both measured against fpc 3.2.2:

  1. `const GP: PChar = '-'` fell through to ConstEval, where a ONE-character
     literal is a perfectly good ordinal and an ordinal is a perfectly good
     initialiser for a pointer-sized slot. It compiled, and the program then
     dereferenced address 45. Two characters had no ordinal, so `'konst'`
     refused instead — loudly, and with an unrelated message. The array form
     said `too many array constant elements`, because the short element folded
     and the long one did not consume its token at all.

  2. A NAMED array type of pointers (`TAp = array[0..2] of PChar`) dropped the
     pointee's TYPE KIND at alias-definition time — the pointee RECORD id had
     been given a slot years earlier, the kind never was — so every use read
     whatever the last unrelated pointer declaration anywhere in the unit had
     left in the global. `a[0] := 'hey'; WriteLn(a[0])` printed 4304310.
     That one is not about constants at all; the const rows above merely could
     not work until it was fixed.

  The `junk`/`PR` pair below is load-bearing: it is the unrelated pointer
  declaration whose pointee leaked into the alias. Without it the alias rows
  can pass by accident.

  bug-p-typed-constants-cannot-hold-a-pointer-a-nested-aggregate-or-storage }
program test_typed_const_pointer_values;

type
  PR  = ^Integer;                        { the leak source — do not remove }
  TRw = record nm: PChar; c: Char; n: Integer; end;
  TAp = array[0..2] of PChar;

const
  GP : PChar = '-';                      { one char: used to compile and segfault }
  KC : PChar = 'konst';                  { many chars: used to be a parse error }
  AP : array[0..1] of PChar = ('-', '--');
  NA : TAp = ('n0', 'n1', 'x');          { through a named alias }
  RW : TRw = (nm: 'field'; c: 'Z'; n: 5);
  KT : array[1..2] of TRw = ((nm: 'a'; c: 'p'; n: 1), (nm: 'bb'; c: 'q'; n: 2));
  NP : Pointer = nil;                    { the ordinal path must not move }

var
  junk: PR;
  va: TAp;

procedure Loc;
const
  LP: PChar = 'local';
  LC: Char  = 'y';                       { a one-char literal in a CHAR slot is
                                           still an ordinal — the destination
                                           decides, not the token }
begin
  WriteLn('loc     : ', LP, ' ', LC);
end;

begin
  junk := nil;
  WriteLn('scalar  : ', GP, ' ', KC);
  WriteLn('array   : ', AP[0], ' ', AP[1]);
  WriteLn('alias   : ', NA[0], ' ', NA[1], ' ', NA[2]);
  WriteLn('record  : ', RW.nm, ' ', RW.c, ' ', RW.n);
  WriteLn('arr/rec : ', KT[1].nm, ' ', KT[1].c, ' ', KT[2].nm, ' ', KT[2].n);
  if NP = nil then WriteLn('nilptr  : ok');
  Loc;
  va[0] := 'hey'; va[1] := 'you'; va[2] := 'now';
  WriteLn('var alia: ', va[0], ' ', va[1], ' ', va[2]);
end.
