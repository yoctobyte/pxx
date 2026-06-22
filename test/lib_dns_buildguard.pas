program lib_dns_buildguard;
{ Adversarial test for DnsBuildQueryA bounds. Before the bufLen guard, a long
  name overflowed the output buffer (no length check at all). Here a 0xCC canary
  fills the buffer past the declared bufLen; a too-long name must return
  DNS_ERR_TOOLONG and leave the canary intact (no write past bufLen). Also checks
  over-long (>63) and empty labels are rejected, and a fitting name still works. }

uses dns_wire_core;

var
  buf: array[0..63] of Byte;
  rc, i: Integer;
  canaryOk: Boolean;
  bigLabel: string;

procedure Show(const tag: string; pass: Boolean);
begin
  if pass then writeln(tag, '=ok') else writeln(tag, '=bad');
end;

begin
  { Canary the whole buffer; tell DnsBuildQueryA only the first 40 bytes are
    available; feed a name whose encoding needs more than 40. }
  for i := 0 to 63 do buf[i] := $CC;
  rc := DnsBuildQueryA('aaaaaaaa.bbbbbbbb.cccccccc.dddddddd', $1, @buf[0], 40);
  Show('toolong', rc = DNS_ERR_TOOLONG);
  canaryOk := True;
  for i := 40 to 63 do
    if buf[i] <> $CC then canaryOk := False;
  Show('no-overflow', canaryOk);

  { A single label longer than 63 bytes. }
  bigLabel := '';
  for i := 1 to 64 do bigLabel := bigLabel + 'a';
  rc := DnsBuildQueryA(bigLabel, $1, @buf[0], 512);
  Show('biglabel', rc = DNS_ERR_MALFORMED);

  { Empty label (double dot). }
  rc := DnsBuildQueryA('a..b', $1, @buf[0], 512);
  Show('emptylabel', rc = DNS_ERR_MALFORMED);

  { Buffer too small even for a short name. }
  rc := DnsBuildQueryA('example.com', $1, @buf[0], 16);
  Show('tinybuf', rc = DNS_ERR_TOOLONG);

  { A name that fits encodes fine. }
  rc := DnsBuildQueryA('a.b', $1, @buf[0], 512);
  Show('fits', rc > 0);
end.
