program test_thread_heap;
{ M5 foundation: the heap allocator is thread-safe under --threadsafe (x86-64
  lock-prefixed spinlock around PXXAlloc/PXXFree). NT TThreads each churn
  GetMem/FreeMem; each fills its block with a thread-unique byte and reads it back.
  If the allocator ever handed the same block to two threads at once, a readback
  would see the other thread's tag -> a counted error. Must finish with 0 errors
  and not crash. Compile with --threadsafe. Libc-free. }
uses palthread, palthreadobj;

const
  NT = 4;
  K  = 12000;
  SZ = 128;

type
  PByte = ^Byte;

var
  errors: Integer;     { atomic: blocks that saw a foreign tag }

type
  TChurn = class(TThread)
  public
    Tag: Integer;
  protected
    procedure Execute; override;
  end;

procedure TChurn.Execute;
var
  j, b: Integer;
  p: Pointer;
  pb: PByte;
  bad: Boolean;
  ignore: Int64;
begin
  for j := 1 to K do
  begin
    GetMem(p, SZ);
    pb := PByte(p);
    for b := 0 to SZ - 1 do pb[b] := Byte(Tag);
    bad := False;
    for b := 0 to SZ - 1 do
      if pb[b] <> Byte(Tag) then bad := True;
    if bad then ignore := __pxxatomic_add(@errors, 1);
    FreeMem(p);
  end;
end;

var
  w: array[0..NT-1] of TChurn;
  i: Integer;
begin
  errors := 0;
  for i := 0 to NT - 1 do
  begin
    w[i] := TChurn.Create(True);
    w[i].Tag := i + 1;
  end;
  for i := 0 to NT - 1 do w[i].Start;
  for i := 0 to NT - 1 do w[i].WaitFor;

  writeln('errors=', errors);
  if errors = 0 then writeln('HEAP OK') else writeln('HEAP FAIL');
end.
