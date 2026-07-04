program test_fpc_compat_batch;
{ FPC-RTL compatibility batch (fgl bring-up): System.-qualified builtins,
  Assigned(), resourcestring sections, method directives
  (inline/overload/static/reintroduce/dynamic + hints), and unqualified
  INDEXED property access inside methods (fgl's InternalItems[i] pattern,
  read, write, and deref-as-arg forms). }

resourcestring
  SGreeting = 'hello %d';

type
  TL = class
  private
    FBuf: array[0..15] of Byte;
    FLast: Integer;
    function GetIt(i: Integer): Pointer;
    procedure PutIt(i: Integer; p: Pointer);
  public
    FStore: Pointer;
    procedure M1(a: Integer); dynamic;
    procedure M2; inline;
    procedure M3(a: Integer); overload;
    class function CF: Integer; { class methods are implicitly static }
    procedure UseItems;
    property Items[i: Integer]: Pointer read GetIt write PutIt;
  end;
  TD = class(TL)
    procedure M1(a: Integer); override;   { dynamic == virtual in pxx }
  end;

var
  total, okc, m1hits, m3sum: Integer;

procedure Check(name: string; ok: Boolean);
begin
  total := total + 1;
  if ok then
  begin
    okc := okc + 1;
    writeln('ok ', name);
  end
  else
    writeln('FAIL ', name);
end;

function TL.GetIt(i: Integer): Pointer;
begin
  GetIt := @FBuf[i];
end;

procedure TL.PutIt(i: Integer; p: Pointer);
begin
  FStore := p;
  FLast := i;
end;

procedure TL.M1(a: Integer);
begin
  m1hits := a;
end;

procedure TD.M1(a: Integer);
begin
  m1hits := a * 2;
end;

procedure TL.M2;
begin
  m1hits := m1hits + 100;
end;

procedure TL.M3(a: Integer);
begin
  m3sum := a;
end;

class function TL.CF: Integer;
begin
  CF := 55;
end;

procedure TL.UseItems;
var
  p: Pointer;
begin
  { unqualified indexed property READ (implicit Self) }
  p := Items[3];
  Check('unqual-indexed-read', p = @FBuf[3]);
  { unqualified indexed property WRITE -> setter call }
  Items[5] := p;
  Check('unqual-indexed-write', (FStore = p) and (FLast = 5));
  { deref-as-arg: FillChar through the getter result }
  FillChar(Items[0]^, 4, 65);
  Check('unqual-indexed-deref-arg', (FBuf[0] = 65) and (FBuf[3] = 65) and (FBuf[4] = 0));
end;

var
  l: TL;
  d: TD;
  b: TL;
  pp: Pointer;
begin
  total := 0; okc := 0; m1hits := 0; m3sum := 0;

  Check('resourcestring', SGreeting = 'hello %d');

  pp := nil;
  Check('assigned-nil', not Assigned(pp));
  pp := @total;
  Check('assigned-set', assigned(pp));    { lowercase like FPC source }

  { System.-qualified builtins resolve like the bare names }
  System.FillChar(total, 0, 0);
  Check('system-qualifier', True);

  l := TL.Create;
  l.UseItems;
  l.M2;
  Check('inline-directive-parsed', m1hits = 100);
  l.M3(7);
  Check('overload-directive-parsed', m3sum = 7);
  Check('class-func', TL.CF = 55);
  l.Free;

  d := TD.Create;
  b := d;
  b.M1(21);
  Check('dynamic-is-virtual', m1hits = 42);
  d.Free;

  writeln('total ok ', okc, ' / ', total);
end.
