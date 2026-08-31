{ The accept half of test_param_row_external_forward_fail.pas, and here it is
  the more important half.

  The three registration paths in ParseSubroutine wrote different subsets of the
  durable ProcParam* columns, and the SAME omission fails in both directions:
  a missing `ProcParamPtrElemTk` made the narrowing guard fail OPEN (an object
  accepted where a typed pointer was declared), while a missing
  `ProcParamHasDefault` made the overload matcher fail CLOSED — an external
  routine with a default argument could not be called at all, which fpc 3.2.2
  accepts:

    function c_abs(x: Integer; unused: Integer = 0): Integer; cdecl;
      external 'libc.so.6' name 'abs';
    ... c_abs(-5)   -> "no overload of c_abs matches these arguments"

  So a fix measured only by what it starts REFUSING would have missed half of
  its own effect. This program compiles AND runs, because "accepted" and
  "correct" are different claims, and its output is verified against fpc.

  Each row exercises a column that one of the three paths did not write:
  defaults (external + forward), the pointee (all three), a record/class rec id,
  a set's enum id, a managed-string element width, a proc signature, and a
  `var` dynamic array — whose missing ProcParamDynDepth passes the handle VALUE
  instead of &slot, which is how SetLength corrupts memory rather than erroring.
  bug-a-an-external-routines-pointer-param-pointee-is-never-recorded-so-a-class-argument-is-accepted

  The last two rows (bodyDef, bodyRec) are the BODY path's arm of the default
  and rec-id columns, added when the three copies were collapsed into one
  nested PersistParamRow. The pointee column already proves all three paths in
  the sibling FAIL test; these make a second and third column three-for-three,
  which is what "one write site" has to mean if it means anything.

  They are a REGRESSION guard, not a demonstration: the body path already wrote
  both columns before the collapse, so these rows must pass on the pre-collapse
  compiler too. Measured rather than reasoned — a compiler built at the commit
  before the collapse prints this file's line identically. (`pinned` cannot
  compile this file at all and never could; it is the wrong control here.) }
program test_param_row_external_forward_ok;
{$mode objfpc}{$H+}
type
  PInteger = ^Integer;
  TOpt  = (oA, oB, oC);
  TOpts = set of TOpt;
  TRec  = record N: Integer; end;
  TCb   = function(x: Integer): Integer;
  TInts = array of Integer;

{ external, with a DEFAULT argument — this is the row that used to be refused }
function c_abs(x: Integer; unused: Integer = 0): Integer; cdecl; external 'libc.so.6' name 'abs';

{ forward-declared, called BEFORE its body, across the column set }
function fwdPtr(p: PInteger): Integer; forward;
function fwdDef(a: Integer; b: Integer = 7): Integer; forward;
function fwdRec(const r: TRec): Integer; forward;
function fwdSet(o: TOpts): Boolean; forward;
function fwdStr(const s: AnsiString): Integer; forward;
function fwdCb(cb: TCb; v: Integer): Integer; forward;
procedure fwdDyn(var a: TInts); forward;

function Double_(x: Integer): Integer; begin Double_ := x * 2; end;

{ BODY path, declared and defined before the caller: the default and the rec id
  again, on the third registration path }
function bodyDef(a: Integer; b: Integer = 11): Integer; begin bodyDef := a + b; end;
function bodyRec(const r: TRec): Integer; begin bodyRec := r.N * 7; end;

procedure caller;
var i: Integer; r: TRec; a: TInts; s: AnsiString;
begin
  i := 41; r.N := 5; s := 'abcd';
  SetLength(a, 1);
  fwdDyn(a);                { var dyn-array: needs &slot, not the handle }
  WriteLn('ok ',
    c_abs(-5), ' ',
    fwdPtr(@i), ' ',
    fwdDef(1), ' ',
    fwdRec(r), ' ',
    fwdSet([oA, oC]), ' ',
    fwdStr(s), ' ',
    fwdCb(@Double_, 6), ' ',
    Length(a), ' ',
    bodyDef(2), ' ',
    bodyRec(r));
end;

function fwdPtr(p: PInteger): Integer; begin fwdPtr := p^ + 1; end;
function fwdDef(a: Integer; b: Integer = 7): Integer; begin fwdDef := a + b; end;
function fwdRec(const r: TRec): Integer; begin fwdRec := r.N * 3; end;
function fwdSet(o: TOpts): Boolean; begin fwdSet := oC in o; end;
function fwdStr(const s: AnsiString): Integer; begin fwdStr := Length(s); end;
function fwdCb(cb: TCb; v: Integer): Integer; begin fwdCb := cb(v); end;
procedure fwdDyn(var a: TInts); begin SetLength(a, 3); a[2] := 9; end;

begin
  caller;
end.
