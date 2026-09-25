{ An `out` parameter of a MANAGED type is finalized at the callee's entry, and
  that finalize is its own CompileAST. It ran without RcSuppressAssign, so at
  -O2 the callee emitted its r14/r15 residency save+load TWICE: the second save
  captured the callee's own parameter, and the single epilogue restored THAT
  into the caller's register. The caller's resident first parameter came back
  holding the callee's first argument, and a method's Self came back as 0
  (SIGSEGV on the next field access). FindFirst(.., sr: TSearchRec) is the real
  reach: any recursive directory walk stopped at depth 1, and the ESP IDE
  crashed listing serial ports.
  Every caller value below is a NON-default 7 or 70, and every callee receives
  a different first argument, so a clobber cannot print the right number. The
  make row runs this at -O2, -O3 and -O0. }
program test_out_managed_param_keeps_the_caller_s_registers;
{$mode objfpc}
type
  IDummy = interface end;
  TDummy = class(TInterfacedObject, IDummy) end;
  TStrRec = record A: Int64; Name: AnsiString; end;
  TDynRec = record A: Int64; D: array of Integer; end;
  TIntfRec = record A: Int64; I: IDummy; end;
  TVarRec2 = record A: Int64; V: Variant; end;
  TPlain = record A: Int64; B: Int64; end;
  TX = class
    FField: Integer;
    function OutM(A: LongInt; out R: TStrRec): LongInt;
    procedure M;
  end;

function FS(A: LongInt; out R: TStrRec): LongInt; begin R.A := 1; R.Name := 'x'; FS := A; end;
function FD(A: LongInt; out R: TDynRec): LongInt; begin R.A := 1; SetLength(R.D, 2); FD := A; end;
function FI(A: LongInt; out R: TIntfRec): LongInt; begin R.A := 1; R.I := TDummy.Create; FI := A; end;
function FV(A: LongInt; out R: TVarRec2): LongInt; begin R.A := 1; R.V := 5; FV := A; end;
function FP(A: LongInt; out R: TPlain): LongInt; begin R.A := 1; FP := A; end;
function FA(A: LongInt; out S: AnsiString): LongInt; begin S := 'y'; FA := A; end;
function FT(A: LongInt; out R1: TStrRec; out R2: TDynRec): LongInt;
begin R1.A := 1; R2.A := 2; FT := A; end;

function TX.OutM(A: LongInt; out R: TStrRec): LongInt; begin R.A := A; OutM := A + FField; end;

procedure WS(depth: Integer); var r: TStrRec; begin FS(16, r); WriteLn('string-rec ', depth, ' ', r.Name); end;
procedure WD(depth: Integer); var r: TDynRec; begin FD(17, r); WriteLn('dynarr-rec ', depth, ' ', Length(r.D)); end;
procedure WI(depth: Integer); var r: TIntfRec; begin FI(18, r); WriteLn('intf-rec ', depth, ' ', r.I <> nil); end;
procedure WV(depth: Integer); var r: TVarRec2; begin FV(19, r); WriteLn('variant-rec ', depth, ' ', Integer(r.V)); end;
procedure WP(depth: Integer); var r: TPlain; begin FP(20, r); WriteLn('plain-rec ', depth, ' ', r.A); end;
procedure WA(depth: Integer); var s: AnsiString; begin FA(21, s); WriteLn('ansistring ', depth, ' ', s); end;
procedure WT(depth: Integer); var r1: TStrRec; r2: TDynRec; begin FT(22, r1, r2); WriteLn('two-outs ', depth, ' ', r1.A + r2.A); end;

function G: Integer; var r: TStrRec; begin FS(16, r); G := 1; end;

procedure TX.M;
var r: TStrRec; n: LongInt;
begin
  FField := 70;
  G;
  n := OutM(23, r);
  WriteLn('method Self ', FField, ' ', n, ' ', r.A);
end;

var x: TX;
begin
  WS(7); WD(7); WI(7); WV(7); WP(7); WA(7); WT(7);
  x := TX.Create; x.M; x.Free;
end.
