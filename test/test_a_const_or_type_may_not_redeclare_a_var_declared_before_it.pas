{ The reverse order of test_a_var_may_not_redeclare_any_name_of_its_own_scope:
  a const or a type declared AFTER a var, string const or set const of the same
  name, in the same scope. fpc refuses every one. pxx accepted them and the
  later declaration won, so the earlier var read as something else. All seven
  are reported from one compile, each ONCE (the case-only check would have
  reported the typed const and `vv` a second time without the rename).
  bug-p-a-const-or-type-may-redeclare-a-var-declared-before-it }
program test_a_const_or_type_may_not_redeclare_a_var_declared_before_it;
{$mode objfpc}
var
  tel: AnsiString;
  cnt: Integer;
  vv: Integer;
  x: Integer;
const
  TEL = 'telegram';        { 1: a string const after a var, other spelling }
  cnt = 3;                 { 2: an ordinal const after a var }
  VV: Integer = 4;         { 3: a typed const after a var, other spelling }
  Banner = 'a';
  Banner = 'b';            { 4: a string const twice }
  Digits = ['0'..'9'];
type
  Digits = Integer;        { 5: a type after a set const }
  X = Integer;             { 6: a type after a var, other spelling }

procedure P;
var loc: Integer;
const LOC = 5;             { 7: the same inside a routine }
begin
  loc := 0;
end;

begin
  P;
end.
