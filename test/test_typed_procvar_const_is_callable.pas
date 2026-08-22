{ `const K: TFn = @Sq;` could be declared and assigned to a variable, but never
  CALLED: the const path allocated the symbol without copying LastTypeProcSig
  into SymProcSig, and both call sites gate on SymProcSig >= 0.
  bug-a-a-typed-procvar-constant-cannot-be-called }
program test_typed_procvar_const_is_callable;

type
  TFn = function(x: Integer): Integer;
  TP  = procedure(x: Integer);
  TV  = procedure;

function Sq(x: Integer): Integer; begin Sq := x * x; end;
function Neg(x: Integer): Integer; begin Neg := -x; end;
procedure Emit(x: Integer); begin WriteLn('emit ', x); end;
procedure Bare; begin WriteLn('bare'); end;
procedure Use(g: TFn); begin WriteLn('arg ', g(6)); end;

const
  KFn: TFn = @Sq;
  KProc: TP = @Emit;
  KVoid: TV = @Bare;

{ a routine-local typed const takes a different storage path (static BSS +
  a prologue init) than a global one, so it needs its own row }
procedure Local;
const
  LFn: TFn = @Neg;
begin
  WriteLn('local ', LFn(3));
end;

var
  f: TFn;
begin
  WriteLn('direct ', KFn(7));            { the call that used to be a syntax error }
  KProc(4);
  KVoid;                                  { parameterless, no parens }
  KVoid();                                { ...and with them }
  Local;
  f := KFn;                               { the path that always worked }
  WriteLn('viavar ', f(5));
  WriteLn('mixed ', f(2) + KFn(3));       { const call inside a larger expression }
  Use(KFn);                               { const passed as a procvar argument }
  WriteLn('assigned ', Assigned(KFn));
end.
