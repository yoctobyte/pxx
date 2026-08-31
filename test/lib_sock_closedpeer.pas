program lib_sock_closedpeer;
{ A send to a socket whose peer has closed must return an error, not kill the
  process with SIGPIPE. Regression test for
  bug-b-fpsend-to-a-closed-peer-kills-the-process-msg-nosignal-is-never-passed:
  PalSend used write(2), which has no flags argument, so MSG_NOSIGNAL could not
  be passed and every closed-peer send died with exit 141.

  There is no assertion to write for the failure: the process is killed by the
  signal, so the harness sees a missing line rather than a wrong one. Hence the
  final 'survived' line — it can only be printed by a process that lived. }
uses sockets, sysutils, platform;

function OkStr(b: Boolean): string;
begin
  if b then OkStr := 'ok' else OkStr := 'FAIL';
end;

{ A connected socket whose peer has gone away. Returns the still-open local end. }
function DeadPeerSocket: cint;
var
  srv, cli, conn: cint;
  sa, peer: TInetSockAddr;
  slen: TSocklen;
  one, i: Integer;
begin
  Result := -1;
  srv := fpSocket(AF_INET, SOCK_STREAM, 0);
  if srv < 0 then Exit;
  one := 1;
  fpSetSockOpt(srv, SOL_SOCKET, SO_REUSEADDR, @one, SizeOf(one));
  sa.sin_family := AF_INET;
  sa.sin_port := htons(0);            { let the kernel pick — no fixed port, no collisions }
  sa.sin_addr.s_addr := htonl(INADDR_LOOPBACK);
  for i := 0 to 7 do sa.sin_zero[i] := 0;
  if fpBind(srv, @sa, SizeOf(sa)) < 0 then Exit;
  if fpListen(srv, 1) < 0 then Exit;
  slen := SizeOf(sa);
  if fpGetSockName(srv, @sa, @slen) < 0 then Exit;
  cli := fpSocket(AF_INET, SOCK_STREAM, 0);
  if cli < 0 then Exit;
  peer := sa;
  peer.sin_addr.s_addr := htonl(INADDR_LOOPBACK);
  if fpConnect(cli, @peer, SizeOf(peer)) < 0 then Exit;
  slen := SizeOf(sa);
  conn := fpAccept(srv, @sa, @slen);
  if conn < 0 then Exit;
  fpShutdown(cli, 2);
  PalSocketClose(cli);
  PalSocketClose(srv);
  Result := conn;
end;

{ Send until the error surfaces. The FIRST send succeeds — the bytes go into the
  socket buffer before the peer's RST is processed — so a single send proves
  nothing either way; it is the second and later ones that used to die. }
function SendsUntilError(fd: cint; useSendTo: Boolean): Boolean;
var
  buf: array[0..63] of Byte;
  dst: TInetSockAddr;
  i, tries: Integer;
  n: Int64;
begin
  Result := False;
  for i := 0 to 63 do buf[i] := 65;
  dst.sin_family := AF_INET;
  dst.sin_port := htons(9);
  dst.sin_addr.s_addr := htonl(INADDR_LOOPBACK);
  for i := 0 to 7 do dst.sin_zero[i] := 0;
  for tries := 1 to 40 do
  begin
    if useSendTo then
      n := fpSendTo(fd, @buf[0], 64, 0, @dst, SizeOf(dst))
    else
      n := fpSend(fd, @buf[0], 64, 0);
    if n < 0 then begin Result := True; Exit; end;
    Sleep(20);
  end;
end;

var
  fd: cint;
  okSend, okSendTo, okLive: Boolean;
  a, b: cint;
  sa2: TInetSockAddr;
  slen2: TSocklen;
  srv2, cli2: cint;
  one2, i2: Integer;
  tx, rx: array[0..15] of Byte;
begin
  fd := DeadPeerSocket;
  okSend := (fd >= 0) and SendsUntilError(fd, False);
  if fd >= 0 then PalSocketClose(fd);
  WriteLn('send=', OkStr(okSend));

  fd := DeadPeerSocket;
  okSendTo := (fd >= 0) and SendsUntilError(fd, True);
  if fd >= 0 then PalSocketClose(fd);
  WriteLn('sendto=', OkStr(okSendTo));

  { Control: the send path still delivers on a HEALTHY socket. Without this the
    test above passes trivially if send were broken outright. }
  okLive := False;
  srv2 := fpSocket(AF_INET, SOCK_STREAM, 0);
  one2 := 1;
  fpSetSockOpt(srv2, SOL_SOCKET, SO_REUSEADDR, @one2, SizeOf(one2));
  sa2.sin_family := AF_INET;
  sa2.sin_port := htons(0);
  sa2.sin_addr.s_addr := htonl(INADDR_LOOPBACK);
  for i2 := 0 to 7 do sa2.sin_zero[i2] := 0;
  if (fpBind(srv2, @sa2, SizeOf(sa2)) = 0) and (fpListen(srv2, 1) = 0) then
  begin
    slen2 := SizeOf(sa2);
    fpGetSockName(srv2, @sa2, @slen2);
    cli2 := fpSocket(AF_INET, SOCK_STREAM, 0);
    if fpConnect(cli2, @sa2, SizeOf(sa2)) = 0 then
    begin
      slen2 := SizeOf(sa2);
      a := fpAccept(srv2, @sa2, @slen2);
      for i2 := 0 to 15 do begin tx[i2] := Byte(i2 + 7); rx[i2] := 0; end;
      if fpSend(a, @tx[0], 16, 0) = 16 then
        if fpRecv(cli2, @rx[0], 16, 0) = 16 then
        begin
          okLive := True;
          for i2 := 0 to 15 do if rx[i2] <> tx[i2] then okLive := False;
        end;
      b := a;
      PalSocketClose(b);
      PalSocketClose(cli2);
    end;
  end;
  PalSocketClose(srv2);
  WriteLn('live=', OkStr(okLive));

  { Reached only if no send raised SIGPIPE. }
  WriteLn('survived');
end.
