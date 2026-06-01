program test_multithreading;

{$THREADSAFE ON}

type
  PthreadT = QWord;
  PPthreadT = ^PthreadT;

function pthread_create(thread: PPthreadT; attr: Pointer; start_routine: Pointer; arg: Pointer): Integer; cdecl; external 'libpthread.so.0';
function pthread_join(thread: PthreadT; retval: Pointer): Integer; cdecl; external 'libpthread.so.0';
procedure usleep(usec: Cardinal); cdecl; external 'libc.so.6';

function ThreadFunc(arg: Pointer): Pointer; cdecl;
var
  p: ^Int64;
  i: Integer;
begin
  for i := 1 to 200 do
  begin
    p := GetMem(8);
    p^ := i * 100;
    if i mod 50 = 0 then write('.');
    usleep(10);
    FreeMem(p);
  end;
  Result := nil;
end;

var
  t1, t2, t3, t4: PthreadT;
  res1, res2, res3, res4: Integer;
begin
  writeln('starting main program');
  res1 := pthread_create(@t1, nil, @ThreadFunc, nil);
  writeln('thread 1 create res: ', res1);
  res2 := pthread_create(@t2, nil, @ThreadFunc, nil);
  writeln('thread 2 create res: ', res2);
  res3 := pthread_create(@t3, nil, @ThreadFunc, nil);
  writeln('thread 3 create res: ', res3);
  res4 := pthread_create(@t4, nil, @ThreadFunc, nil);
  writeln('thread 4 create res: ', res4);

  writeln('joining thread 1');
  pthread_join(t1, nil);
  writeln('joining thread 2');
  pthread_join(t2, nil);
  writeln('joining thread 3');
  pthread_join(t3, nil);
  writeln('joining thread 4');
  pthread_join(t4, nil);

  writeln('multithreading test completed successfully');
end.
