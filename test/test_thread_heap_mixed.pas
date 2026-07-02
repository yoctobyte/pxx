program test_thread_heap_mixed;
{ feature-threadsafe-heap-contract: the hosted x86-64 heap under --threadsafe
  must survive CONCURRENT allocation of every allocation family, not just raw
  GetMem/FreeMem (test_thread_heap covers those). NT threads each churn, per
  iteration: an AnsiString (concat + SetLength), a dynamic array of Integer
  (SetLength grow/shrink + element writes), a dynamic array of AnsiString
  (managed elements), a class instance (Create/fill/Free), and a raw block
  (GetMem/ReallocMem/FreeMem). Every block is filled with a thread-unique tag
  and read back; a foreign tag or wrong length = a counted error. Must finish
  with 0 errors. Compile with --threadsafe. Libc-free. }
uses palthread, palthreadobj;

const
  NT = 4;
  K  = 1500;

type
  PByte = ^Byte;
  TIntArr = array of Integer;
  TStrArr = array of AnsiString;

  TNode = class
  public
    a, b: Int64;
    name: AnsiString;
  end;

var
  errors: Integer;

type
  TChurn = class(TThread)
  public
    Tag: Integer;
  protected
    procedure Execute; override;
  end;

procedure TChurn.Execute;
var
  j, i, n: Integer;
  s: AnsiString;
  ia: TIntArr;
  sa: TStrArr;
  node: TNode;
  p: Pointer;
  pb: PByte;
  ch: Char;
  bad: Boolean;
  ignore: Int64;
begin
  ch := Chr(Ord('a') + Tag);
  for j := 1 to K do
  begin
    bad := False;

    { managed AnsiString: grow by concat, then SetLength shrink }
    s := '';
    for i := 1 to 40 do s := s + ch;
    SetLength(s, 25);
    if Length(s) <> 25 then bad := True;
    for i := 1 to 25 do
      if s[i] <> ch then bad := True;

    { dynamic array of Integer: grow, fill, shrink, verify }
    n := 16 + (j mod 32);
    SetLength(ia, n);
    for i := 0 to n - 1 do ia[i] := Tag * 100000 + i;
    SetLength(ia, 10);
    for i := 0 to 9 do
      if ia[i] <> Tag * 100000 + i then bad := True;
    SetLength(ia, 0);

    { dynamic array of AnsiString: managed elements }
    SetLength(sa, 6);
    for i := 0 to 5 do sa[i] := s + ch;
    for i := 0 to 5 do
      if (Length(sa[i]) <> 26) or (sa[i][26] <> ch) then bad := True;
    SetLength(sa, 0);

    { class instance }
    node := TNode.Create;
    node.a := Tag;
    node.b := j;
    node.name := s;
    if (node.a <> Tag) or (node.b <> j) or (node.name[1] <> ch) then bad := True;
    node.Free;

    { raw memory: GetMem -> fill -> ReallocMem grow -> verify -> FreeMem }
    GetMem(p, 64);
    pb := PByte(p);
    for i := 0 to 63 do pb[i] := Byte(Tag);
    ReallocMem(p, 192);
    pb := PByte(p);
    for i := 0 to 63 do
      if pb[i] <> Byte(Tag) then bad := True;
    FreeMem(p);

    if bad then ignore := __pxxatomic_add(@errors, 1);
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
  if errors = 0 then writeln('HEAP MIXED OK') else writeln('HEAP MIXED FAIL');
end.
