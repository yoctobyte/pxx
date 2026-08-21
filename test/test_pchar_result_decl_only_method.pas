program test_pchar_result_decl_only_method;
{ A method whose call resolves to a DECLARATION rather than to an implementation
  — an abstract method reached through the base class, or an interface method
  reached through the interface — returning PChar.

  Two halves of one gap, and BOTH are needed (refactor-centralize-managed-string-
  pchar-conversion):

    1. the three method-DECL registration paths never set ProcRetPtrElemTk, so
       the recorded return-element type stayed tyUnknown. For a method with a
       body that is harmless (the implementation re-registers through the normal
       path); for an abstract or interface method there IS no implementation to
       fall back on.
    2. IsNodePChar / IRPointerStride enumerated AN_CALL and AN_CALL_IND only, so
       even a populated AN_VIRTUAL_CALL / AN_INTF_CALL was not recognised.

  Symptom of either: `AnsiString(x.GetP)` lowers as a raw pointer cast and yields
  an EMPTY string. Silent wrong value — no diagnostic, no crash. Every expected
  value here is FPC 3.2.2's on this same source. }
{$mode objfpc}{$H+}

type
  IGet = interface
    ['{22222222-2222-2222-2222-222222222222}']
    function GetP: PChar;
  end;

  TBase = class
    function GetP: PChar; virtual; abstract;
    function GetTail: PChar; virtual; abstract;
  end;

  TImpl = class(TBase)
    function GetP: PChar; override;
    function GetTail: PChar; override;
  end;

  TIntfImpl = class(TInterfacedObject, IGet)
    function GetP: PChar;
  end;

  { ...and the same metadata pair one step further: a TYPED pointer result whose
    element is a RECORD. IRPointerStride's call arm read the element KIND and
    never the element's record id, so RecSize(REC_NONE) answered the pointer
    size — `P2 - P0` over a 24-byte record gave 6 instead of 2, on a plain
    function as well as a virtual one. }
  TRec = record a, b, c: Int64; end;
  PRec = ^TRec;

  TRecBase = class
    function R0: PRec; virtual; abstract;
    function R2: PRec; virtual; abstract;
  end;

  TRecImpl = class(TRecBase)
    function R0: PRec; override;
    function R2: PRec; override;
  end;

var
  buf: array[0..15] of Char;
  recs: array[0..3] of TRec;
  pass, fail: Integer;

function TImpl.GetP: PChar; begin Result := @buf[0]; end;
function TImpl.GetTail: PChar; begin Result := @buf[3]; end;
function TIntfImpl.GetP: PChar; begin Result := @buf[0]; end;
function TRecImpl.R0: PRec; begin Result := @recs[0]; end;
function TRecImpl.R2: PRec; begin Result := @recs[2]; end;

function PlainR0: PRec; begin Result := @recs[0]; end;
function PlainR2: PRec; begin Result := @recs[2]; end;

procedure Chk(const what: string; ok: Boolean);
begin
  if ok then begin Inc(pass); writeln('ok   ', what); end
  else begin Inc(fail); writeln('FAIL ', what); end;
end;

function Consume(const s: AnsiString): Integer;
begin
  Result := Length(s);
end;

var
  b: TBase;
  g: IGet;
  rb: TRecBase;
  s: AnsiString;
  d: PtrInt;
  pr: PRec;
begin
  pass := 0; fail := 0;
  buf[0] := 'a'; buf[1] := 'b'; buf[2] := 'c'; buf[3] := 'd';
  buf[4] := 'e'; buf[5] := #0;

  b := TImpl.Create;
  g := TIntfImpl.Create;

  { the cast — the reported shape }
  s := AnsiString(b.GetP);
  Chk('cast of an abstract method result', s = 'abcde');

  s := AnsiString(g.GetP);
  Chk('cast of an interface method result', s = 'abcde');

  { assignment without a cast: same conversion, different context }
  s := b.GetP;
  Chk('assign an abstract method result', s = 'abcde');

  { concatenation }
  s := '<' + AnsiString(b.GetP) + '>';
  Chk('concat an abstract method result', s = '<abcde>');

  { as an argument }
  Chk('pass an abstract method result', Consume(AnsiString(b.GetP)) = 5);

  { POINTER ARITHMETIC on the result: the stride must be 1 (char), not 8 —
    IRPointerStride enumerated the same two node kinds. }
  d := b.GetTail - b.GetP;
  Chk('difference of two abstract method results', d = 3);

  { the record-pointer stride, virtual and plain }
  rb := TRecImpl.Create;
  Chk('difference of two PRec results (virtual)', (rb.R2 - rb.R0) = 2);
  Chk('difference of two PRec results (plain)', (PlainR2 - PlainR0) = 2);
  pr := PlainR0 + 2;
  Chk('PRec result plus two', pr = @recs[2]);

  writeln;
  writeln('total ok ', pass, ' / ', pass + fail);
end.
