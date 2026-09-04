program lib_sock_flags;
{ fpSend/fpRecv/fpSendTo/fpRecvFrom FLAGS over the PAL.

  ALL FOUR TOOK `flags' AND NEVER READ IT until 2026-09-04
  (bug-b-fprecv-and-fpsend-silently-discard-their-flags-argument), and the
  observable was a HANG rather than a wrong value: two successive
  fpRecv(..., MSG_PEEK) calls should return the same bytes, but the first
  consumed them and the second waited forever.

  ROW `peek2' IS THE ASSERTION. `peek1' passes whether or not the flag arrives,
  because an ordinary recv also returns 8 bytes; only the second peek separates
  them. Both peeks carry MSG_DONTWAIT as well, so a partially-dropped flag word
  answers instead of blocking -- and the Makefile still runs this under
  `timeout', because a flag word dropped ENTIRELY takes MSG_DONTWAIT with it.

  NO FIXED PORT: bind 0 and read back what the kernel gave, as lib_sockets.pas
  does after two concurrent runs collided on a fixed one. }
uses sockets, platform;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

const
  EAGAIN = 11;   { Linux }
  EINVAL = 22;
  MSG_TRUNC = $20;  { declared by Linux, carried by no PAL backend }

var
  srv, cli, conn: cint;
  a: TInetSockAddr;
  alen: TSocklen;
  sbuf, b1, b2: array[0..7] of Byte;
  i, tries: Integer;
  n: ssize_t;

function Same(const x: array of Byte): Boolean;
var k: Integer;
begin
  Same := True;
  for k := 0 to 7 do if x[k] <> sbuf[k] then Same := False;
end;

{ Peek with MSG_DONTWAIT, retrying while the bytes are still in flight. The
  bound makes "never arrived" a distinct outcome from "arrived and the flag was
  dropped" -- without it the two are one FAIL. }
function PeekOnce(fd: cint; var dst: array of Byte): ssize_t;
var t: Integer; r: ssize_t;
begin
  r := -1;
  for t := 0 to 9999 do
  begin
    r := fpRecv(fd, @dst[0], 8, MSG_PEEK or MSG_DONTWAIT);
    if r >= 0 then break;
    if fpGetErrno <> EAGAIN then break;
  end;
  PeekOnce := r;
end;

begin
  for i := 0 to 7 do sbuf[i] := Byte(65 + i);

  srv := fpSocket(AF_INET, SOCK_STREAM, 0);
  a.sin_family := AF_INET;
  a.sin_port := htons(0);
  a.sin_addr.s_addr := htonl(INADDR_LOOPBACK);
  SayBool('bind', fpBind(srv, @a, SizeOf(TInetSockAddr)) = 0);
  SayBool('listen', fpListen(srv, 4) = 0);
  alen := SizeOf(TInetSockAddr);
  SayBool('sockname', (fpGetSockName(srv, @a, @alen) = 0) and (ntohs(a.sin_port) > 0));

  cli := fpSocket(AF_INET, SOCK_STREAM, 0);
  SayBool('connect', fpConnect(cli, @a, SizeOf(TInetSockAddr)) = 0);
  alen := SizeOf(TInetSockAddr);
  conn := fpAccept(srv, @a, @alen);
  SayBool('accept', conn >= 0);

  { MSG_NOSIGNAL is accepted rather than refused: the PAL sets it on every send
    anyway, so a caller asking for it gets what it asked for. }
  SayBool('send-nosignal', fpSend(conn, @sbuf[0], 8, MSG_NOSIGNAL) = 8);

  for i := 0 to 7 do begin b1[i] := 0; b2[i] := 0; end;
  n := PeekOnce(cli, b1);
  SayBool('peek1', (n = 8) and Same(b1));
  n := PeekOnce(cli, b2);
  SayBool('peek2', (n = 8) and Same(b2));

  for i := 0 to 7 do b2[i] := 0;
  n := fpRecv(cli, @b2[0], 8, 0);
  SayBool('recv-after', (n = 8) and Same(b2));

  { The queue is empty now, and MSG_DONTWAIT must say so rather than block. }
  n := fpRecv(cli, @b2[0], 8, MSG_DONTWAIT);
  SayBool('recv-empty', (n < 0) and (fpGetErrno = EAGAIN));

  { A flag the PAL does not carry is REFUSED, not masked off. Masking is how
    the original bug looked like success. MSG_TRUNC is the one declared flag
    with no PAL counterpart. }
  n := fpRecv(cli, @b2[0], 8, MSG_TRUNC);
  SayBool('recv-unknown-flag', (n < 0) and (fpGetErrno = EINVAL));

  fpShutdown(conn, 2);
  SayBool('close-conn', CloseSocket(conn) = 0);
  SayBool('close-cli', CloseSocket(cli) = 0);
  SayBool('close-srv', CloseSocket(srv) = 0);

  { The datagram pair goes through different PAL entries and had the same
    defect, so it gets its own peek-twice rather than being assumed. }
  srv := fpSocket(AF_INET, SOCK_DGRAM, 0);
  cli := fpSocket(AF_INET, SOCK_DGRAM, 0);
  a.sin_family := AF_INET;
  a.sin_port := htons(0);
  a.sin_addr.s_addr := htonl(INADDR_LOOPBACK);
  SayBool('ubind', fpBind(srv, @a, SizeOf(TInetSockAddr)) = 0);
  alen := SizeOf(TInetSockAddr);
  SayBool('usockname', fpGetSockName(srv, @a, @alen) = 0);
  SayBool('usendto', fpSendTo(cli, @sbuf[0], 8, 0, @a, SizeOf(TInetSockAddr)) = 8);

  for i := 0 to 7 do begin b1[i] := 0; b2[i] := 0; end;
  n := -1;
  for tries := 0 to 9999 do
  begin
    alen := SizeOf(TInetSockAddr);
    n := fpRecvFrom(srv, @b1[0], 8, MSG_PEEK or MSG_DONTWAIT, @a, @alen);
    if n >= 0 then break;
    if fpGetErrno <> EAGAIN then break;
  end;
  SayBool('upeek1', (n = 8) and Same(b1));
  alen := SizeOf(TInetSockAddr);
  n := fpRecvFrom(srv, @b2[0], 8, MSG_PEEK or MSG_DONTWAIT, @a, @alen);
  SayBool('upeek2', (n = 8) and Same(b2));
  for i := 0 to 7 do b2[i] := 0;
  alen := SizeOf(TInetSockAddr);
  n := fpRecvFrom(srv, @b2[0], 8, 0, @a, @alen);
  SayBool('urecv-after', (n = 8) and Same(b2));

  CloseSocket(cli);
  CloseSocket(srv);
end.
