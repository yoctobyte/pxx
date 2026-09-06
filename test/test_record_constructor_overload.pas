{ A record constructor call must pick its overload by ARGUMENT COUNT, exactly as
  the class arm already does. Before 2026-09-07 the record arm used FindUMeth --
  first-declared wins -- so TRec.Create(2) ran Create(dummy: Boolean) (a SILENT
  WRONG VALUE) and TRec.Create(1, 2) entered the 1-argument body with two
  arguments pushed (a SEGFAULT). Differential against fpc; the class rows are the
  control that must stay correct.

  Row 6 is deliberately the FIRST-DECLARED overload: if a future change makes
  lookup pick the LAST match instead, rows 1-3 stay green and only this one goes
  red. }
program test_record_constructor_overload;
{$mode delphi}
type
  TRec = record
    X, Y: Integer;
    constructor Create(dummy: Boolean); overload;
    constructor Create(AX, AY: Integer); overload;
    constructor Create(AY: Integer); overload;
  end;
  TCls = class
    X, Y: Integer;
    constructor Create(dummy: Boolean); overload;
    constructor Create(AX, AY: Integer); overload;
    constructor Create(AY: Integer); overload;
  end;

constructor TRec.Create(dummy: Boolean); begin X := 10; Y := 20; end;
constructor TRec.Create(AX, AY: Integer); begin X := AX; Y := AY; end;
constructor TRec.Create(AY: Integer); begin X := 10; Y := AY; end;

constructor TCls.Create(dummy: Boolean); begin X := 10; Y := 20; end;
constructor TCls.Create(AX, AY: Integer); begin X := AX; Y := AY; end;
constructor TCls.Create(AY: Integer); begin X := 10; Y := AY; end;

procedure ShowR(R: TRec); begin Writeln(R.X, ' ', R.Y); end;

var
  R: TRec;
  C: TCls;
begin
  R := TRec.Create(1, 2);   Writeln(R.X, ' ', R.Y);   { 1 2   -- used to SEGFAULT }
  R := TRec.Create(2);      Writeln(R.X, ' ', R.Y);   { 10 2  -- used to print 10 20 }
  R := TRec.Create(False);  Writeln(R.X, ' ', R.Y);   { 10 20 }
  ShowR(TRec.Create(1, 2));                           { 1 2   -- argument position }
  ShowR(TRec.Create(2));                              { 10 2 }
  ShowR(TRec.Create(True));                           { 10 20 -- first-declared arm }
  C := TCls.Create(1, 2);   Writeln(C.X, ' ', C.Y);   { control: the class arm }
  C := TCls.Create(2);      Writeln(C.X, ' ', C.Y);
  C := TCls.Create(False);  Writeln(C.X, ' ', C.Y);
end.
