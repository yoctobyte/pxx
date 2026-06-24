program lib_dns_async;
{ End-to-end async DNS over the coroutine reactor (feature-own-net-http-lib):
  a loopback UDP DNS server coroutine answers a canned A record; a client
  coroutine resolves through DnsQueryAAsync. Both run on one thread, reactor-
  driven — proves async UDP + the DNS wire round-trip without external network. }
uses scheduler, platform, dns_wire_core, dns_async;

const PORT = 28766;

var
  gRcode: Integer;
  gCount: Integer;
  gIp:    LongWord;
  gServerDone: Boolean;

procedure ServerCo(arg: Pointer);
var
  sock: Integer; rc: Integer;
  qbuf: array[0..1535] of Byte;
  resp: array[0..1599] of Byte;
  n: Int64; fromAddr: LongWord; fromPort: Integer;
  i, qlen, off: Integer;
begin
  sock := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  rc := PalBindIpv4(sock, PAL_NET_IP_LOOPBACK, PORT);
  rc := PalSetSocketNonBlocking(sock, 1);

  WaitReadable(sock);
  n := PalRecvFromIpv4(sock, @qbuf[0], 1536, fromAddr, fromPort);
  qlen := Integer(n);

  { Echo the query as the response prefix (keeps the id + question), then flip
    to an answer: QR=1, RA=1, RCODE=0, ANCOUNT=1, append one A record = 1.2.3.4. }
  for i := 0 to qlen - 1 do resp[i] := qbuf[i];
  resp[2] := $81;            { QR=1, Opcode=0, AA=0, TC=0, RD=1 }
  resp[3] := $80;            { RA=1, RCODE=0 }
  resp[6] := $00; resp[7] := $01;   { ANCOUNT = 1 }

  off := qlen;
  resp[off]   := $C0; resp[off+1] := $0C;   { name -> pointer to offset 12 }
  resp[off+2] := $00; resp[off+3] := $01;   { TYPE  A }
  resp[off+4] := $00; resp[off+5] := $01;   { CLASS IN }
  resp[off+6] := $00; resp[off+7] := $00;
  resp[off+8] := $00; resp[off+9] := $3C;   { TTL = 60 }
  resp[off+10] := $00; resp[off+11] := $04; { RDLENGTH = 4 }
  resp[off+12] := 1; resp[off+13] := 2; resp[off+14] := 3; resp[off+15] := 4;

  rc := Integer(PalSendToIpv4(sock, @resp[0], off + 16, fromAddr, fromPort));
  rc := PalSocketClose(sock);
  gServerDone := True;
end;

procedure ClientCo(arg: Pointer);
var ips: TDnsIpv4Array; cnt: Integer;
begin
  cnt := 0;
  gRcode := DnsQueryAAsync(PAL_NET_IP_LOOPBACK, PORT, 'test.local', ips, cnt);
  gCount := cnt;
  if cnt > 0 then gIp := ips[0];
end;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

begin
  gRcode := -999; gCount := 0; gIp := 0; gServerDone := False;
  Spawn(@ServerCo, nil);
  Spawn(@ClientCo, nil);
  RunUntilDone;

  SayBool('server-done', gServerDone);
  SayBool('rcode', gRcode = 0);
  SayBool('count', gCount = 1);
  SayBool('ip', gIp = $01020304);   { 1.2.3.4 host byte order }
end.
