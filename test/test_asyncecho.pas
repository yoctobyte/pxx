program TestAsyncEcho;
{ Async TCP echo over the scheduler + reactor (x86-64). One thread, no blocking:
  a server coroutine accepts two connections and spawns an echo coroutine per
  connection; two client coroutines connect, send "ping<id>", and verify the
  echo. Results are stored per client and printed in id order at the end, so the
  output is deterministic regardless of how the reactor interleaves the work. }
uses scheduler, asyncnet;

const
  PORT = 47891;

var
  results: array[0..3] of Integer;   { 1 = echo matched, 2 = mismatch }

procedure EchoConn(arg: Pointer);
var fd: Integer; buf: array[0..63] of Byte; n: Int64;
begin
  fd := Integer(arg);
  n := TcpRecv(fd, @buf[0], 64);
  if n > 0 then TcpSend(fd, @buf[0], n);
  TcpClose(fd);
end;

procedure Server(arg: Pointer);
var lfd, cfd, i: Integer;
begin
  lfd := TcpListen(PORT);
  for i := 1 to 2 do
  begin
    cfd := TcpAccept(lfd);
    Spawn(@EchoConn, Pointer(cfd));
  end;
  TcpClose(lfd);
end;

procedure Client(arg: Pointer);
var fd, id, i, ok: Integer; msg: array[0..4] of Byte; buf: array[0..63] of Byte; n: Int64;
begin
  id := Integer(arg);
  fd := TcpConnect(PORT);
  msg[0] := Ord('p'); msg[1] := Ord('i'); msg[2] := Ord('n'); msg[3] := Ord('g');
  msg[4] := Ord('0') + id;
  TcpSend(fd, @msg[0], 5);
  n := TcpRecv(fd, @buf[0], 64);
  ok := 1;
  if n <> 5 then ok := 2
  else
    for i := 0 to 4 do
      if buf[i] <> msg[i] then ok := 2;
  results[id] := ok;
  TcpClose(fd);
end;

begin
  Spawn(@Server, nil);
  Spawn(@Client, Pointer(1));
  Spawn(@Client, Pointer(2));
  RunUntilDone;
  if results[1] = 1 then writeln('client 1 ok') else writeln('client 1 FAIL');
  if results[2] = 1 then writeln('client 2 ok') else writeln('client 2 FAIL');
  writeln('done');
end.
