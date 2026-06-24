program test_virtual_managed_arg;
{ Regression: a string-literal argument passed to a managed-string parameter
  through a VIRTUAL call must be materialised to a managed AnsiString, exactly
  like a direct call. Before the fix the virtual-call path passed the raw inline
  literal as a managed handle → corrupt length / garbage.
  See bug-mixed-signature-vmt-misdispatch. }
type
  TBase = class
    function GetA(i: Integer): string; virtual; abstract;
    function GetCount: Integer; virtual; abstract;
    function GetObj(i: Integer): TObject; virtual; abstract;
    procedure PutA(i: Integer; const s: string); virtual; abstract;
    procedure PutObj(i: Integer; o: TObject); virtual; abstract;
    procedure ClearIt; virtual; abstract;
    procedure DelIt(i: Integer); virtual; abstract;
    procedure InsIt(i: Integer; const s: string); virtual; abstract;
  end;

  TImpl = class(TBase)
    F: array of string;
    N: Integer;
    function GetA(i: Integer): string; override;
    function GetCount: Integer; override;
    function GetObj(i: Integer): TObject; override;
    procedure PutA(i: Integer; const s: string); override;
    procedure PutObj(i: Integer; o: TObject); override;
    procedure ClearIt; override;
    procedure DelIt(i: Integer); override;
    procedure InsIt(i: Integer; const s: string); override;
  end;

function TImpl.GetA(i: Integer): string; begin GetA := F[i]; end;
function TImpl.GetCount: Integer; begin GetCount := N; end;
function TImpl.GetObj(i: Integer): TObject; begin GetObj := nil; end;
procedure TImpl.PutA(i: Integer; const s: string); begin F[i] := s; end;
procedure TImpl.PutObj(i: Integer; o: TObject); begin end;
procedure TImpl.ClearIt; begin N := 0; end;
procedure TImpl.DelIt(i: Integer); begin end;
procedure TImpl.InsIt(i: Integer; const s: string);
begin SetLength(F, N + 1); F[N] := s; N := N + 1; end;

var
  b: TBase;
begin
  b := TImpl.Create;
  b.InsIt(0, 'banana');       { virtual call, managed-string literal arg }
  b.InsIt(1, 'apple');
  b.PutA(0, 'cherry');        { virtual setter, literal arg }
  writeln(b.GetCount);        { 2 }
  writeln(b.GetA(0));         { cherry }
  writeln(b.GetA(1));         { apple }
end.
