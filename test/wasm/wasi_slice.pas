program WasiSlice;

{ The WASI PAL, implemented: open / read / write / seek / close / sync, the
  three single-path operations, rename, and the clocks.

  What makes this slice worth more than "does writeln to a file work" is the
  set of cases where a WASI backend can differ from a posix one and still look
  fine on one happy path:

    * PATH RESOLUTION. There is no open(2). Every path is resolved against the
      table of directories the host preopened, and the remainder is what the
      host is given. A path under no grant must be ENOENT, and a relative path
      must find the "." grant.
    * ERRNO NUMBERING. WASI's errno list is alphabetical and Linux's is not,
      so WASI 2 is EACCES where Linux 2 is ENOENT. Passing one through as the
      other turns every missing file into a permission error — and both are
      non-zero, so anything that only checks "did it fail" agrees.
    * RIGHTS. An fd carries the rights it was opened with and refuses anything
      else with ENOTCAPABLE. Too few rights gives an fd that OPENS and then
      fails on first use, which a test that only opens will not see.
    * APPEND, TRUNCATE and SEEK, which are flags and offsets rather than
      capabilities, and are where a mapping table gets silently transposed. }

uses platform;

{ Deliberately NOT `uses SysUtils`: this slice's subject is the PAL, and the
  fewer unrelated bodies it drags in, the more a refusal here means what it
  says. Dec3 is four lines and replaces the only thing SysUtils was here for.

  (It also once looked as if SysUtils were the CAUSE of a trap in this slice,
  and it was not — the trap survived removing it, and the real cause was a
  string literal passed as a PChar. A comment that names the wrong cause is
  worse than none, so this one names only what is true: the dependency is
  dropped for size, not to dodge a bug.) }
function Dec3(v: Integer): string;
var d: string;
begin
  if v = 0 then begin Dec3 := '0'; Exit; end;
  d := '';
  while v > 0 do
  begin
    d := Chr(48 + (v mod 10)) + d;
    v := v div 10;
  end;
  Dec3 := d;
end;


var
  f: Text;
  s: string;
  i, n, h: Integer;
  buf: array[0..31] of Byte;

begin
  { --- write, close, read back --- }
  Assign(f, 'a.txt');
  Rewrite(f);
  writeln(f, 'first');
  writeln(f, 'second');
  Close(f);

  Assign(f, 'a.txt');
  Reset(f);
  n := 0;
  while not Eof(f) do
  begin
    readln(f, s);
    n := n + 1;
    writeln(n, ': ', s);
  end;
  Close(f);

  { --- TRUNCATE: a second Rewrite must not leave the old tail behind --- }
  Assign(f, 'a.txt');
  Rewrite(f);
  writeln(f, 'x');
  Close(f);
  Assign(f, 'a.txt');
  Reset(f);
  n := 0;
  while not Eof(f) do begin readln(f, s); n := n + 1; end;
  Close(f);
  writeln('after rewrite, lines=', n, ' last=[', s, ']');

  { --- APPEND: Append must find the end, not offset zero --- }
  Assign(f, 'a.txt');
  Append(f);
  writeln(f, 'y');
  Close(f);
  Assign(f, 'a.txt');
  Reset(f);
  s := '';
  while not Eof(f) do
  begin
    readln(f, s);
    write(s);
  end;
  Close(f);
  writeln(' <- appended');

  { --- the PAL directly: byte-exact writes and a SEEK back to the start.
        Going through `platform` rather than through a Text file is the point —
        it is these eight entry points the backend implements, and the Text
        layer above them would hide a wrong byte count behind its own
        buffering. --- }
  h := PalOpen('b.bin', PAL_OPEN_WRITE or PAL_OPEN_CREATE or PAL_OPEN_TRUNC, 420);
  writeln('open-for-write ok=', h >= 0);
  for i := 0 to 9 do buf[i] := Byte(i * 7);
  writeln('wrote=', PalWrite(h, @buf[0], 10));
  writeln('flush=', PalFlush(h));
  writeln('close=', PalClose(h));

  h := PalOpen('b.bin', PAL_OPEN_READ, 0);
  for i := 0 to 31 do buf[i] := 0;
  writeln('read=', PalRead(h, @buf[0], 10));
  s := '';
  for i := 0 to 9 do s := s + Dec3(buf[i]) + ' ';
  writeln('bytes: ', s);

  { SEEK: to 5 from the start, then to -2 from the end, then tell. A backend
    that transposed whence would still read SOMETHING at each of these. }
  writeln('seek5=', PalSeek(h, 5, 0));
  buf[0] := 0;
  writeln('read1=', PalRead(h, @buf[0], 1), ' got=', buf[0]);
  writeln('seek-end-2=', PalSeek(h, -2, 2));
  buf[0] := 0;
  writeln('read1=', PalRead(h, @buf[0], 1), ' got=', buf[0]);
  writeln('tell=', PalTell(h));
  writeln('close=', PalClose(h));

  { A path under no grant, and a path that does not exist. Both must be
    ENOENT (-2) and NOT the same as each other by accident of both being
    negative — the numbering is the assertion. }
  writeln('missing=', PalOpen('does-not-exist.bin', PAL_OPEN_READ, 0));
  writeln('outside=', PalOpen('/definitely/not/granted', PAL_OPEN_READ, 0));

  { The platform IDENTITY is deliberately not printed here. It is the one
    thing that must DIFFER between the two builds — posix is 1 with sockets
    and threads, WASI is 3 with neither — so putting it in a diffed slice
    would force the check to either ignore a line or assert a falsehood.
    check_wasi.sh asserts it separately, against the values each target should
    give. }

  { --- a missing file must be ENOENT, and IOResult must say so --- }
  Assign(f, 'nosuchfile.txt');
  {$I-} Reset(f); {$I+}
  writeln('missing file ioresult=', IOResult);

  { --- rename, then the old name is gone and the new one reads --- }
  Assign(f, 'a.txt');
  Rename(f, 'c.txt');
  Assign(f, 'c.txt');
  Reset(f);
  readln(f, s);
  Close(f);
  writeln('renamed reads [', s, ']');
  Assign(f, 'a.txt');
  {$I-} Reset(f); {$I+}
  writeln('old name ioresult=', IOResult);

  { --- erase --- }
  Assign(f, 'c.txt');
  Erase(f);
  Assign(f, 'c.txt');
  {$I-} Reset(f); {$I+}
  writeln('erased ioresult=', IOResult);

  { --- a directory: create, use, remove --- }
  writeln('mkdir=', PalMkdir('sub', 493));
  Assign(f, 'sub/d.txt');
  Rewrite(f);
  writeln(f, 'nested');
  Close(f);
  Assign(f, 'sub/d.txt');
  Reset(f);
  readln(f, s);
  Close(f);
  writeln('nested reads [', s, ']');
  Assign(f, 'sub/d.txt');
  Erase(f);
  writeln('rmdir=', PalRmdir('sub'));
  writeln('dir cycle done');

  { --- cleanup so a rerun starts clean --- }
  writeln('unlink=', PalDelete('b.bin'));
end.
