program test_a_a_compiler_internal_record_name_is_an_ordinary_user_name;
{ TToken, TParam, TProc, TSymbol and ten more are the compiler's OWN record
  names, with builtin ids so compiler.pas keeps them across the self-host. A
  user program saw them too: `PToken = ^TToken` ahead of the user's own TToken
  bound the pointer to the compiler's record ("no such member" on p^.kind), and
  an undeclared `TParam` was a silent 40-byte record. Every line matches fpc
  3.2.2. bug-a-fourteen-compiler-internal-record-names-are-reserved-in-every-user-program }
{$mode objfpc}
type
  PToken = ^TToken;
  TToken = record kind: Byte; end;
  PParam = ^TParam;
  TParam = record name: string[7]; value: Int64; end;
  TProc = object a, b: Integer; end;
var t: TToken; p: PToken; q: PParam; r: TParam; x: TProc;
begin
  t.kind := 7; p := @t; WriteLn(p^.kind, ' ', SizeOf(TToken), ' ', SizeOf(p^));
  r.name := 'width'; r.value := 640; q := @r; WriteLn(q^.name, '=', q^.value, ' ', SizeOf(TParam));
  x.a := 1; x.b := 2; WriteLn(SizeOf(x), ' ', x.a + x.b);
end.
