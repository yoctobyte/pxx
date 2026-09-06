{ SPDX-License-Identifier: Zlib }
unit espassert;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ `Assert` for the ESP-class BARE profile, and nothing else.

  WHY THIS UNIT EXISTS AT ALL. `__pxxAssert` lives in `builtin`, and the parser's
  soft-alias for a bare `Assert(` fires only when `FindProc('__pxxAssert') >= 0`
  (pasparser_stmt.inc). `--esp-profile=bare` pulls no `builtin` -- deliberately,
  because that unit does not compile for ESP at all and because bare must not pay
  for an RTL it has no room for -- so the alias never fired, the name fell through
  to the ordinary identifier path, and a five-line program with one assertion in
  it answered

      pascal26:5: error: undefined variable (Assert)

  on both chips. A procedure diagnosed as a variable, and no program containing an
  assertion could be built for bare metal at all. It worked on every IDF profile
  and on every hosted target, so this was the PROFILE and not the ISA.
  bug-a-assert-is-undefined-on-the-esp-bare-profile

  WHY A UNIT OF ITS OWN RATHER THAN A PIECE OF `builtin`. `uses builtin` under
  --esp-profile=bare really does fail -- measured, not assumed: it dies on
  PXXVarBinOp and PxxSciDigits17, both of which live in companion units bare does
  not get. Splitting one procedure out is the only way to have `Assert` here
  without the rest, and the rest is what will not compile.

  AND `writeln` IS A DOCUMENTED NO-OP HERE, WHICH IS WHY THIS FILE CARRIES A
  UART WRITE. My first draft of this unit reused builtin's body unchanged, and it
  COMPILED on both chips and printed NOTHING when the assertion fired -- a silent
  Halt(227), which is the worst possible outcome for an assertion. docs/targets/
  esp32.md:70 says it plainly: *"writeln/readln are intentionally no-ops -- there
  is no console. Output goes through your own UART writes"*, and test_esp_bare.pas
  has hand-rolled `PByte($60000000)^ :=` since the day it was written.

  I had recorded "AnsiString, concatenation, WriteLn and Halt all work on bare"
  from a set of COMPILES. Three of those four do work; `writeln` compiles and
  emits nothing, and only running it on the device separated them. The discipline
  that would have caught it is the one this profile is full of: a bare image's
  output is the only evidence it ran, so `ok:` from the compiler is not a result.

  So the failure path writes to the UART0 TX FIFO directly, which is what the
  docs tell every bare user to do and what the RTL should therefore do on their
  behalf. `defs.inc:1847` fixes the address for both SoCs: *"UART0 FIFO is MMIO
  at 0x60000000 on both."*

  PULLED ON DEMAND, exactly like `softfloat` and for the same reason: the token
  scan in pasparser_prog.inc only asks for it when the source contains an
  `Assert(`, so a program with no assertion in it pays nothing. TARGET-GATED as
  well as on-demand -- never made ambient, because an ambient unit is parsed by
  every compiler on every target including the older pinned one, which is the
  trap the wasibackend injection documents. }

interface

{ Identical to builtin's, deliberately -- see the note on the body. }
type
  TAssertErrorProc = procedure(const msg: AnsiString);
var
  AssertErrorProc: TAssertErrorProc;

procedure __pxxAssert(cond: Boolean; const msg: AnsiString = ''; const pos: AnsiString = '');

implementation

{ THE BODY IS A COPY OF builtin.pas's AND THAT IS THE POINT, not an oversight.

  Two implementations of `Assert` that differ are worse than one duplicated: the
  whole value of an assertion is that it says the same thing wherever it fires,
  and this one's output is diffed against the x86-64 oracle by test-esp-bare, so
  a divergence is a red rather than a surprise on a device. The shared-code
  alternative is an include both units pull, and that is the right shape ONLY
  once something else needs it -- one caller is not a second path.

  FPC semantics, measured against fpc 3.2.2 by the commit that wrote the
  original: THE MESSAGE REPLACES 'Assertion failed', IT DOES NOT FOLLOW IT, the
  position is appended by the caller as a compile-time constant, and the period
  belongs to the printer rather than to the message.

      Assert(1=2, 'boom')  ->  boom (af.pas, line 4).            rc 227
      Assert(1=2)          ->  Assertion failed (afn.pas, line 3).  rc 227

  The hook is kept even though nothing on bare installs one today: sysutils is
  what replaces it, sysutils is not reachable here, and a program that DOES
  install one (its own, for a device that must not halt) is the reason the
  indirection is FPC's design rather than an implementation detail. Dropping it
  would make this the one Assert in the tree that cannot be intercepted. }
{$ifdef PXX_ESP_BARE}
{ Byte to the UART0 TX FIFO. qemu drains it instantly; on silicon the FIFO is
  32 bytes deep and an assertion message can exceed that, but the failure path
  ends in Halt, so a dropped tail is preferable to spinning on a status
  register this unit would then have to know the layout of. Same address on
  esp32c3 and esp32s3 -- defs.inc:1847. }
procedure EspAssertPutC(code: Integer);
begin
  PByte(Int64($60000000))^ := Byte(code);
end;

procedure EspAssertPutS(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do EspAssertPutC(Ord(s[i]));
end;
{$endif}

procedure __pxxAssert(cond: Boolean; const msg: AnsiString = ''; const pos: AnsiString = '');
var text: AnsiString;
begin
  if cond then Exit;
  if msg = '' then text := 'Assertion failed' else text := msg;
  text := text + pos;
  if Assigned(AssertErrorProc) then
  begin
    AssertErrorProc(text);
    Exit;                          { a raising hook never returns; a print-only one may }
  end;
{$ifdef PXX_ESP_BARE}
  { The whole reason this unit is not a one-line `uses builtin`. }
  EspAssertPutS(text);
  EspAssertPutS('.'#10);
{$else}
  writeln(text, '.');
{$endif}
  Halt(227);                       { FPC's assertion runtime error }
end;

end.
