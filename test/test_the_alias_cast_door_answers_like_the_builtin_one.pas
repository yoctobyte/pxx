program test_the_alias_cast_door_answers_like_the_builtin_one;
{ `SomeName(expr)` is recognised at two doors — the USER-ALIAS table
  (FindTypeAlias) and the BUILTIN-NAME table (BuiltinScalarTypeKind) — and the
  two grew their arms independently, so the alias door was missing two the
  builtin door has. Each row casts the SAME operand to the SAME target through
  both spellings: the axis varied is WHICH DOOR RECOGNISES THE NAME, which is
  what selects the arm, and the target kind and operand are held fixed.

  fpc 3.2.2 is the oracle here and agrees row for row.

  - ENUM ALIAS: `type TE = TMyEnum; TE(1)` printed the ordinal 1 where
    `TMyEnum(1)` printed eB. The door asked `FindEnumType` about the ALIAS
    name, which is not an enum type name; the alias table's own AliasEnumId
    column is the answer and the two High/Low resolvers already read it.
  - VARIANT ALIAS: `type TV = Variant; TV(v)` on an already-variant operand
    printed 1 — the variant record's TAG word — where `Variant(v)` printed 41.
    TypeIsOrdinal answers True for tyVariant, so the ordinal arm swallowed it
    and asked VariantCastToTemp to convert a variant INTO a variant.

  The ordinal and string rows are the controls, and they are on the varied axis
  rather than in rows of their own: they were right at both doors before and
  must stay equal, so a change that broke the alias door for everything would
  show as a whole column instead of reading as a defect of the interesting row.
  refactor-p-five-dispatch-sites-for-one-named-type-cast }
type
  TMyEnum = (eA, eB, eC);
  TE2 = TMyEnum;      { enum alias }
  TV  = Variant;      { variant alias }
  TI  = ShortInt;     { ordinal alias — control }
  TS  = AnsiString;   { string alias — control }
var i: LongInt; v, w: Variant; s: AnsiString;
begin
  i := 1;
  WriteLn('enum builtin ', TMyEnum(i));
  WriteLn('enum alias   ', TE2(i));
  v := 41;
  w := Variant(v);   WriteLn('vbox builtin ', w);
  w := TV(v);        WriteLn('vbox alias   ', w);
  i := 300;
  WriteLn('ord  builtin ', ShortInt(i));
  WriteLn('ord  alias   ', TI(i));
  s := 'hi';
  WriteLn('str  builtin ', AnsiString(s));
  WriteLn('str  alias   ', TS(s));
  { and a VARIANT alias over a non-variant operand, which already worked and is
    the row that says the new box arm did not simply replace the old path }
  i := 233;
  w := TV(i);        WriteLn('vbox alias-int ', w);
end.
