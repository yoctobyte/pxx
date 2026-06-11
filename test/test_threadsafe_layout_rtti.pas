{$define PXX_MANAGED_STRING}
program test_threadsafe_layout_rtti;

{$THREADSAFE ON}

type
  PthreadT = QWord;
  PPthreadT = ^PthreadT;

  TPayload = record
    Name: AnsiString;
    Extra: AnsiString;
  end;

  TBox = record
    LabelText: AnsiString;
    Payload: TPayload;
  end;

function pthread_create(thread: PPthreadT; attr: Pointer; start_routine: Pointer; arg: Pointer): Integer; cdecl; external 'libpthread.so.0';
function pthread_join(thread: PthreadT; retval: Pointer): Integer; cdecl; external 'libpthread.so.0';
procedure usleep(usec: Cardinal); cdecl; external 'libc.so.6';

var
  SharedBox: TBox;
  SharedGrid: array of array of AnsiString;

procedure Check(code: Integer; ok: Boolean);
begin
  if not ok then Halt(code);
end;

function Worker(arg: Pointer): Pointer; cdecl;
var
  i: Integer;
  localBox: TBox;
  otherBox: TBox;
  localGrid: array of array of AnsiString;
begin
  for i := 1 to 2000 do
  begin
    localBox := SharedBox;
    Check(11, localBox.LabelText = 'shared label');
    Check(12, localBox.Payload.Name = 'shared payload');
    Check(13, localBox.Payload.Extra = 'extra field');

    otherBox := localBox;
    otherBox.Payload.Name := 'worker';
    Check(14, localBox.Payload.Name = 'shared payload');
    Check(15, otherBox.Payload.Name = 'worker');
    Check(16, SharedBox.Payload.Name = 'shared payload');

    localGrid := SharedGrid;
    localGrid[0][0] := 'changed';
    Check(17, SharedGrid[0][0] = 'root');
    Check(18, localGrid[0][0] = 'changed');

    if (i mod 64) = 0 then usleep(1);
  end;
  Result := nil;
end;

var
  t1, t2, t3, t4: PthreadT;
begin
  SharedBox.LabelText := 'shared label';
  SharedBox.Payload.Name := 'shared payload';
  SharedBox.Payload.Extra := 'extra field';

  SetLength(SharedGrid, 1);
  SetLength(SharedGrid[0], 1);
  SharedGrid[0][0] := 'root';

  Check(21, pthread_create(@t1, nil, @Worker, nil) = 0);
  Check(22, pthread_create(@t2, nil, @Worker, nil) = 0);
  Check(23, pthread_create(@t3, nil, @Worker, nil) = 0);
  Check(24, pthread_create(@t4, nil, @Worker, nil) = 0);

  pthread_join(t1, nil);
  pthread_join(t2, nil);
  pthread_join(t3, nil);
  pthread_join(t4, nil);

  Check(31, SharedBox.Payload.Name = 'shared payload');
  Check(32, SharedBox.Payload.Extra = 'extra field');
  Check(33, SharedGrid[0][0] = 'root');
  writeln('threadsafe layout ok');
end.
