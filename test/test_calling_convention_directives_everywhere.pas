{ Every calling-convention spelling, in every position that can carry one.

  These were four independent lists and they disagreed: `stdcall` was fine on a
  class METHOD and a parse error on a plain routine, an `external`, and a
  procedural type — so which spelling worked depended on where it was written,
  and a port hit a parse error on a directive that would have been ignored one
  line lower. Three of the four were unified earlier; the procedural type kept
  its own hard-coded `cdecl` until now.

  A convention is the TARGET's, so pxx treats these as decoration — accepted
  and ignored — with exactly one exception: `cdecl` on a procedural TYPE marks
  the signature C-ABI, because an indirect call through a dlsym'd C function
  has to marshal System V (test_cdecl_indirect asserts that half). The other
  spellings must NOT mark it: `register` is FPC's own convention, not C's, so
  the Double rows at the end are the negative half — a Double and an Integer
  through a `register`/`stdcall`/plain procedural type still reach a pxx
  routine by pxx's internal convention and come back 6.0.

  Every routine below is declared with the SAME convention as the procedural
  type it is assigned to, because FPC type-checks that pairing and this file is
  oracled against FPC 3.2.2. pxx does not check it — a convention it does not
  model cannot make two signatures incompatible — which is a place pxx accepts
  more than FPC, not a defect.
  compat-pascal-calling-convention-directives-uneven }
program test_calling_convention_directives_everywhere;

type
  { procedural type — the position that was still cdecl-only }
  TFnRegister = function(a: Integer): Integer; register;
  TFnStdcall  = function(a: Integer): Integer; stdcall;
  TFnSafecall = function(a: Integer): Integer; safecall;
  TFnMwpascal = function(a: Integer): Integer; mwpascal;
  TFnCdecl    = function(a: Integer): Integer; cdecl;

  { class method declaration, and the implementation header below }
  TC = class
    procedure MCdecl;    cdecl;
    procedure MRegister; register;
    procedure MStdcall;  stdcall;
    procedure MSafecall; safecall;
    procedure MPascal;   pascal;
    procedure MMwpascal; mwpascal;
  end;

  { the ABI half: a plain and a decorated procedural type over the same shape }
  TScalePlain = function(x: Double; n: Integer): Double;
  TScaleReg   = function(x: Double; n: Integer): Double; register;
  TScaleStd   = function(x: Double; n: Integer): Double; stdcall;

{ routine with a body }
procedure RCdecl(a: Integer);    cdecl;    begin end;
procedure RRegister(a: Integer); register; begin end;
procedure RStdcall(a: Integer);  stdcall;  begin end;
procedure RSafecall(a: Integer); safecall; begin end;
procedure RPascal(a: Integer);   pascal;   begin end;
procedure RMwpascal(a: Integer); mwpascal; begin end;

{ external declaration }
function XCdecl:    Integer; cdecl;    external 'libc.so.6' name 'getpid';
function XRegister: Integer; register; external 'libc.so.6' name 'getpid';
function XStdcall:  Integer; stdcall;  external 'libc.so.6' name 'getpid';
function XSafecall: Integer; safecall; external 'libc.so.6' name 'getpid';
function XPascal:   Integer; pascal;   external 'libc.so.6' name 'getpid';
function XMwpascal: Integer; mwpascal; external 'libc.so.6' name 'getpid';

procedure TC.MCdecl;    cdecl;    begin writeln('m cdecl'); end;
procedure TC.MRegister; register; begin writeln('m register'); end;
procedure TC.MStdcall;  stdcall;  begin writeln('m stdcall'); end;
procedure TC.MSafecall; safecall; begin writeln('m safecall'); end;
procedure TC.MPascal;   pascal;   begin writeln('m pascal'); end;
procedure TC.MMwpascal; mwpascal; begin writeln('m mwpascal'); end;

function TwiceRegister(a: Integer): Integer; register; begin TwiceRegister := a * 2; end;
function TwiceStdcall(a: Integer): Integer;  stdcall;  begin TwiceStdcall  := a * 2; end;
function TwiceSafecall(a: Integer): Integer; safecall; begin TwiceSafecall := a * 2; end;
function TwiceMwpascal(a: Integer): Integer; mwpascal; begin TwiceMwpascal := a * 2; end;
function TwiceCdecl(a: Integer): Integer;    cdecl;    begin TwiceCdecl    := a * 2; end;

function ScalePlain(x: Double; n: Integer): Double;           begin ScalePlain := x * n; end;
function ScaleReg(x: Double; n: Integer): Double;   register; begin ScaleReg   := x * n; end;
function ScaleStd(x: Double; n: Integer): Double;   stdcall;  begin ScaleStd   := x * n; end;

var
  c: TC;
  fr: TFnRegister; fs: TFnStdcall; fa: TFnSafecall;
  fm: TFnMwpascal; fc: TFnCdecl;
  sp: TScalePlain; sr: TScaleReg;  ss: TScaleStd;
begin
  RCdecl(1); RRegister(1); RStdcall(1); RSafecall(1); RPascal(1); RMwpascal(1);
  writeln('routines ok');

  { XSafecall is declared but not asserted on: FPC MODELS safecall, and its
    model rewrites the declared result into an out-parameter with the real
    return being an HRESULT — so under FPC it answers 0 where every other
    spelling answers the pid. Declaring it is what this row is testing. }
  if (XCdecl > 0) and (XRegister > 0) and (XStdcall > 0) and
     (XPascal > 0) and (XMwpascal > 0) then
    writeln('externals ok');

  c := TC.Create;
  c.MCdecl; c.MRegister; c.MStdcall; c.MSafecall; c.MPascal; c.MMwpascal;

  fr := @TwiceRegister; fs := @TwiceStdcall; fa := @TwiceSafecall;
  fm := @TwiceMwpascal; fc := @TwiceCdecl;
  writeln(fr(21), ' ', fs(21), ' ', fa(21), ' ', fm(21), ' ', fc(21));

  sp := @ScalePlain; sr := @ScaleReg; ss := @ScaleStd;
  writeln(sp(1.5, 4):0:1);
  writeln(sr(1.5, 4):0:1);
  writeln(ss(1.5, 4):0:1);
end.
