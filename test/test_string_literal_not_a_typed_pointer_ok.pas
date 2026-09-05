program test_string_literal_not_a_typed_pointer_ok;
{ POSITIVE half, and it is the load-bearing one: the narrowing above must not
  eat the conversions this dialect deliberately allows. Each row is a shape a
  pointer-GENERAL refusal would have refused.

  Char -> PChar is here on purpose and not because this fix touched it: a
  pointer-general rule landed the same day, ate `Show('-')` and `p := 'e'`, and
  was reverted -- testmgr quick did not run those rows and the self-host
  fixedpoint cannot see the shape at all, because compiler.pas never binds a
  Char to a PChar. This row is where that class gets caught. }
type
  TRec = record a, b: Integer; end;
  PRec = ^TRec;
var
  r: TRec;
  pr: PRec;
  pc: PChar;
  s: string;
function TakeUntyped(q: Pointer): Integer;   begin TakeUntyped := 1; end;
function TakePChar(q: PChar): Integer;       begin TakePChar := 2; end;
function TakeRec(q: PRec): Integer;
begin
  { nil-safe on purpose: the nil row below passes nil to THIS formal, and a
    bare q^.a would segfault on a correct compiler. The row is about nil
    REACHING a typed pointer formal, not about dereferencing it. }
  if q = nil then TakeRec := -1 else TakeRec := q^.a;
end;
begin
  { the const char* marshalling the rule exists for -- must still work }
  writeln('untyped literal = ', TakeUntyped('hello'));
  writeln('pchar literal   = ', TakePChar('hello'));
  s := 'from a var';
  writeln('untyped var     = ', TakeUntyped(s));

  { Char into a PChar slot, and a one-char literal: legal, and the class a
    pointer-general refusal breaks }
  writeln('pchar from char = ', TakePChar('x'));
  pc := 'e';
  writeln('pchar assign    = ', pc);

  { a REAL typed pointer still binds to its own pointee }
  r.a := 42; r.b := 7; pr := @r;
  writeln('typed pointer   = ', TakeRec(pr));

  { nil is untyped and must reach every pointer formal }
  writeln('nil to typed    = ', TakeRec(nil));
  writeln('STRING LITERAL POINTER OK');
end.
