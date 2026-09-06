program test_mgmt_operators_addref_declaration_shapes;
{ NO MANAGEMENT OPERATOR FOR `var`/`const`, THROUGH THE FOUR DECLARATION SHAPES
  THAT HAVE NO IMPLEMENTATION HEADER TO REPAIR THEM, AT BOTH SIZES.

  Why these four and not a sample: a parameter row is written once at the
  declaration and, for an ordinary procedure, written AGAIN at the implementation
  header -- the second write repairs the first. The shapes with no second write
  are therefore the whole broken population, not a selection from it:
  an INTERFACE method, a `virtual; abstract` method, a RECORD method
  (ParseRecordMethodDecl) and a PROC TYPE signature (ParseProcTypeSignature).
  That is structural, so a reader should not "reduce" this file to one case.
  frankB measured the population and fixed the columns (74e823da0); this file is
  the management-operator half, which reads them.

  WHAT IT GUARDS. The AddRef/Finalize hook on a by-value parameter copy asks
  ProcParamExplicitByRef -- "was `var`/`out`/`const` WRITTEN" -- to tell a real
  by-ref parameter from a by-value record that the >8-byte ABI promoted. Where
  that column is not written it reads False for BOTH, and the hook runs an
  operator on a caller's aliased record where fpc runs none. So this file fails
  if that column silently stops being written for any of the four.

  SIZE IS IRRELEVANT HERE AND THE SMALL ROWS SAY SO. The flag is named for the
  >8-byte promotion, which invites the assumption that a small record never
  reaches the arm. A `var` parameter carries IsRef at ANY size, so TSmall (4
  bytes) reaches exactly the same code with exactly the same question
  (frankB's finding: a row written as a control that could not fail, failed).

  ALL FOUR ARE EXERCISED BY A CALL, not merely declared: the declaration writes
  the parameter row, but only a call site READS it and reaches the hook under
  test, so the interface and abstract shapes carry a concrete implementor
  (TImpl, TConc) and are invoked through an interface reference and a base-class
  reference respectively. A declaration-only version of this file would pass
  with the hook completely disconnected.

  THE LAST ROW IS THE POSITIVE CONTROL AND IT MUST FIRE. Every other row here
  asserts an ABSENCE, and a file of absences passes just as well when the
  operator has been disconnected entirely. `TakeValBig` is by-value and over 8
  bytes, so AddRef runs, prints, and the callee sees 103.

  EVERY LINE OF THE .expected IS FPC 3.2.2's, byte for byte. }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TBig = record
    id: Integer; pad1, pad2, pad3: Int64;
    class operator Initialize(var a: TBig);
    class operator Finalize(var a: TBig);
    class operator AddRef(var a: TBig);
  end;
  TSmall = record
    id: Integer;
    class operator Initialize(var a: TSmall);
    class operator Finalize(var a: TSmall);
    class operator AddRef(var a: TSmall);
  end;

class operator TBig.Initialize(var a: TBig); begin a.id := 0; end;
class operator TBig.Finalize(var a: TBig);   begin end;
class operator TBig.AddRef(var a: TBig);     begin WriteLn('  !! TBig AddRef fired'); a.id := a.id + 100; end;
class operator TSmall.Initialize(var a: TSmall); begin a.id := 0; end;
class operator TSmall.Finalize(var a: TSmall);   begin end;
class operator TSmall.AddRef(var a: TSmall);     begin WriteLn('  !! TSmall AddRef fired'); a.id := a.id + 100; end;

type
  { shape 1: an INTERFACE method }
  IThing = interface ['{11111111-2222-3333-4444-555555555555}']
    procedure TakeVar(var b: TBig);
    procedure TakeConst(const b: TBig);
  end;
  { shape 2: a `virtual; abstract` method }
  TAbs = class
    procedure TakeVar(var b: TBig); virtual; abstract;
  end;
  { ...and a concrete descendant, so the abstract row is CALLED and not merely
    declared. The declaration is what writes the parameter row; a CALL is what
    reads it, and only the call reaches the hook under test. }
  TConc = class(TAbs)
    procedure TakeVar(var b: TBig); override;
  end;
  { a class implementing IThing, for the same reason }
  TImpl = class(TInterfacedObject, IThing)
    procedure TakeVar(var b: TBig);
    procedure TakeConst(const b: TBig);
  end;
  { shape 3: a RECORD method (ParseRecordMethodDecl) }
  THolder = record
    procedure TakeVarBig(var b: TBig);
    procedure TakeVarSmall(var s: TSmall);
    procedure TakeConstSmall(const s: TSmall);
    procedure TakeValBig(b: TBig);   { POSITIVE CONTROL: by-value, must fire }
  end;
  { shape 4: a PROC TYPE signature (ParseProcTypeSignature) }
  TCbBig   = procedure(var b: TBig);
  TCbSmall = procedure(var s: TSmall);

procedure THolder.TakeVarBig(var b: TBig);       begin b.id := b.id + 1; end;
procedure THolder.TakeVarSmall(var s: TSmall);   begin s.id := s.id + 1; end;
procedure THolder.TakeConstSmall(const s: TSmall); begin WriteLn('  const-small sees ', s.id); end;
procedure THolder.TakeValBig(b: TBig); begin WriteLn('  byval-big sees ', b.id); end;

procedure TConc.TakeVar(var b: TBig); begin b.id := b.id + 1; end;
procedure TImpl.TakeVar(var b: TBig);   begin b.id := b.id + 1; end;
procedure TImpl.TakeConst(const b: TBig); begin WriteLn('  intf const sees ', b.id); end;

procedure CbBig(var b: TBig);     begin b.id := b.id + 1; end;
procedure CbSmall(var s: TSmall); begin s.id := s.id + 1; end;

var
  h: THolder; big: TBig; sml: TSmall;
  fb: TCbBig; fs: TCbSmall;
  a: TAbs; it: IThing;
begin
  big.id := 1; sml.id := 1;
  WriteLn('-- record method, var, BIG --');    h.TakeVarBig(big);      WriteLn('   id=', big.id);
  WriteLn('-- record method, var, SMALL --');  h.TakeVarSmall(sml);    WriteLn('   id=', sml.id);
  WriteLn('-- record method, const, SMALL --');h.TakeConstSmall(sml);  WriteLn('   id=', sml.id);
  fb := @CbBig;   WriteLn('-- proc type, var, BIG --');   fb(big);     WriteLn('   id=', big.id);
  fs := @CbSmall; WriteLn('-- proc type, var, SMALL --'); fs(sml);     WriteLn('   id=', sml.id);
  a := TConc.Create;
  WriteLn('-- virtual abstract method, var, BIG --'); a.TakeVar(big);  WriteLn('   id=', big.id);
  a.Free;
  it := TImpl.Create;
  WriteLn('-- interface method, var, BIG --');   it.TakeVar(big);      WriteLn('   id=', big.id);
  WriteLn('-- interface method, const, BIG --'); it.TakeConst(big);    WriteLn('   id=', big.id);
  it := nil;
  WriteLn('-- POSITIVE CONTROL: record method, BY VALUE, big --'); h.TakeValBig(big);
  WriteLn('-- done --');
end.
