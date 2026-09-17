{ A typecast to an ENUM type in a CONSTANT expression.

  pxx has no tyEnum -- an enum's values travel in an ordinary integer kind with
  the identity carried beside them -- so TypeIsOrdinal has no enum family and
  the const-cast door's alias arm could not answer for one however the enum was
  declared. `const K = TE(2)` was refused as `not a constant`.

  THE ALIAS-BEFORE-BUILTIN CONTROLS ARE NOT DECORATION AND ARE DELIBERATELY NOT
  LAST. This file touches ConstCastWidth, which exists to own the ORDER in which
  a cast name is resolved -- a source declaration outranks a builtin, and
  symtab.inc records that inverting it breaks the compiler outright. A third arm
  inserted in the wrong place would still make every enum row below pass. The
  two control rows are what fail in that case, so they sit in the middle where a
  reader cannot skip them and a truncated run cannot certify them by not
  reaching them.

  Every row's value is fpc 3.2.2's own answer, checked row by row.
  bug-p-an-enum-typecast-is-not-a-constant-expression }
program test_const_enum_cast;

type
  { the plain case: nothing unusual about the declaration at all }
  TE = (eA, eB, eC);

  { fpc's cgbase.pas:401 shape. The explicit bounds make the enum 4 bytes SIGNED
    and incompatible with a neighbouring type -- fpc's own comment says that is
    why it is written this way. $ffffffff must therefore fold to -1, not to
    4294967295, which is the row that proves the width came from
    EnumStorageTypeKind and not from a default. }
  TRegister = (TRegisterLowEnum := Low(LongInt), TRegisterHighEnum := High(LongInt));

  MyInt64 = Int64;

const
  K_PLAIN   = TE(2);
  K_ZERO    = TE(0);
  K_REG     = TRegister($ffffffff);
  K_REG_POS = TRegister(7);

  { CONTROL, and see the header: a user alias must outrank the builtin table. }
  K_ALIAS   = MyInt64(4294967301);

  { CONTROL, the other direction: a BUILTIN name with no alias shadowing it
    keeps the builtin's 4-byte width, so the high half is discarded. }
  K_BUILTIN = LongInt(4294967296 + 5);

  { back to enums, AFTER the controls, so the controls are never the tail }
  K_ORD     = Ord(TE(2));

var
  T: TE;
begin
  WriteLn('K_PLAIN   = ', Ord(K_PLAIN));
  WriteLn('K_ZERO    = ', Ord(K_ZERO));
  WriteLn('K_REG     = ', Ord(K_REG));
  WriteLn('K_REG_POS = ', Ord(K_REG_POS));
  WriteLn('K_ALIAS   = ', K_ALIAS);
  WriteLn('K_BUILTIN = ', K_BUILTIN);
  WriteLn('K_ORD     = ', K_ORD);

  { the folded constant is still an enum VALUE, not a loose integer: it assigns
    to a variable of the enum type without a cast }
  T := K_PLAIN;
  WriteLn('assigned  = ', Ord(T));

  { THE SECOND SPELLING, and it is the reason these rows are in this file and
    not a separate one. `case` labels are parsed by their own narrow grammar
    that does not call the const-declaration evaluator -- its own comment says
    so -- so fixing the cast in a `const` left `case e of TE(1)` still refused:
    one construct, two places the language lets you write it, one of them fixed.
    Found by varying the SPELLING rather than the feature. A single-arm fix
    passes every row above this line. }
  T := eB;
  case T of
    TE(1): WriteLn('case cast = hit');
  else
    WriteLn('case cast = MISS');
  end;

  { ...and the RANGE form of the same label, which is a third grammar position }
  case T of
    TE(0)..TE(1): WriteLn('case range= hit');
  else
    WriteLn('case range= MISS');
  end;

  { CONTROL: a bare enum member must still work as a label, and a non-constant
    must still be refused -- the latter is asserted in the Makefile, not here,
    since a refusal cannot be a row in a program that must run. }
  case T of
    eB: WriteLn('bare memb = hit');
  else
    WriteLn('bare memb = MISS');
  end;
end.
