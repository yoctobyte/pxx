{ SPDX-License-Identifier: 0BSD }
program lib_inttohex;
{ IntToHex parity with FPC 3.2.2, across the whole declared family.

  Two separable properties are under test and they belong to different tracks.

  * The RTL BODIES (Track B, lib/rtl/sysutils.pas): that the LongInt body masks
    through LongWord so a negative renders its 32-bit two's complement, that the
    LongWord body zero-extends, and that `digits` is a MINIMUM width in every
    body — never a truncation. The explicitly-typed rows pin these, and they
    hold whatever the overload-selection rules are, because the argument's type
    names the body directly. That is why they are asserted unconditionally.

  * Which body a given SPELLING selects (Track A). `Integer`, `SmallInt` and a
    bare literal do not name a body; the resolver picks one. In the default
    dialect it may widen to Int64 — intended, not a defect (user, 2026-08-14) —
    and under --strict-overload-width it takes the narrowest fit, which is FPC's
    rule. So those rows are asserted only when the narrowing rule is in force,
    guarded by STRICT_WIDTH (auto-set under FPC, where it is always the rule).
    Asserting them unflagged would freeze a Track A choice this file does not
    own into a Track B test.

  Oracle: FPC 3.2.2, and the expectations below were read off it. This program
  compiles and passes under FPC unmodified — objfpc mode is REQUIRED, because in
  FPC's DEFAULT mode `Integer` is 16-bit and silently answers a different
  question: $12345678 renders as 00005678.

  Run flagged and unflagged; see the lib-test recipe. }

{$mode objfpc}{$H+}
{$IFDEF FPC}{$DEFINE STRICT_WIDTH}{$ENDIF}

uses sysutils;

var
  fails: Integer;

procedure Check(const name, got, want: AnsiString);
begin
  if got = want then
    WriteLn(name, '=ok')
  else
  begin
    WriteLn(name, '=FAIL got ', got, ' want ', want);
    fails := fails + 1;
  end;
end;

var
  i32: LongInt;
  u32: LongWord;
  i64: Int64;
  b:   Byte;
  w:   Word;
{$IFDEF STRICT_WIDTH}
  n:   Integer;
  s:   SmallInt;
{$ENDIF}

begin
  fails := 0;

  { --- LongInt: the body whose mask this ticket added -------------------- }
  i32 := -1;            Check('longint-m1',   IntToHex(i32, 8),  'FFFFFFFF');
  i32 := -255;          Check('longint-m255', IntToHex(i32, 8),  'FFFFFF01');
  i32 := Low(LongInt);  Check('longint-min',  IntToHex(i32, 8),  '80000000');
  i32 := $12345678;     Check('longint-pos',  IntToHex(i32, 8),  '12345678');

  { `digits` is a MINIMUM: under-width never truncates, and over-width pads
    with ZEROS rather than sign extension — which is the point of the mask. }
  i32 := -1;            Check('longint-d2',   IntToHex(i32, 2),  'FFFFFFFF');
  i32 := -1;            Check('longint-d16',  IntToHex(i32, 16), '00000000FFFFFFFF');
  i32 := $12345678;     Check('longint-d0',   IntToHex(i32, 0),  '12345678');

  { --- LongWord: unsigned, zero-extends ---------------------------------- }
  u32 := $FFFFFFFF;     Check('longword-max', IntToHex(u32, 8),  'FFFFFFFF');
  u32 := $FFFFFFFF;     Check('longword-d16', IntToHex(u32, 16), '00000000FFFFFFFF');

  { --- Int64: the original body, unchanged ------------------------------- }
  i64 := -1;            Check('int64-m1',     IntToHex(i64, 16), 'FFFFFFFFFFFFFFFF');
  i64 := -1;            Check('int64-d8',     IntToHex(i64, 8),  'FFFFFFFFFFFFFFFF');
  i64 := Low(Int64);    Check('int64-min',    IntToHex(i64, 16), '8000000000000000');

  { --- narrow unsigned types --------------------------------------------- }
  b := 255;             Check('byte-255',     IntToHex(b, 2),    'FF');
  b := 15;              Check('byte-15',      IntToHex(b, 2),    '0F');
  w := 65535;           Check('word-max',     IntToHex(w, 4),    'FFFF');

{$IFDEF STRICT_WIDTH}
  { --- selection-sensitive: only under the narrowest-fit rule ------------- }
  n := -1;              Check('integer-m1',   IntToHex(n, 8),    'FFFFFFFF');
  n := Low(LongInt);    Check('integer-min',  IntToHex(n, 8),    '80000000');
  s := -1;              Check('smallint-m1',  IntToHex(s, 8),    'FFFFFFFF');
                        Check('literal-m1',   IntToHex(-1, 8),   'FFFFFFFF');
{$ENDIF}

  if fails = 0 then WriteLn('INTTOHEX OK')
                else WriteLn('INTTOHEX FAILED ', fails);
end.
