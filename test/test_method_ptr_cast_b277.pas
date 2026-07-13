{ Building a CALLABLE method pointer by hand, from a TMethod record.

  A `procedure of object` value is a 16-byte {Code, Data} record, and System.TMethod is
  the same two words -- so casting one to the other is a pure REINTERPRET, not a pointer
  conversion. The alias-cast path used to wrap it in AN_PTR_CAST, which took the record's
  FIRST WORD as if it were the value and produced a method pointer whose Code was
  garbage; calling it jumped into nothing.

  This is fpcunit's TTestCase.RunBare, and it is the last link in the chain from "a name
  in the RTTI blob" to "run it":

      pMethod := Self.MethodAddress(FName);
      m.Code := pMethod;
      m.Data := Self;
      RunMethod := TRunMethod(m);
      RunMethod; }
program test_method_ptr_cast_b277;

type
  TMethod = record
    Code: Pointer;
    Data: Pointer;
  end;
  TRunMethod = procedure of object;
  TFn = function: Integer of object;

  TA = class
    n: Integer;
  published
    procedure Hello;
    function Twice: Integer;
  end;

procedure TA.Hello;
begin
  writeln('hello n=', n);
end;

function TA.Twice: Integer;
begin
  Result := n * 2;
end;

{ discover a method by name, build a callable from it, invoke it }
procedure RunNamed(a: TA; const nm: string);
var
  m: TMethod;
  run: TRunMethod;
begin
  m.Code := a.MethodAddress(nm);
  m.Data := a;
  writeln('found ', nm, ': ', m.Code <> nil);
  run := TRunMethod(m);
  run;                       { bare parenless call of the built method pointer }
end;

var
  a, b: TA;
  m: TMethod;
  run: TRunMethod;
  f: TFn;
begin
  a := TA.Create;  a.n := 7;
  b := TA.Create;  b.n := 100;

  RunNamed(a, 'Hello');

  { the Data word really is Self: the same Code, a different instance }
  m.Code := a.MethodAddress('Hello');
  m.Data := b;
  run := TRunMethod(m);
  run;

  { a FUNCTION method pointer, built the same way }
  m.Code := a.MethodAddress('Twice');
  m.Data := a;
  f := TFn(m);
  writeln('twice: ', f());
  m.Data := b;
  f := TFn(m);
  writeln('twice b: ', f());
end.
