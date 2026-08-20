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

  So the leak is still here BY DESIGN and this test asserts the crash is gone,
  not that the object is destroyed: `destroyed` stays 0 where FPC reports 1, and
  that gap belongs to bug-a-class-managed-fields-not-finalized-on-destroy.

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
    function Name: string;
  end;
  TRec    = record a: Integer; f: IFoo; end;
  TNested = record tag: Integer; inner: TRec; end;

var
  pass, fail: Integer;

constructor TFoo.Create(const n: string); begin inherited Create; fN := n; end;
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

begin
  pass := 0; fail := 0;

  DirtyTheStack; Chk('interface field of a local record', PlainField);
  DirtyTheStack; Chk('nil store into the field', NilFirst);
  DirtyTheStack; Chk('interface nested one record deep', NestedField);
  DirtyTheStack; Chk('overwriting the field', Overwrite);
  DirtyTheStack; Chk('local array of such records', ArrayOfRecords);

  writeln;
  writeln('total ok ', pass, ' / ', pass + fail);
end.
