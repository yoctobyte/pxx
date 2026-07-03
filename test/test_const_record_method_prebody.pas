program test_const_record_method_prebody;
{ A call to a class method taking a `const` small (<=8-byte) record, made
  BEFORE the method's implementation body is parsed, must use the same
  by-ref convention as the compiled body. The class-declaration header parse
  used to skip the const-record -> by-ref promotion ParseSubroutine applies,
  so the declared and implemented signatures disagreed: the pre-body call
  passed by value (a hard backend error on i386; on x86-64 the mismatched
  signature failed overload matching and left the method an unresolved
  forward). See bug-method-call-before-body-byvalue-small-record-arg. }

type
  TM = record
    Code: Pointer;
    Data: Pointer;
  end;
  TC = class
    FM: TM;
    procedure S(const m: TM);
  end;

var
  got: Int64;

{ The pre-body call site: TC.S's implementation is below. }
procedure Launch(c: TC);
var
  mt: TM;
begin
  mt.Code := c.FM.Code;
  mt.Data := c.FM.Data;
  if mt.Code <> nil then
    c.S(mt);
end;

procedure TC.S(const m: TM);
begin
  got := Int64(m.Code) + Int64(m.Data);
end;

var
  c: TC;
begin
  got := 0;
  c := TC.Create;
  c.FM.Code := Pointer(40);
  c.FM.Data := Pointer(2);
  Launch(c);
  writeln(got);            { 42: both fields crossed the call }
  c.S(c.FM);               { post-body call agrees too }
  writeln(got);
  writeln('OK');
end.
