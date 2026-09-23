{ SPDX-License-Identifier: Zlib }
unit ansiterm;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
interface

{ THE SYSCALL NUMBERS ARE THE PAL'S, not this unit's. Until 2026-09-04 ansiterm
  carried four private per-target tables -- GetSysIoctl, GetSysRead, GetSysWrite,
  GetSysFcntl -- and the incident that produced two of them is recorded in
  bug-b-ansiterm-has-no-syscall-numbers-for-riscv32-or-xtensa-so-every-tui-draws-nothing:
  GetSysWrite returned -1 there, AnsiWrite's `if w = -1 then Exit` took it, and
  every TUI drew NOTHING on riscv32 and xtensa while ordinary WriteLn kept
  working. The ioctl and fcntl tables still had that hole when they were
  deleted, with a comment saying it could not be filled because "this compiler
  never emits ioctl or fcntl for either target, so there is no in-tree source
  for the number". platform.pas HAS them for all six -- riscv32 29/25, xtensa
  66/67 -- and has had them all along. The private table is what stopped anyone
  asking.

  `platform` is pulled in the IMPLEMENTATION uses below, not here: nothing in
  this unit's interface names a PAL type, and an interface-level dependency
  would propagate to every consumer of ansiterm for no reason.

  The five bodies also stop REFUSING on a backend that simply has none. wasi's
  PalIoctl and PalFcntl answer PAL_ERR_UNSUPPORTED, which is a defined failure
  the callers already handle (no raw mode, 80x24, no key) -- while on wasm32
  PalRead and PalWrite are real, so a TUI now DRAWS there instead of the whole
  body being refused at codegen. These five were 45 of the 518 IR_SYSCALL
  refusals in the wasm32 corpus census. }
function AnsiColor(fg: Integer; const s: AnsiString): AnsiString;
function AnsiRGB(fgR, fgG, fgB: Integer; const s: AnsiString): AnsiString;
function AnsiBgRGB(r, g, b: Integer): AnsiString;
function AnsiReset: AnsiString;
function AnsiBold: AnsiString;
function AnsiClear: AnsiString;
function AnsiMove(row, col: Integer): AnsiString;

{ Backend primitives the screen manager (unit `screen`) drives. Colour setters
  here SET the pen (no string wrap, no auto-reset), unlike AnsiColor/AnsiRGB. }
function AnsiSetFg(code: Integer): AnsiString;   { SGR 30..37 / 90..97 }
function AnsiSetBg(code: Integer): AnsiString;   { SGR 40..47 / 100..107 }
function AnsiHideCursor: AnsiString;
function AnsiShowCursor: AnsiString;
function AnsiAltScreen(enable: Boolean): AnsiString;

function TerminalSize(var cols, rows: Integer): Boolean;
procedure AnsiSetRawMode(enable: Boolean);
function AnsiReadKey: Char;
{ Blocking single-byte read from stdin (no O_NONBLOCK): waits for a key. In raw
  mode (VMIN=1) it returns as soon as one byte arrives; on EOF / error -> #0.
  The non-blocking AnsiReadKey is for polling; this is for an event loop. }
function AnsiReadKeyWait: Char;
{ Unbuffered write of s to stdout (raw syscall) — a TUI must not wait on Pascal's
  output buffering to flush, so the screen manager renders through this. }
procedure AnsiWrite(const s: AnsiString);

implementation

uses sysutils, platform;

const
  ESC = #27;

function AnsiColor(fg: Integer; const s: AnsiString): AnsiString;
begin
  Result := '' + ESC + '[' + IntToStr(fg) + 'm' + s + ESC + '[0m';
end;

function AnsiRGB(fgR, fgG, fgB: Integer; const s: AnsiString): AnsiString;
begin
  Result := '' + ESC + '[38;2;' + IntToStr(fgR) + ';' + IntToStr(fgG) + ';' + IntToStr(fgB) + 'm' + s + ESC + '[0m';
end;

function AnsiBgRGB(r, g, b: Integer): AnsiString;
begin
  Result := '' + ESC + '[48;2;' + IntToStr(r) + ';' + IntToStr(g) + ';' + IntToStr(b) + 'm';
end;

function AnsiReset: AnsiString;
begin
  Result := '' + ESC + '[0m';
end;

// Note: ESC is a Char, prefixing with '' ensures it is concatenated as a string.
function AnsiBold: AnsiString;
begin
  Result := '' + ESC + '[1m';
end;

function AnsiClear: AnsiString;
begin
  Result := '' + ESC + '[2J' + ESC + '[H';
end;

function AnsiMove(row, col: Integer): AnsiString;
begin
  Result := '' + ESC + '[' + IntToStr(row) + ';' + IntToStr(col) + 'H';
end;

function AnsiSetFg(code: Integer): AnsiString;
begin
  Result := '' + ESC + '[' + IntToStr(code) + 'm';
end;

function AnsiSetBg(code: Integer): AnsiString;
begin
  Result := '' + ESC + '[' + IntToStr(code) + 'm';
end;

function AnsiHideCursor: AnsiString;
begin
  Result := '' + ESC + '[?25l';
end;

function AnsiShowCursor: AnsiString;
begin
  Result := '' + ESC + '[?25h';
end;

function AnsiAltScreen(enable: Boolean): AnsiString;
begin
  if enable then
    Result := '' + ESC + '[?1049h'
  else
    Result := '' + ESC + '[?1049l';
end;

function AnsiReadKeyWait: Char;
var c: Char;
begin
  c := #0;
  if PalRead(0, @c, 1) = 1 then Result := c else Result := #0;
end;

procedure AnsiWrite(const s: AnsiString);
var ignored: Int64;
begin
  if Length(s) = 0 then Exit;
  ignored := PalWrite(1, @s[1], Length(s));   { fd 1 = stdout }
end;

type
  TTermios = record
    IFlag: LongWord;
    OFlag: LongWord;
    CFlag: LongWord;
    LFlag: LongWord;
    Line: Byte;
    CC: array[0..31] of Byte;
    ISpeed: LongWord;
    OSpeed: LongWord;
  end;

var
  OrigTermios: TTermios;
  RawModeEnabled: Boolean = False;

procedure AnsiSetRawMode(enable: Boolean);
var t: TTermios;
begin
  if enable then
  begin
    if RawModeEnabled then Exit;
    { Read current state. A backend with no ioctl -- wasi, and any ESP platform
      -- answers PAL_ERR_UNSUPPORTED, so raw mode simply does not engage and
      RawModeEnabled stays False. That is the same path a redirected stdout
      takes on x86-64, and it is a DEFINED failure rather than the refusal the
      old `if sysIoctlVal = -1 then Exit` produced from a missing table row. }
    if PalIoctl(0, $5401, @OrigTermios) = 0 then   { TCGETS }
    begin
      t := OrigTermios;
      t.LFlag := t.LFlag and (not LongWord($00000002)); { ICANON }
      t.LFlag := t.LFlag and (not LongWord($00000008)); { ECHO }
      t.CC[6] := 1; { VMIN }
      t.CC[5] := 0; { VTIME }
      if PalIoctl(0, $5402, @t) = 0 then           { TCSETS }
        RawModeEnabled := True;
    end;
  end
  else
  begin
    if not RawModeEnabled then Exit;
    if PalIoctl(0, $5402, @OrigTermios) = 0 then   { TCSETS }
      RawModeEnabled := False;
  end;
end;

function AnsiReadKey: Char;
var c: Char; rd: Int64; flags, ignored: Integer;
begin
  c := #0;
  Result := #0;

  { Temporarily set stdin to non-blocking. THE GUARD IS LOAD-BEARING: without
    O_NONBLOCK this read BLOCKS, and AnsiReadKey's whole contract is that it
    does not. So a backend with no fcntl must return #0 here rather than fall
    through to the read -- which is what the old `if sysFcntlVal = -1` did, for
    a different reason (a missing table row rather than a backend that says so). }
  flags := PalFcntl(0, 3, 0);                        { F_GETFL }
  if flags < 0 then Exit;
  ignored := PalFcntl(0, 4, Int64(flags) or $800);   { F_SETFL, O_NONBLOCK }

  { keep the read's byte count in its own var -- restoring flags below must not
    clobber it (this once made AnsiReadKey always return #0). }
  rd := PalRead(0, @c, 1);

  ignored := PalFcntl(0, 4, flags);                  { restore }

  if rd = 1 then Result := c;
end;

const
  { TIOCGWINSZ IS NOT ONE NUMBER ACROSS LINUX ARCHES, AND XTENSA IS THE ONE OF
    OURS THAT DIFFERS. Most arches take asm-generic's $5413; xtensa keeps the
    BSD-style 't' encoding for the window-size family while using asm-generic
    for everything else -- TCGETS $5401 and TCSETS $5402 are the generic numbers
    on xtensa too, measured, which is why only this one constant is conditional.

    $80087468 is _IOR('t', 104, struct winsize) under LINUX's macro, and the
    direction bits are the whole trap: Linux's _IOC_READ is 2, so _IOR sets
    $80000000, where BSD's sets $40000000. (2<<30)|(8<<16)|('t'<<8)|104 lands
    exactly on $80087468.

    bug-b-terminalsize-answers-enotty-on-xtensa-and-the-probe-cannot-say-why
    tried $40087468 -- the BSD spelling of the same idea -- and got -25, the
    same answer the generic constant gives, so the probe refuted nothing. It was
    testing a constant that is wrong under BOTH hypotheses it was meant to
    separate.

    Measured 2026-09-24 at HEAD, all six targets, each in a pty under
    `script -qec 'stty rows 40 cols 132'`, x86-64 native and the rest under
    qemu user-mode:

      target                     $5413    $80087468
      x86-64, i386, arm32,
      aarch64, riscv32              0          -25
      xtensa                      -25     0 (rows=40 cols=132)

    THE XTENSA ROWS ARE QEMU-XTENSA, NOT SILICON, and qemu's target ioctl table
    is derived from the kernel's uapi headers rather than being an independent
    witness. What raises it above "qemu says so" is that the accepted value is
    exactly the canonical _IOR('t',104,8) encoding, which is what a kernel header
    generates, and that qemu decoded and NAMED the request. A run on real xtensa
    Linux would still be worth having.

    IT TRACKS, WHICH IS A SEPARATE CLAIM FROM "IT ANSWERED 40x132" (frankb-8e,
    independently, same day): three pty sizes read back exactly -- 132x40, 80x24
    and 200x50 -- and two calls in a row give the same answer, so it is a GET and
    not a setter that happens to leave data behind. It also returns -25 correctly
    when stdout is a plain file. One size alone cannot distinguish a real
    TIOCGWINSZ from a constant that reports something plausible. }
{$ifdef CPU_XTENSA}
  TIOCGWINSZ = $80087468;
{$else}
  TIOCGWINSZ = $5413;
{$endif}

function TerminalSize(var cols, rows: Integer): Boolean;
type
  TWinSize = record
    Row, Col, XPixel, YPixel: Word;
  end;
var
  ws: TWinSize;
begin
  cols := 80;
  rows := 24;
  Result := False;
  ws.Row := 0;
  ws.Col := 0;
  { THE Col/Row GUARD IS LOAD-BEARING ON XTENSA, NOT DEFENSIVE -- do not fold it
    into the rc check as redundant. Measured 2026-09-24: on an xtensa pty there
    are ioctl encodings that return rc = 0 and leave the struct ZEROED ($40087467
    is one; four exist in the read-direction 't'/'T' space). So rc alone would
    report SUCCESS with an 0x0 terminal, and every consumer would scale its UI to
    nothing. The dimensions, not the return code, are what identify this ioctl --
    which is also why any future candidate constant must be validated against a
    pty of KNOWN size rather than against rc = 0. }
  if PalIoctl(1, TIOCGWINSZ, @ws) = 0 then
    if (ws.Col > 0) and (ws.Row > 0) then
    begin
      cols := ws.Col;
      rows := ws.Row;
      Result := True;
    end;
end;

end.
