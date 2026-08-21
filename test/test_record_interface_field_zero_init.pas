{ A local RECORD holding an interface field was never zero-initialised, so the
  first assignment to that field released STACK GARBAGE.

    type TRec = record a: Integer; f: IFoo; end;
    procedure P;
    var r: TRec;
    begin
      r.f := TFoo.Create('r');   { releases the "old" f -- stack junk --
    end;                           dispatching _Release through a garbage IMT }

  WHY IT WAS THERE. RecordHasManagedFields deliberately does NOT count a COM
  interface field, and says so: finalizing one under the record heap lock
  deadlocks, because record-scope finalization holds the non-reentrant heap
  spinlock and _Release -> Free -> FreeMem re-acquires it. The documented trade
  was that such a field LEAKS, which is benign.

  But that one predicate was answering TWO questions. Finalization must skip the
  field; ZERO-INIT must not, and cannot deadlock -- nilling a stack slot at
  routine entry takes no lock and calls nothing. Sharing the predicate turned the
  intended benign leak into a use-after-free. Split into RecordHasManagedFields
  (finalization, unchanged) and RecordNeedsZeroInit (init, counts interfaces).

  UPDATE 2026-08-21: the leak is GONE and this file now asserts destruction too.
  decide-interface-members-in-aggregates-lock-strategy chose a separate UNLOCKED
  interface pass, so RecordHasManagedFields counts interface fields again and
  the copy/scope-exit halves came with it — see the second half of this file
  (bug-a-a-record-copy-does-not-retain-an-interface-field). Every count below is
  FPC 3.2.2's on this same source.

  Like the array case, the failure only shows on a DIRTY stack -- on a clean one
  the garbage is zero and the bug is invisible -- so this test dirties the stack
  itself rather than depending on what a previous call happened to leave behind.

  The pinned binary SEGFAULTS on this file.
  bug-a-a-record-with-an-interface-field-is-not-zero-initialised }
program test_record_interface_field_zero_init;
{$mode objfpc}{$H+}

type
  IFoo = interface
    ['{11111111-1111-1111-1111-111111111111}']
    function Name: string;
  end;
  TFoo = class(TInterfacedObject, IFoo)
    fN: string;
    constructor Create(const n: string);
    destructor Destroy; override;
    function Name: string;
  end;
  TRec    = record a: Integer; f: IFoo; end;
  TNested = record tag: Integer; inner: TRec; end;

var
  pass, fail: Integer;
  destroyed: Integer;        { bumped by TFoo.Destroy — the ARC evidence }

constructor TFoo.Create(const n: string); begin inherited Create; fN := n; end;
destructor TFoo.Destroy; begin Inc(destroyed); inherited Destroy; end;
function TFoo.Name: string; begin Result := fN; end;

procedure Chk(const what: string; ok: Boolean);
begin
  if ok then begin Inc(pass); writeln('ok   ', what); end
  else begin Inc(fail); writeln('FAIL ', what); end;
end;

procedure DirtyTheStack;
var junk: array[0..31] of NativeInt; k: Integer;
begin
  for k := 0 to 31 do junk[k] := NativeInt($5A5A5A5A00) + k;
  if junk[0] = 0 then writeln('unreachable');
end;

{ 1. the minimal shape }
function PlainField: Boolean;
var r: TRec;
begin
  r.f := TFoo.Create('a');
  Result := r.f.Name = 'a';
  r.f := nil;
end;

{ 2. assigning nil first -- the release of the "old" value is the crash site }
function NilFirst: Boolean;
var r: TRec;
begin
  r.f := nil;
  Result := r.f = nil;
end;

{ 3. an interface nested one record deep: the walk must recurse }
function NestedField: Boolean;
var n: TNested;
begin
  n.inner.f := TFoo.Create('b');
  Result := n.inner.f.Name = 'b';
  n.inner.f := nil;
end;

{ 4. overwriting the field releases the previous occupant, not garbage }
function Overwrite: Boolean;
var r: TRec;
begin
  r.f := TFoo.Create('c');
  r.f := TFoo.Create('d');
  Result := r.f.Name = 'd';
  r.f := nil;
end;

{ 5. a local ARRAY of such records }
function ArrayOfRecords: Boolean;
var i: Integer; arr: array[0..2] of TRec; s: string;
begin
  for i := 0 to 2 do arr[i].f := TFoo.Create('e');
  s := '';
  for i := 0 to 2 do s := s + arr[i].f.Name;
  for i := 0 to 2 do arr[i].f := nil;
  Result := s = 'eee';
end;

{ ===== The COPY half: b := a must RETAIN, or the two records share one counted
  reference and nilling either dangles the other — a use-after-free that
  segfaults on the next member call, present on pinned.
  bug-a-a-record-copy-does-not-retain-an-interface-field ===== }

{ 6. the minimal shape: copy, then nil the source. The object must survive. }
function CopyKeepsItAlive: Boolean;
var x, y: TRec;
begin
  destroyed := 0;
  x.f := TFoo.Create('k');
  y := x;
  x.f := nil;
  Result := (destroyed = 0) and (y.f.Name = 'k');
  y.f := nil;
  Result := Result and (destroyed = 1);
end;

{ 7. `x := x` must net zero: retain-then-release, not release-then-copy-nil }
function SelfAssign: Boolean;
var x: TRec;
begin
  destroyed := 0;
  x.f := TFoo.Create('s');
  x := x;
  Result := (destroyed = 0) and (x.f.Name = 's');
  x.f := nil;
  Result := Result and (destroyed = 1);
end;

{ 8. one record deep: the walk recurses through the nested descriptor }
function NestedCopy: Boolean;
var n1, n2: TNested;
begin
  destroyed := 0;
  n1.inner.f := TFoo.Create('n');
  n2 := n1;
  n1.inner.f := nil;
  Result := (destroyed = 0) and (n2.inner.f.Name = 'n');
  n2.inner.f := nil;
  Result := Result and (destroyed = 1);
end;

{ 9. the retain must be balanced at SCOPE EXIT, or every copy leaks one ref }
procedure CopyInAScope;
var x, y: TRec;
begin
  x.f := TFoo.Create('q');
  y := x;
end;

function ScopeExitReleasesBoth: Boolean;
begin
  destroyed := 0;
  CopyInAScope;
  Result := destroyed = 1;
end;

{ 10. overwriting a record that already holds an interface releases the old one }
function CopyOverLiveTarget: Boolean;
var x, y: TRec;
begin
  destroyed := 0;
  x.f := TFoo.Create('u');
  y.f := TFoo.Create('v');
  y := x;                    { y's 'v' dies here, 'u' is now shared }
  Result := (destroyed = 1) and (y.f.Name = 'u');
  x.f := nil;
  Result := Result and (destroyed = 1);
  y.f := nil;
  Result := Result and (destroyed = 2);
end;

begin
  pass := 0; fail := 0;
  destroyed := 0;

  DirtyTheStack; Chk('interface field of a local record', PlainField);
  DirtyTheStack; Chk('nil store into the field', NilFirst);
  DirtyTheStack; Chk('interface nested one record deep', NestedField);
  DirtyTheStack; Chk('overwriting the field', Overwrite);
  DirtyTheStack; Chk('local array of such records', ArrayOfRecords);

  DirtyTheStack; Chk('record copy keeps the object alive', CopyKeepsItAlive);
  DirtyTheStack; Chk('self-assignment nets zero', SelfAssign);
  DirtyTheStack; Chk('copy one record deep', NestedCopy);
  DirtyTheStack; Chk('scope exit releases both copies', ScopeExitReleasesBoth);
  DirtyTheStack; Chk('copy over a live target releases it', CopyOverLiveTarget);

  writeln;
  writeln('total ok ', pass, ' / ', pass + fail);
end.
