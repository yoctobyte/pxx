program fex;
{$THREADSAFE ON}
type
  PthreadT = QWord;
  PPthreadT = ^PthreadT;
function pthread_create(thread: PPthreadT; attr: Pointer; start_routine: Pointer; arg: Pointer): Integer; cdecl; external 'libpthread.so.0';
function pthread_join(thread: PthreadT; retval: Pointer): Integer; cdecl; external 'libpthread.so.0';

var
  workerOk, mainOk: Integer;

procedure Boom;
begin
  raise 12;
end;

function ThreadFunc(arg: Pointer): Pointer; cdecl;
var i: Integer;
begin
  for i := 1 to 300000 do
  begin
    try
      Boom;
      { must not be reached }
      workerOk := -1000000;
    except
      Inc(workerOk);
    end;
  end;
  ThreadFunc := nil;
end;

var t: PthreadT; i: Integer;
begin
  workerOk := 0; mainOk := 0;
  if pthread_create(@t, nil, @ThreadFunc, nil) <> 0 then
  begin WriteLn('FAIL: pthread_create'); Halt(1); end;
  for i := 1 to 300000 do
  begin
    try
      Boom;
      mainOk := -1000000;
    except
      Inc(mainOk);
    end;
  end;
  pthread_join(t, nil);
  WriteLn('main=', mainOk, ' worker=', workerOk);
  if (mainOk = 300000) and (workerOk = 300000) then WriteLn('FOREIGNEXC OK')
  else WriteLn('FAIL: counts');
end.
