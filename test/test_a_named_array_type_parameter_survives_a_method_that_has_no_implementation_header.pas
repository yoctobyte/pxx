program test_a_named_array_type_parameter_survives_a_method_that_has_no_implementation_header;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

{ `procedure Dy(a: TDyn)` where `TDyn = array of Integer`, declared on an
  INTERFACE or as `virtual; abstract`, was refused at every call site --
  `no overload of Dy matches these arguments` -- and compiled-then-segfaulted
  when the argument was `nil`.

  IT IS NOT AN INTERFACE BUG, AND THAT IS THE WHOLE FINDING. The four parameter
  parsers in pasparser_decl.inc knew only the LITERAL `array of` spelling; a
  NAMED array type fell to ParseTypeKind, which collapses it to a scalar, so the
  row recorded IsArray = False and the ELEMENT kind as the parameter's own.
  ParseSubroutine has had the named-array arm for as long as named fixed arrays
  have worked.

  A class or record method is declared TWICE -- in the body, and again by its
  implementation header, which goes through ParseSubroutine and OVERWRITES the
  row. So the wrong row was written for every method in the language and
  repaired for every method with a body in the same unit. The two spellings with
  no implementation header are an INTERFACE method and `virtual; abstract`, and
  those are the only places it survived to a call site. A defect present
  everywhere, observable in two places.

  WHICH IS WHY THE ABSTRACT ROWS ARE HERE AND ARE NOT AN INTERFACE. The ticket
  was filed as "an interface-dispatched call segfaults" and a fixture built from
  that sentence would have been all-interface and would have said nothing about
  the cause. `b.Dy(d)` through a plain class reference to a `virtual; abstract`
  method is the row that separates "interface dispatch" from "no implementation
  header", and it fails identically before the fix.

  EVERY ROW PRINTS CONTENTS. The ticket's own repro passed `nil`, and a nil
  handle and a mis-marshalled one both read as Length 0 -- so a length assertion
  cannot tell the fix from the bug on that row. Values are distinct and
  ascending; the nil row is kept and labelled as the ORIGINAL repro rather than
  as evidence.

  Verified row-for-row against fpc 3.2.2 -Mobjfpc.
  bug-p-an-interface-dispatched-call-passing-a-named-dynamic-array-segfaults }

type
  TDyn = array of Integer;
  TFix = array[0..2] of Integer;

  IFoo = interface
    ['{5E1B0A11-1111-4222-8333-444455556666}']
    function  CDyn(const a: TDyn): AnsiString;
    function  CFix(const a: TFix): AnsiString;
    procedure Grow(var a: TDyn);
    function  COpen(const a: array of Integer): AnsiString;   { always worked }
    function  CScalar(n: Integer): AnsiString;                { always worked }
  end;

  { no implementation header for these two, and no interface either }
  TBase = class(TInterfacedObject)
    function ADyn(const a: TDyn): AnsiString; virtual; abstract;
    function AFix(const a: TFix): AnsiString; virtual; abstract;
  end;

  TFoo = class(TBase, IFoo)
    function  CDyn(const a: TDyn): AnsiString;
    function  CFix(const a: TFix): AnsiString;
    procedure Grow(var a: TDyn);
    function  COpen(const a: array of Integer): AnsiString;
    function  CScalar(n: Integer): AnsiString;
    function  ADyn(const a: TDyn): AnsiString; override;
    function  AFix(const a: TFix): AnsiString; override;
    { an ordinary method WITH a body: the control the implementation header
      repaired all along }
    function  Plain(const a: TDyn): AnsiString;
  end;

  TRec = record
    function RDyn(const a: TDyn): AnsiString;
  end;

  TCb = function(const a: TDyn): AnsiString;

var
  fails: LongInt = 0;

function ShowD(const a: TDyn): AnsiString;
var k: LongInt; s, d: AnsiString;
begin
  s := '[';
  for k := 0 to High(a) do
  begin
    if k > 0 then s := s + ',';
    Str(a[k], d); s := s + d;
  end;
  Str(Length(a), d);
  ShowD := s + '] n=' + d;
end;

function ShowF(const a: TFix): AnsiString;
var k: LongInt; s, d: AnsiString;
begin
  s := '[';
  for k := 0 to High(a) do
  begin
    if k > 0 then s := s + ',';
    Str(a[k], d); s := s + d;
  end;
  Str(Length(a), d);
  ShowF := s + '] n=' + d;
end;

function TFoo.CDyn(const a: TDyn): AnsiString;   begin CDyn := ShowD(a); end;
function TFoo.CFix(const a: TFix): AnsiString;   begin CFix := ShowF(a); end;
procedure TFoo.Grow(var a: TDyn);
begin SetLength(a, Length(a) + 1); a[High(a)] := 99; end;
function TFoo.COpen(const a: array of Integer): AnsiString;
var k: LongInt; s, d: AnsiString;
begin
  s := '[';
  for k := 0 to High(a) do
  begin
    if k > 0 then s := s + ',';
    Str(a[k], d); s := s + d;
  end;
  Str(Length(a), d);
  COpen := s + '] n=' + d;
end;
function TFoo.CScalar(n: Integer): AnsiString;
var d: AnsiString; begin Str(n, d); CScalar := d; end;
function TFoo.ADyn(const a: TDyn): AnsiString;   begin ADyn := ShowD(a); end;
function TFoo.AFix(const a: TFix): AnsiString;   begin AFix := ShowF(a); end;
function TFoo.Plain(const a: TDyn): AnsiString;  begin Plain := ShowD(a); end;
function TRec.RDyn(const a: TDyn): AnsiString;   begin RDyn := ShowD(a); end;

procedure Expect(const what, got, want: AnsiString);
begin
  if got = want then
    WriteLn('ok   ', what, ' ', got)
  else
  begin
    WriteLn('FAIL ', what, ' got ', got, ' want ', want);
    Inc(fails);
  end;
end;

var
  i: IFoo;
  f: TFoo;
  b: TBase;
  r: TRec;
  cb: TCb;
  d, g: TDyn;
  x: TFix;
const
  D3 = '[11,12,13] n=3';
  F3 = '[21,22,23] n=3';
begin
  f := TFoo.Create;
  i := f;
  b := f;
  cb := @ShowD;
  SetLength(d, 3); d[0] := 11; d[1] := 12; d[2] := 13;
  x[0] := 21; x[1] := 22; x[2] := 23;

  { --- the controls that always worked --- }
  Expect('ctrl scalar ', i.CScalar(7), '7');
  Expect('ctrl open   ', i.COpen(d), D3);
  Expect('ctrl body   ', f.Plain(d), D3);
  Expect('ctrl record ', r.RDyn(d), D3);
  Expect('ctrl free   ', ShowD(d), D3);
  Expect('ctrl proctyp', cb(d), D3);

  { --- an INTERFACE method: no implementation header --- }
  Expect('iface dyn   ', i.CDyn(d), D3);
  Expect('iface fixed ', i.CFix(x), F3);

  { --- `virtual; abstract`: no implementation header AND no interface. This is
        the row that says the cause is not interface dispatch. --- }
  Expect('abstract dyn', b.ADyn(d), D3);
  Expect('abstract fix', b.AFix(x), F3);

  { --- a `var` named dynamic array through the interface. This needs the
        by-ref HANDLE ABI, i.e. the dynamic-DEPTH column and not just IsArray;
        with IsArray alone it compiled and segfaulted here. --- }
  SetLength(g, 2); g[0] := 31; g[1] := 32;
  i.Grow(g);
  Expect('iface var   ', ShowD(g), '[31,32,99] n=3');

  { --- the ticket's ORIGINAL repro, kept and labelled: `nil` reads as length 0
        whether the marshalling is right or wrong, so this row cannot tell the
        fix from the bug and is here only because it is what was filed. --- }
  Expect('iface nil   ', i.CDyn(nil), '[] n=0');

  if fails = 0 then WriteLn('NAMEDARRAYPARAM OK') else WriteLn('NAMEDARRAYPARAM FAILED ', fails);
end.
