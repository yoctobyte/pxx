program WasiDiffSlice;
{ The two WASI capability models, asked the same questions and compared against
  EACH OTHER.

  There are two implementations of preopen resolution and rights in this tree:

    * compiler/builtin/wasibackend.pas       — reached here through the
      `sysopen` / `sysread` / `sysclose` INTRINSICS, which is the path the
      wasm-hosted compiler itself takes;
    * lib/rtl/platform/wasi/platform_backend.pas — reached here through
      `PalOpen` / `PalRead` / `PalClose`, which is the path every ordinary
      program takes.

  Both are in THIS program at once, which is not incidental: it is the measured
  reason a shared `{$i}` include cannot unify them (it would define every
  symbol twice), and this slice is the standing proof that the co-occurrence is
  real rather than theoretical.

  WHAT THIS CAN AND CANNOT CATCH — state it plainly, because the limit is
  structural and it is easy to over-trust a green tick here.

  CAN catch: DIVERGENCE. One model opening a path the other refuses, or reading
  different bytes from the same file. That is the failure mode two copies drift
  into, and it is silent in every other check because each path is exercised
  alone.

  CANNOT catch: a defect that is IDENTICAL IN BOTH. The copies are each other's
  only oracle here, so a bug copied at birth makes them agree and this slice
  goes green. That is not hypothetical — the u64 alignment bug
  (bug-wasm-hosted-compiler-segfaults-the-host-after-a-successful-parse) was
  exactly that shape: present in both, agreed on by both, and caught only by a
  strict HOST refusing the module. `check_align.sh` is the check for that class;
  this one is for the other.

  THE REFUSALS ARE THE POINT, not the accepts. A capability model's whole job is
  saying no: `..` climbing out of the preopen, an absolute path to something the
  host never granted, an empty path. Two models that agree on what they OPEN and
  disagree on what they REFUSE differ in exactly the direction that matters, and
  a test that only opened files would report them identical.

  Native is NOT the oracle. On posix, `../escape.txt` is an ordinary readable
  path; under WASI it must be refused because no preopen covers it. The two wasm
  implementations are each other's oracle, and the check asserts they agree —
  plus that BOTH outcomes actually occurred, since "everything refused" would
  make agreement trivially true. }

uses platform;

const
  O_RDONLY = 0;

var
  probePath: AnsiString;
  ibuf, pbuf: array[0..63] of Byte;
  accepts, refuses, disagreements: Integer;

{ The intrinsic path -> PXXWasiOpen in wasibackend.pas. `sysopen` requires a
  string VARIABLE as its first argument, hence the var parameter. }
function OpenIntrinsic(var p: AnsiString): Integer;
begin
  OpenIntrinsic := sysopen(p, O_RDONLY);
end;

{ The PAL path -> PalBackendOpen in platform_backend.pas. }
function OpenPal(const p: AnsiString): Integer;
begin
  OpenPal := PalOpen(PChar(p), O_RDONLY, 0);
end;

function Verdict(fd: Integer): AnsiString;
begin
  if fd >= 0 then Verdict := 'ACCEPT' else Verdict := 'REFUSE';
end;

{ One question, asked of both models. Reports each verdict, whether they agree,
  and — when both accepted — whether they read the same bytes, because agreeing
  to open a file and then disagreeing about its contents is still divergence. }
procedure Probe(const name: AnsiString; const p: AnsiString);
var
  ifd, pfd, i: Integer;
  inr, pnr: Int64;
  sameBytes: Boolean;
begin
  probePath := p;
  ifd := OpenIntrinsic(probePath);
  pfd := OpenPal(p);

  Write(name, ' intrinsic=', Verdict(ifd), ' pal=', Verdict(pfd));

  if (ifd >= 0) = (pfd >= 0) then
    Write(' agree=TRUE')
  else
  begin
    Write(' agree=FALSE');
    disagreements := disagreements + 1;
  end;

  if ifd >= 0 then accepts := accepts + 1 else refuses := refuses + 1;

  if (ifd >= 0) and (pfd >= 0) then
  begin
    for i := 0 to 63 do begin ibuf[i] := 0; pbuf[i] := 0; end;
    inr := sysread(ifd, ibuf, 64);
    pnr := PalRead(pfd, @pbuf[0], 64);
    sameBytes := (inr = pnr);
    if sameBytes then
      for i := 0 to 63 do
        if ibuf[i] <> pbuf[i] then sameBytes := False;
    { The COUNT is printed only when it is a real byte count. Reading a
      DIRECTORY is an error on both models and both hosts, but the errno they
      map it to is the HOST's choice -- wasmtime says -9, node says -1 -- and
      printing it would make this slice's output host-dependent for no gain.
      What is being asserted is that the two MODELS agree, which they do either
      way. (Same trap as align_slice's monotonic clock: assert what is promised,
      not what one host happens to return.) }
    if sameBytes and (inr >= 0) then
      Write(' bytes=SAME n=', inr)
    else if sameBytes then
      Write(' bytes=SAME n=ERR')
    else
    begin
      Write(' bytes=DIFFER');
      disagreements := disagreements + 1;
    end;
  end;

  Writeln;
  if ifd >= 0 then sysclose(ifd);
  if pfd >= 0 then PalClose(pfd);
end;

begin
  accepts := 0; refuses := 0; disagreements := 0;

  { --- should be ACCEPTED by both ----------------------------------------- }
  Probe('plain    ', 'wd_data.txt');
  Probe('dotslash ', './wd_data.txt');
  Probe('nested   ', 'wd_sub/wd_nested.txt');

  { --- should be REFUSED by both; these are the capability model's job ----- }
  Probe('missing  ', 'wd_absent.txt');
  Probe('escape   ', '../wd_outside.txt');
  Probe('deepesc  ', 'wd_sub/../../wd_outside.txt');
  Probe('abs-etc  ', '/etc/passwd');
  Probe('empty    ', '');

  { --- whatever the answer is, both must give the SAME one ---------------- }
  Probe('adir     ', 'wd_sub');

  Writeln('accepts=', accepts);
  Writeln('refuses=', refuses);
  Writeln('disagreements=', disagreements);
end.
