program lib_synapse;
{ Synapse hermetic smoke (feature-synapse-compile-check): synacode vectors
  (byte-exact vs FPC) + a blcksock TCP loopback round-trip. No network. }
uses synacode, synautil, blcksock, sysutils;

function ToHex(const s: AnsiString): AnsiString;
const HD: string = '0123456789abcdef';
var j: Integer;
begin
  Result := '';
  for j := 1 to Length(s) do
    Result := Result + HD[(Ord(s[j]) shr 4) + 1] + HD[(Ord(s[j]) and 15) + 1];
end;

procedure CodecChecks;
begin
  writeln('b64=', EncodeBase64('Hello, World!'));
  writeln('b64d=', DecodeBase64('SGVsbG8sIFdvcmxkIQ=='));
  writeln('md5=', ToHex(MD5('abc')));
  writeln('sha1=', ToHex(SHA1('abc')));
  writeln('crc32=', Crc32('123456789'));
  writeln('url=', EncodeURL('a b&c'));
end;

procedure LoopbackCheck;
var
  srv, cli, conn: TTCPBlockSocket;
  line: AnsiString;
begin
  srv := TTCPBlockSocket.Create;
  srv.Bind('127.0.0.1', '0');          { ephemeral port }
  srv.Listen;
  cli := TTCPBlockSocket.Create;
  cli.Connect('127.0.0.1', IntToStr(srv.GetLocalSinPort));
  if srv.CanRead(2000) then
  begin
    conn := TTCPBlockSocket.Create;
    conn.Socket := srv.Accept;
    cli.SendString('ping' + CRLF);
    line := conn.RecvString(2000);
    writeln('srv-got=', line);
    conn.SendString('pong' + CRLF);
    line := cli.RecvString(2000);
    writeln('cli-got=', line);
    conn.Free;
  end
  else
    writeln('accept-timeout');
  cli.Free;
  srv.Free;
end;

begin
  CodecChecks;
  LoopbackCheck;
end.
