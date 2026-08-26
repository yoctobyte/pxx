{ `<BuiltinType>(target) := value` as a statement, for EVERY spelling of a
  builtin type name.

  Only four names worked: Integer, LongWord, Char and Boolean -- which is to say,
  exactly the four that lex as KEYWORD tokens and therefore reached the
  cast-as-lvalue arm. `Pointer`, `PtrUInt`, `Int64`, `AnsiString` and the rest
  lex as identifiers, were looked up as VARIABLES, and answered
  `undefined variable (Pointer)` -- for a line whose rvalue twin `a := Pointer(b)`
  compiles two lines up.

  `string(p^) := v` was worse than either: it did not fail at all. It parsed as
  something else and SILENTLY WROTE NOTHING, which is how fgl's string list read
  back empty and its string map raised EListError on a key it thought it had
  stored.

  This is the third time this shape has been fixed here one name at a time -- the
  builtin POINTER names (PInteger and friends) got their own fallback earlier,
  and the expression site got one before that. So the fix is one shared body
  (ParseCastAsLValueStore) reached through one lookup (BuiltinTypeNameTk, the
  same function the expression side uses), not a fourth list of names.

  Every row measured against fpc 3.2.2 (-Mobjfpc -O1). }
program test_cast_as_lvalue_builtin_names;
{$mode objfpc}
type PStr = ^string;
var
  a, b, p: Pointer;
  i: Integer; i64: Int64; pu: PtrUInt;
  s, v: string; ps: PStr;
  blk: Pointer;
begin
  { the keyword-token names, which always worked -- pinned because the body they
    run moved out from under them }
  blk := GetMem(64); FillChar(blk^, 64, 0);
  p := blk;
  Integer(p^) := 1234;          WriteLn('Integer   ', Integer(p^));
  LongWord(p^) := 4000000000;   WriteLn('LongWord  ', LongWord(p^));
  Char(p^) := 'z';              WriteLn('Char      ', Char(p^));
  Boolean(p^) := True;          WriteLn('Boolean   ', Boolean(p^));

  { ...and the identifier-spelled ones, which did not }
  FillChar(blk^, 64, 0);
  Int64(p^) := 5000000000;      WriteLn('Int64     ', Int64(p^));
  PtrUInt(p^) := 987654321;     WriteLn('PtrUInt   ', PtrUInt(p^));

  { a genuine pointer store through the cast, which is fgl's own line }
  i := 5; b := @i; a := nil; p := @a;
  Pointer(p^) := b;
  WriteLn('Pointer   ', Assigned(a), ' ', Integer(a^));

  { the string forms: these were ACCEPTED and wrote nothing }
  FillChar(blk^, 64, 0);
  p := blk;
  v := 'alpha';
  string(p^) := v;
  WriteLn('string    [', string(p^), '] ', Length(string(p^)));
  v := 'beta-longer';
  string(p^) := v;
  WriteLn('rewrite   [', string(p^), '] ', Length(string(p^)));
  ps := PStr(blk);
  WriteLn('typed ptr [', ps^, ']');

  FillChar(blk^, 64, 0);
  AnsiString(p^) := 'gamma';
  WriteLn('AnsiString[', AnsiString(p^), ']');

  { the rvalue twin still reads the same value -- the two spellings agreeing is
    the whole point }
  s := 'roundtrip'; p := @s;
  WriteLn('rvalue    [', string(p^), ']');
end.
