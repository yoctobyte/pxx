program lib_settextbuf;
{ SetTextBuf, diffed against FPC 3.2.2 rather than asserted against constants.

  SetTextBuf IS NOT A HINT AND ITS SIDE EFFECTS ARE THE CONTRACT. FPC's body is
  four assignments -- pointer, size, and two zeroed indices -- with no copy and
  no seek, so all three of its observable consequences follow directly and all
  three are what a caller relies on
  (decided/decide-settextbuf-needs-buffered-text-io-or-stays-missing.md).

  THE FILE POSITION IS THE INSTRUMENT, and it is chosen because it is the only
  one that can distinguish "the buffer was adopted" from "the call was accepted
  and ignored". Content rows cannot: a reader with the DEFAULT buffer returns
  exactly the same lines, so a test that only checked the text would pass
  against a SetTextBuf that did nothing at all. After the first ReadLn the
  descriptor sits one buffer ahead of the logical position, and that number IS
  the size the caller asked for -- 16 and 100 below, neither of which is
  TF_BUFSIZE or FPC's 256, so no row can be satisfied by a default.

  Row `midstream' is the one that looks like a bug and is not: swapping buffers
  after reading has started DISCARDS what was already buffered, so the next
  line read is not the next line in the file. Measured under FPC, copied
  deliberately. }

{$MODE OBJFPC}
{$ifdef FPC}
uses sysutils;
{$else}
uses sysutils, platform;
{$endif}

var
  f: Text;
  b16: array[0..15] of Byte;
  b100: array[0..99] of Byte;
  s: AnsiString;
  path: AnsiString;
  i: Integer;

{ The fd's real position, which is what read-ahead moves. FileSeek over the
  Text record's handle is not portable between the two RTLs, so the file is
  re-opened as an untyped file and its own position is not the subject -- what
  is measured is how many bytes the TEXT read consumed from the OS, obtained by
  asking the OS. }
function TextPos(var t: Text): Int64;
begin
{$ifdef FPC}
  TextPos := FileSeek(TextRec(t).Handle, Int64(0), 1);
{$else}
  { pxx's Text carries Handle directly (FPC hides it behind TextRec) and its
    seek lives on the PAL rather than in sysutils. Both spellings ask the OS
    the same question about the same descriptor -- which is the point: the
    number compared across the two compilers is the KERNEL's, not either
    RTL's idea of where it is. }
  TextPos := PalSeek(t.Handle, 0, PAL_SEEK_CUR);
{$endif}
end;

{ Written through Text I/O rather than a file API, because the two RTLs do not
  spell FileCreate/FileWrite the same way and the fixture is not the subject. }
procedure MakeFile;
var w: Text; k: Integer; line: AnsiString;
begin
  Assign(w, path);
  Rewrite(w);
  for k := 1 to 20 do
  begin
    line := 'line' + IntToStr(k);
    while Length(line) < 9 do line := line + '.';
    writeln(w, line);                 { 20 lines of exactly 10 bytes = 200 }
  end;
  Close(w);
end;

begin
  path := 'settextbuf_probe.tmp';
  MakeFile;

  { 1: a 16-byte buffer. First ReadLn must leave the fd at 16. }
  Assign(f, path);
  SetTextBuf(f, b16, 16);
  Reset(f);
  ReadLn(f, s);
  writeln('small-line=', s);
  writeln('small-pos=', TextPos(f));
  Close(f);

  { 2: a 100-byte buffer over the same file. Same line, different position --
       so the row cannot be satisfied by any single hardcoded answer. }
  Assign(f, path);
  SetTextBuf(f, b100, 100);
  Reset(f);
  ReadLn(f, s);
  writeln('big-line=', s);
  writeln('big-pos=', TextPos(f));

  { 3: all 20 lines still come back in order with the small buffer -- refills
       work, and the size only changes how often. }
  Close(f);
  Assign(f, path);
  SetTextBuf(f, b16, 16);
  Reset(f);
  i := 0;
  while not Eof(f) do begin ReadLn(f, s); Inc(i); end;
  writeln('count=', i, ' last=', s);
  Close(f);

  { 4: MID-STREAM. Read one line, then swap buffers: the pending bytes are
       dropped and the next line is NOT line2. }
  Assign(f, path);
  SetTextBuf(f, b100, 100);
  Reset(f);
  ReadLn(f, s);
  writeln('midstream-first=', s);
  SetTextBuf(f, b16, 16);
  ReadLn(f, s);
  writeln('midstream-next=', s);
  Close(f);

  DeleteFile(path);
end.
