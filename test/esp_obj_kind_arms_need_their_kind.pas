program esp_obj_kind_arms_need_their_kind;
{ The DCE cuts a managed-value walk's call for a member or element kind no
  descriptor carries (DceCutDeadKindArms): PXXRecordRelease's variant and
  NilPy-object arms, the dyn-array walks' variant and interface arms, and the
  interface-member walks altogether. Built plain, this program has records and
  arrays of strings only, so those arms are dropped and must not be missed: the
  string releases still balance. Built with -dALL it puts a Variant and an
  interface in a record, and arrays of both, and every one must be released
  exactly as on x86-64 -- a Destroy line per object, in order. }
{$mode objfpc}
type
  TRec = record
    s: AnsiString;
    n: Integer;
  end;
{$ifdef ALL}
  IThing = interface
    procedure Hello;
  end;
  TThing = class(TInterfacedObject, IThing)
    FName: AnsiString;
    constructor Create(const nm: AnsiString);
    destructor Destroy; override;
    procedure Hello;
  end;
  TIntfRec = record
    s: AnsiString;
    t: IThing;
  end;
  TVarRec = record
    s: AnsiString;
    v: Variant;
  end;

constructor TThing.Create(const nm: AnsiString);
begin
  FName := nm;
end;

destructor TThing.Destroy;
begin
  writeln('destroy ', FName);
  inherited Destroy;
end;

procedure TThing.Hello;
begin
  writeln('hello ', FName);
end;
{$endif}

procedure Strings;
var r: TRec; a: array of TRec; i: Integer;
begin
  r.s := 'rec'; r.n := 1;
  SetLength(a, 3);
  for i := 0 to 2 do
  begin
    a[i].s := 'el' + Chr(Ord('0') + i);
    a[i].n := i;
  end;
  a[1] := r;
  writeln(r.s, ' ', a[0].s, ' ', a[1].s, ' ', a[2].s);
  SetLength(a, 1);
  writeln(Length(a), ' ', a[0].s);
end;

{$ifdef ALL}
procedure Intfs;
var r: TIntfRec; a: array of IThing; b: array of TIntfRec;
begin
  r.s := 'r';
  r.t := TThing.Create('in-record');
  r.t.Hello;
  SetLength(a, 2);
  a[0] := TThing.Create('in-array-0');
  a[1] := TThing.Create('in-array-1');
  SetLength(b, 1);
  b[0].t := TThing.Create('in-record-array');
  writeln('intfs built');
  SetLength(a, 1);
  writeln('array shrunk');
end;

procedure Variants;
var r: TVarRec; a: array of Variant;
begin
  r.s := 'v';
  r.v := 'variant string';
  SetLength(a, 2);
  a[0] := 42;
  a[1] := 'second';
  writeln(r.v, ' ', a[0], ' ', a[1]);
end;
{$endif}

begin
  Strings;
{$ifdef ALL}
  Intfs;
  writeln('after intfs');
  Variants;
{$endif}
  writeln('done');
end.
