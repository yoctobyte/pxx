program scopeexit_slice;
{ Managed locals must be released at ORDINARY scope exit -- no exception, no
  unwind -- on every target, and wasm32 released only two of the kinds.

  THREE KINDS, THREE DIFFERENT RELEASE HELPERS, and the object counts its own
  destructions so the assertion does not depend on the allocator census being
  compiled in. Measured on wasm32 before the fix (wasmtime 48.0.1):

      COM interface local        gone=0 of 50      (PXXIntfRelease never called)
      record with managed fields live=543 of 3799  (PXXRecordRelease absent)
      static array of AnsiString live=871 of 6088  (PXXArrayReleaseImmediate absent)

  and after it, gone=50 and live=3/live=4, which is what x86-64 says.

  The interface row is the one that asserts a NUMBER the program itself
  produces, so it is the row that works without -dPXX_ALLOC_CENSUS and the one
  wired into the suite. It fails loudly against the old backend rather than
  leaking quietly, which is the whole difficulty with this defect class: a leak
  prints nothing and both sides of a native-vs-wasm differential produce
  identical OUTPUT.

  bug-a-managed-locals-leak-at-ORDINARY-scope-exit-on-wasm32-and-a-variant-local-traps }
type
  IThing = interface
    ['{11111111-2222-3333-4444-555555555555}']
    procedure Poke;
  end;

var Made, Gone: Integer;

type
  TThing = class(TInterfacedObject, IThing)
    procedure Poke;
    destructor Destroy; override;
  end;

procedure TThing.Poke; begin end;
destructor TThing.Destroy; begin Inc(Gone); inherited Destroy; end;

type
  TRec = record a, b: AnsiString; end;
  TSArr = array[0..2] of AnsiString;

function MakeStr(n: Integer): AnsiString;
var r: AnsiString; k: Integer;
begin
  r := '';
  for k := 0 to (n mod 5) + 2 do r := r + Chr(65 + ((n + k) mod 26));
  MakeStr := r;
end;

procedure RecAndArray;
var r: TRec; a: TSArr; n: Integer;
begin
  for n := 1 to 40 do
  begin
    r.a := MakeStr(n); r.b := MakeStr(n + 1);
    a[0] := MakeStr(n); a[1] := MakeStr(n + 1); a[2] := MakeStr(n + 2);
    if (Length(r.a) = 0) or (Length(a[2]) = 0) then
    begin WriteLn('FAIL: managed field or element came back empty'); Halt(1); end;
  end;
end;

procedure Hold;
var t: IThing;
begin
  t := TThing.Create;
  Inc(Made);
  t.Poke;
end;

var i: Integer;
begin
  Made := 0; Gone := 0;
  for i := 1 to 50 do Hold;
  WriteLn('made=', Made, ' gone=', Gone);
  if Gone <> Made then
  begin
    WriteLn('FAIL: ', Made - Gone, ' interface local(s) never released at scope exit');
    Halt(1);
  end;
  { A record with managed fields and a static array of string go through
    PXXRecordRelease and PXXArrayReleaseImmediate, which the interface row does
    not reach. Their leak is invisible without the census, so what is asserted
    here is that they RUN and produce the right values -- the release itself is
    measured in the ticket. }
  RecAndArray;
  WriteLn('MANAGED LOCAL RELEASE OK');
end.
