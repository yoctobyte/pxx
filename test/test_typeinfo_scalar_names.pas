program test_typeinfo_scalar_names;
{ TypeInfo(T) must report the type the caller NAMED.

  `byte` and `integer` lex as the SAME token (tkInteger_T — lexer.inc has one
  token with two spellings), and this path switched on the token kind, so
  TypeInfo(Byte) answered kind=tkInteger named "Integer" while the identical
  TypeInfo(UInt8) — an ordinary identifier, resolved by name — correctly
  answered "Byte". FPC says Byte. Both rows are here for exactly that reason:
  the pair is what makes the bug visible, since either alone looks fine.

  The type system was never confused — SizeOf(Byte) has always been 1. Only
  the reported NAME was wrong, which is the kind of defect that survives
  because everything built on it still works.

  Every kind and name below was checked against FPC 3.2.2 with the same
  program. Two deliberate dialect differences, NOT bugs and NOT asserted as
  FPC parity:
    * Integer reports "Integer"; FPC says "LongInt" (Integer is an alias for
      LongInt there).
    * Real reports the type it resolves to — "Double" here — where FPC reports
      the name "Real", because FPC gives the alias its own RTTI entry and we
      report the underlying type. The KIND (4, tkFloat) agrees.
      The row is target-dependent by design: `Real` is the target's native
      float depth, so it reports "Single" on xtensa and riscv32
      (docs/language/types.md). It is here so that the third copy of that
      rule — the TypeInfo token-kind arm — cannot drift back to a hard-wired
      Double the way BuiltinTypeNameTk did
      (bug-a-sizeof-real-disagrees-with-the-storage-real-actually-gets).
  feature-typeinfo-all-types }

uses typinfo;

var
  p: PTypeInfo;

procedure S(const w: string; q: Pointer);
begin
  p := PTypeInfo(q);
  WriteLn(w, ' ', p^.Kind, ' ', p^.NamePtr^);
end;

begin
  S('Byte', TypeInfo(Byte));         { the bug: was 1 Integer }
  S('UInt8', TypeInfo(UInt8));       { its twin, always correct — the control }
  S('Integer', TypeInfo(Integer));
  S('Word', TypeInfo(Word));
  S('LongWord', TypeInfo(LongWord));
  S('Int64', TypeInfo(Int64));
  S('Char', TypeInfo(Char));
  S('Boolean', TypeInfo(Boolean));
  S('Double', TypeInfo(Double));
  S('Single', TypeInfo(Single));
  S('Real', TypeInfo(Real));         { the target's native float depth }
  S('string', TypeInfo(string));
end.
