{ SPDX-License-Identifier: MPL-2.0 }
{ THE OUTPUT MAY NOT BE AN INPUT.

  `pxx g.pas ./g.pas`, `pxx g.pas /abs/dir/g.pas`, `pxx g.pas a/../g.pas` and an
  output that is a symlink to the source all wrote the ELF over the source file:
  the one guard compared the two SPELLINGS (`outFile = inFile`), so only the
  byte-identical `pxx g.pas g.pas` was caught. The same held for any file the
  compile reads -- a unit, an include, a C header, an object to link.

  So the comparison is by IDENTITY, the kernel's: the mount id and inode of the
  file, read from /proc/self/fdinfo of an O_PATH descriptor (no read permission
  needed, and a FIFO does not block). There is no stat intrinsic, and this
  needs none: the compiler already reads /proc through sysopen/sysread for its
  environment. A path resolves through every symlink and `..` on the way, so
  all four spellings above name one identity.

  The output's identity is taken ONCE, by the driver, and only exists when the
  output file already exists -- a file that is not there cannot be an input.
  Every input then passes through LoadInput, which is LoadFile plus the check;
  LoadFile itself is an intrinsic in a self-hosted compiler, so the check cannot
  live in its body (that body runs only under the FPC seed).

  When identity cannot be read (no /proc, or a kernel whose fdinfo has no
  `ino:` line), PxxFileIdentity answers '' and only the spelling guard in the
  driver remains -- the state before this file, not a new failure.
  bug-a-the-output-can-overwrite-the-source-under-another-spelling }

var
  PxxOutIdent: AnsiString;   { '' = the output does not exist yet, or unknown }
  PxxOutPath:  AnsiString;

{ The digits after `key` in an fdinfo block, or ''. }
function PxxFdInfoField(const s, key: AnsiString): AnsiString;
var i, j, n, k: Integer;
begin
  PxxFdInfoField := '';
  n := Length(s); k := Length(key);
  i := 1;
  while i + k - 1 <= n do
  begin
    if ((i = 1) or (s[i - 1] = Chr(10))) and (Copy(s, i, k) = key) then
    begin
      j := i + k;
      while (j <= n) and ((s[j] = ' ') or (s[j] = Chr(9))) do Inc(j);
      while (j <= n) and (s[j] >= '0') and (s[j] <= '9') do
      begin
        PxxFdInfoField := PxxFdInfoField + s[j];
        Inc(j);
      end;
      Exit;
    end;
    Inc(i);
  end;
end;

{ `mnt_id:ino` of the file `path` names, through every symlink, or ''. }
function PxxFileIdentity(const path: AnsiString): AnsiString;
var buf: array[0..1023] of Byte; fd, info, n, i: Integer;
    pth, s, mnt, ino: AnsiString;
begin
  PxxFileIdentity := '';
  pth := path;
  fd := sysopen(pth, 2097152);        { O_PATH }
  if fd < 0 then Exit;
  pth := '/proc/self/fdinfo/' + AIntToStr(fd);
  n := 0;
  info := sysopen(pth, 0);
  if info >= 0 then
  begin
    n := sysread(info, buf, SizeOf(buf));
    sysclose(info);
  end;
  sysclose(fd);
  s := '';
  for i := 0 to n - 1 do s := s + Chr(buf[i]);
  mnt := PxxFdInfoField(s, 'mnt_id:');
  ino := PxxFdInfoField(s, 'ino:');
  if (mnt <> '') and (ino <> '') then PxxFileIdentity := mnt + ':' + ino;
end;

{ Record the output the compile will write; called once by the driver. }
procedure PxxNoteOutput(const path: AnsiString);
begin
  PxxOutPath := path;
  PxxOutIdent := PxxFileIdentity(path);
end;

{ The one refusal text, for the identity check and the driver's spelling check. }
procedure PxxRefuseOutputIs(const path: AnsiString);
begin
  writeln(StdErr, 'pxx: error: the output is an input of this compile; writing it would destroy the input');
  writeln(StdErr, '  input:  ', path);
  writeln(StdErr, '  output: ', PxxOutPath, '  (the same file)');
  writeln(StdErr, '  name a different output: pxx [options] <source> <output>');
  Halt(1);
end;

{ Refuse, before a byte is written, when `path` IS the output. }
procedure PxxRefuseInputAsOutput(const path: AnsiString);
begin
  if PxxOutIdent = '' then Exit;
  if PxxFileIdentity(path) = PxxOutIdent then PxxRefuseOutputIs(path);
end;

{ LoadFile for everything the compile READS. }
procedure LoadInput(const path: AnsiString; var dst: AnsiString);
begin
  PxxRefuseInputAsOutput(path);
  LoadFile(path, dst);
end;
