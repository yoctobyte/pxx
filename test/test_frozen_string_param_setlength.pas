{ SetLength (and Length, and the data address) on a frozen inline string
  PARAMETER -- `string[N]` or `ShortString`, whose slot holds a POINTER to the
  buffer rather than the buffer itself.

  Four helpers in symtab.inc (EmitStoreStrLen, EmitLoadStrLen,
  EmitLeaStrDataRdi, EmitLeaStrDataRsi) asked "is this a frozen-string param?"
  as `TypeKind = tyString` -- the LEGACY overloaded kind. A `string[20]` is
  tyFixedString and a ShortString is tyShortString, so all four fell into the
  else branch and addressed the slot as if the buffer were inline. SetLength
  then wrote the new length OVER the parameter slot, destroying the pointer, and
  the next Length() dereferenced 3. SIGSEGV on x86-64.

  aarch64 had the mirror-image bug at its own -101 arm: it tested `not IsArray`
  where the real question is `not IsRef`, because EmitLoadVarAddrA64 has already
  dereferenced a by-ref param -- so `var s: string[20]` was dereferenced twice.

  i386 and arm32 were correct throughout, which is what made this findable: four
  backends, two of them right. A LOCAL frozen string is correct everywhere, so
  only the parameter arms were narrow.

  And i386 REFUSED the by-value half outright -- "only ordinal/pointer
  parameters supported yet" -- from a third copy of the same narrow test, an
  explicit `in [tyString, ...]` set in the i386 prologue that listed the legacy
  kind and not the other two. It reads like a target limitation and was not one.

  Both directions are here because they fail in opposite places: by-VALUE broke
  on x86-64 and was refused on i386, by-REF broke on aarch64, and a test with
  only one of them passes on one of the broken targets.

  riscv32 and xtensa cannot run this at all -- SetLength (builtin 101) is not
  implemented in their bare-metal stage 1. That is an honest refusal at compile
  time, not a wrong value, and is unrelated. }
program test_frozen_string_param_setlength;
{$mode objfpc}{$H+}
type TS = string[20];

procedure ByVal(s: TS);
begin
  SetLength(s, 3);
  WriteLn('byval  len=', Length(s), ' [', s, ']');
end;

procedure ByRef(var s: TS);
begin
  SetLength(s, 3);
  WriteLn('byref  len=', Length(s), ' [', s, ']');
end;

procedure ShortByRef(var s: ShortString);
begin
  SetLength(s, 3);
  WriteLn('short  len=', Length(s), ' [', s, ']');
end;

procedure ReadsOnly(const s: TS);
begin
  WriteLn('const  len=', Length(s), ' [', s, '] first=', s[1]);
end;

{ The shapes a real caller actually writes, and on i386 they were unreachable
  until the prologue stopped refusing a by-value frozen-string param: copy to a
  frozen local, cross-assign to a managed string, compare, concatenate, and
  forward to a second routine. Widening the prologue is what made these
  compile, so they are the population that widening has to be right for. }
procedure Uses_(s: TS);
var loc: TS; a: AnsiString;
begin
  loc := s;
  a := s;
  WriteLn('uses   copy=[', loc, '] ansi=[', a, '] eq=', s = loc, ' cat=[', s + '!', ']');
end;

procedure Forwards(s: TS);
begin
  Uses_(s);
end;

var t: TS; u: ShortString; L: TS;
begin
  L := 'abcdef'; SetLength(L, 3);
  WriteLn('local  len=', Length(L), ' [', L, ']');     { correct on every target, before and after }
  t := 'abcdef'; ByVal(t);
  WriteLn('caller after byval: [', t, ']');            { by VALUE: the caller must be untouched }
  t := 'abcdef'; ByRef(t);
  WriteLn('caller after byref: [', t, ']');            { by REF: the caller must see the truncation }
  u := 'abcdef'; ShortByRef(u);
  t := 'wxyz';   ReadsOnly(t);
  t := 'hey';    Uses_(t);
  t := 'hey';    Forwards(t);
end.
