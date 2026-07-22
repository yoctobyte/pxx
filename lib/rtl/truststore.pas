{ SPDX-License-Identifier: Zlib }
unit truststore;
{ System trust store: load the platform's CA anchors and validate a server's
  certificate chain against them.

  This is the difference between "verifies a CA I handed it" — which is all the
  from-scratch TLS 1.3 client could do before — and "verifies a real public
  server". The chain is walked leaf -> intermediates -> a root that is IN THE
  STORE; a chain that terminates anywhere else is rejected no matter how
  internally consistent it is.

  Sources, in the order LoadSystemTrust tries them:
    /etc/ssl/certs/ca-certificates.crt     Debian/Ubuntu, one concatenated PEM
    /etc/pki/tls/certs/ca-bundle.crt       Fedora/RHEL
    /etc/ssl/cert.pem                      Alpine, and the BSDs
  The `/etc/ssl/certs/*.pem` + <hash>.0 directory form is not read; every
  mainstream distribution also ships one of the bundles above, and the directory
  form needs a hash index to be worth anything.

  Trust is the whole point of this unit, so it errs toward refusing:
    - a store that could not be read yields an EMPTY store, and an empty store
      validates NOTHING (it never silently degrades to "accept anything")
    - a certificate in the bundle that fails to parse is skipped, not fatal —
      real bundles do carry the occasional cert we cannot parse, and one bad
      anchor must not disarm the other ~150
    - roots are indexed by raw Subject DN bytes, so issuer lookup is an exact
      byte comparison, not a normalised-string guess

  NOT DONE, and deliberately so (see the ticket): basicConstraints CA flag,
  keyUsage, and path-length are not enforced yet, so a leaf certificate that a
  trusted CA signed could itself act as an intermediate. That is a real gap and
  the next hardening step. Revocation (CRL/OCSP) is out of scope entirely.

  Track B (lib/rtl). Consumes x509.pas; no compiler dependency. }

interface

uses x509;

const
  { A bundle holds a few hundred anchors; the cap is a guard against a runaway
    or hostile file rather than a real limit. }
  MAX_ROOTS = 1024;

  { Longest chain we will walk: leaf + intermediates + root. Bounded so a
    cyclic or adversarial certificate_list cannot loop forever. }
  MAX_CHAIN = 10;

type
  TTrustStore = record
    Count:    Integer;
    Certs:    array[0..MAX_ROOTS - 1] of TCert;
    { Subjects[i] mirrors Certs[i].Subject — kept alongside so issuer lookup is
      a plain string compare without touching the parsed record. }
    Subjects: array[0..MAX_ROOTS - 1] of AnsiString;
    Source:   AnsiString;   { which file it came from; '' if none was readable }
  end;

{ Diagnostics for the loader path (used by the devtest to say WHERE it failed
  rather than just "no". }
function TrustReadFile(const path: AnsiString; var content: AnsiString): Boolean;

{ Split a concatenated PEM text into its DER blocks. Returns the number found
  and fills `ders`; anything outside a BEGIN/END CERTIFICATE pair is ignored, so
  the human-readable headers real bundles carry are harmless. }
function PemSplit(const pem: AnsiString; var ders: array of AnsiString): Integer;

{ Read and parse a concatenated-PEM bundle. Unparseable entries are skipped. }
function LoadTrustFile(const path: AnsiString; var store: TTrustStore): Boolean;

{ Try the known system bundle locations in order. An unreadable store is not an
  error here — the caller gets an empty store, which trusts nothing. }
function LoadSystemTrust(var store: TTrustStore): Boolean;

{ Find a root by exact Subject DN. Returns its index, or -1. }
function TrustFindBySubject(const store: TTrustStore; const subject: AnsiString): Integer;

{ Validate a server's certificate_list against the store.

  `certList[0]` is the leaf, the rest are intermediates in any order (the TLS
  spec says sender-ordered, but real servers get this wrong, so order is not
  assumed). Every link is checked with X509VerifyChain — issuer name link,
  signature, and validity at nowStr — and the walk must terminate at a cert
  whose Subject is in the store AND whose signature the store's copy verifies.
  The leaf must additionally match `host` unless host is ''. }
function VerifyServerChain(const store: TTrustStore;
                           const certList: array of AnsiString;
                           certCount: Integer;
                           const nowStr, host: AnsiString): Boolean;

implementation

uses base64, hashing, platform;

const
  PEM_BEGIN = '-----BEGIN CERTIFICATE-----';
  PEM_END   = '-----END CERTIFICATE-----';

{ Read a whole file through the PAL. Returns '' when it cannot be read — the
  caller distinguishes "empty" from "absent" via the Boolean. }
function TrustReadFile(const path: AnsiString; var content: AnsiString): Boolean;
var fd, n: Integer; buf: array[0..8191] of Byte; chunk: AnsiString; i: Integer;
begin
  content := '';
  fd := PalOpen(PChar(path), PAL_OPEN_READ, 0);
  if fd < 0 then
  begin
    TrustReadFile := False;
    Exit;
  end;
  repeat
    n := PalRead(fd, @buf[0], SizeOf(buf));
    if n > 0 then
    begin
      SetLength(chunk, n);
      for i := 0 to n - 1 do chunk[i + 1] := Chr(buf[i]);
      content := content + chunk;
    end;
  until n <= 0;
  PalClose(fd);
  TrustReadFile := True;
end;

{ Strip whitespace so the base64 decoder sees one unbroken string — PEM wraps
  at 64 columns and may use CRLF. }
function StripWs(const s: AnsiString): AnsiString;
var i: Integer; c: Char; r: AnsiString;
begin
  r := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c <> #10) and (c <> #13) and (c <> ' ') and (c <> #9) then r := r + c;
  end;
  StripWs := r;
end;

function PemSplit(const pem: AnsiString; var ders: array of AnsiString): Integer;
var
  pos, b, e, bodyStart: Integer;
  body, der: AnsiString;
  n: Integer;
begin
  n := 0;
  pos := 1;
  while (pos <= Length(pem)) and (n < Length(ders)) do
  begin
    b := Pos(PEM_BEGIN, Copy(pem, pos, Length(pem) - pos + 1));
    if b = 0 then Break;
    b := pos + b - 1;
    bodyStart := b + Length(PEM_BEGIN);
    e := Pos(PEM_END, Copy(pem, bodyStart, Length(pem) - bodyStart + 1));
    if e = 0 then Break;                 { unterminated block: stop, keep what we have }
    e := bodyStart + e - 1;

    body := StripWs(Copy(pem, bodyStart, e - bodyStart));
    der := Base64DecodeStr(body);
    if der <> '' then
    begin
      ders[n] := der;
      n := n + 1;
    end;
    pos := e + Length(PEM_END);
  end;
  PemSplit := n;
end;

function LoadTrustFile(const path: AnsiString; var store: TTrustStore): Boolean;
var
  pem: AnsiString;
  ders: array[0..MAX_ROOTS - 1] of AnsiString;
  count, i: Integer;
  c: TCert;
begin
  store.Count := 0;
  store.Source := '';
  if not TrustReadFile(path, pem) then
  begin
    LoadTrustFile := False;
    Exit;
  end;

  count := PemSplit(pem, ders);
  for i := 0 to count - 1 do
  begin
    c := X509Parse(ders[i]);
    { A bundle with one cert we cannot parse must not disarm the rest. }
    if not c.Ok then Continue;
    if store.Count >= MAX_ROOTS then Break;
    store.Certs[store.Count] := c;
    store.Subjects[store.Count] := c.Subject;
    store.Count := store.Count + 1;
  end;

  store.Source := path;
  LoadTrustFile := store.Count > 0;
end;

function LoadSystemTrust(var store: TTrustStore): Boolean;
begin
  store.Count := 0;
  store.Source := '';
  if LoadTrustFile('/etc/ssl/certs/ca-certificates.crt', store) then
  begin
    LoadSystemTrust := True;
    Exit;
  end;
  if LoadTrustFile('/etc/pki/tls/certs/ca-bundle.crt', store) then
  begin
    LoadSystemTrust := True;
    Exit;
  end;
  if LoadTrustFile('/etc/ssl/cert.pem', store) then
  begin
    LoadSystemTrust := True;
    Exit;
  end;
  { No bundle found. store.Count is 0, so it trusts nothing — the caller can
    report "no trust store" rather than silently accepting. }
  LoadSystemTrust := False;
end;

function TrustFindBySubject(const store: TTrustStore; const subject: AnsiString): Integer;
var i: Integer;
begin
  TrustFindBySubject := -1;
  if subject = '' then Exit;
  for i := 0 to store.Count - 1 do
    if store.Subjects[i] = subject then
    begin
      TrustFindBySubject := i;
      Exit;
    end;
end;

function VerifyServerChain(const store: TTrustStore;
                           const certList: array of AnsiString;
                           certCount: Integer;
                           const nowStr, host: AnsiString): Boolean;
var
  certs: array[0..MAX_CHAIN - 1] of TCert;
  used:  array[0..MAX_CHAIN - 1] of Boolean;
  n, i, j, steps, rootIdx: Integer;
  cur: TCert;
  advanced: Boolean;
begin
  VerifyServerChain := False;

  { An empty store trusts nothing. Said explicitly so the walk below can never
    "succeed" by finding no anchor to contradict it. }
  if store.Count = 0 then Exit;
  if certCount <= 0 then Exit;

  n := certCount;
  if n > MAX_CHAIN then n := MAX_CHAIN;
  for i := 0 to n - 1 do
  begin
    certs[i] := X509Parse(certList[i]);
    if not certs[i].Ok then Exit;        { a malformed cert in the path is fatal }
    used[i] := False;
  end;

  cur := certs[0];
  used[0] := True;

  { The leaf must be for the host we asked for. Checked before any signature
    work: a name mismatch is fatal regardless of how good the chain is. }
  if host <> '' then
    if not X509HostMatch(cur, host) then Exit;
  if not X509ValidAt(cur, nowStr) then Exit;

  steps := 0;
  while steps < MAX_CHAIN do
  begin
    steps := steps + 1;

    { Anchor reached? `cur`'s issuer is a root we trust. Verify cur against the
      STORE's copy of that root, never against a copy the server supplied. }
    rootIdx := TrustFindBySubject(store, cur.Issuer);
    if rootIdx >= 0 then
      if X509VerifyChain(cur, store.Certs[rootIdx], nowStr, '') then
      begin
        VerifyServerChain := True;
        Exit;
      end;

    { A trusted root sent as the leaf itself (direct, self-signed) also
      validates — but only if the store holds that exact certificate. }
    rootIdx := TrustFindBySubject(store, cur.Subject);
    if rootIdx >= 0 then
      if X509VerifyChain(cur, store.Certs[rootIdx], nowStr, '') then
      begin
        VerifyServerChain := True;
        Exit;
      end;

    { Otherwise step up through an intermediate the server sent. Order is not
      assumed — real servers send these out of order — so the whole unused set
      is searched for one that issued `cur`. }
    advanced := False;
    for j := 0 to n - 1 do
    begin
      if used[j] then Continue;
      if certs[j].Subject <> cur.Issuer then Continue;
      if not X509VerifyChain(cur, certs[j], nowStr, '') then Continue;
      used[j] := True;
      cur := certs[j];
      advanced := True;
      Break;
    end;
    { Nowhere left to go and no anchor found: untrusted. }
    if not advanced then Exit;
  end;
  { Ran past MAX_CHAIN without anchoring — treat as untrusted. }
end;

end.
