{ SPDX-License-Identifier: Zlib }
unit strfmt;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ The NON-FLOAT Str formatters, in one place, so the bare ESP profile can have
  them without the rest of `builtin`.

  WHY THIS UNIT EXISTS. `Str(n, s)` is a language statement, not a library call
  -- the parser rewrites it to `s := StrInt(n, w)` and resolves the formatter by
  FindProc. The bare ESP profile links no `builtin`, so every arm failed and
  `Str` was refused for EVERY type on all four ESP targets, integers included.
  That made the profile's only debugging instrument unable to report a value:
  `Assert(n > 99, 'count too low')` compiles and prints, while the same
  assertion carrying the value that failed does not.
  feature-a-non-float-str-on-the-bare-esp-profile

  WHY A UNIT AND NOT AN INCLUDE, which is what the ticket prescribed. An include
  pulled by both `builtin` and a bare-only unit would keep two unit identities
  over one body; a shared unit is one home with no second path, and it needs
  neither a first-of-its-kind `{$i}` under compiler/builtin/ nor a change to the
  Makefile's COMPILER_INC glob -- which matches `builtin/*.pas` and would NOT
  have made a new `.inc` there a build dependency. That last part is the reason
  and not a preference: an include that is not a dependency is a silent
  stale-build source.

  WHY THE FLOAT ARM IS NOT HERE. `StrFloat` needs `PxxSciDigits17` and therefore
  softfloat, which the bare path deliberately skips so a float-free MCU program
  does not pay ~54-64 KB of flash. It stays in `builtin`. Measured marginal
  `code=` on esp32c3 over an AnsiString baseline: integer +23,724 B, float
  +89,116 B.

  EVERY CONSTRUCT BELOW WAS MEASURED ON BOTH CHIPS BEFORE THE SPLIT, not
  inferred from reading the closures. `builtin`'s own pull site says the unit
  uses "frozen-string concat, which the ESP backends cannot lower"; the literal-
  plus-managed concats these five bodies actually perform (`' ' + r`,
  `'-' + digits`, `Chr(...) + digits`), the indexed store `r[1] := c` and the
  QWord digit loop all compile AND boot under Espressif qemu on esp32c3 and
  esp32s3. Whatever that comment is true of, it is not true of these five. }

interface

function StrInt(v: Int64; width: Integer): AnsiString;
function StrQWord(v: QWord; width: Integer): AnsiString;
{ One Char as a string, right-justified to `width`. The Text-file write
  lowering needs it: a Char must NOT go through StrInt (that prints the
  ORDINAL — 120 for 'x'), which is why the ordinal arm there excludes
  tyChar. bug-p-writeln-text-rejects-char }
function StrChar(c: Char; width: Integer): AnsiString;
{ A STRING right-justified to `width`, and a Boolean as FPC's TRUE/FALSE right-
  justified the same way. The two formatters the write lowering was missing:
  writing either with a field width to a TEXT FILE silently DROPPED the width
  (TextStrArg handed the string straight through), and with a VARIABLE width to
  stdout it was refused outright — while the literal-width stdout path, which
  formats inline in codegen, had always handled both.
  bug-a-a-variable-field-width-is-refused-for-strings-and-needs-an-rtl-unit }
function StrStrW(const s: AnsiString; width: Integer): AnsiString;
function StrBool(b: Boolean; width: Integer): AnsiString;

implementation

function StrChar(c: Char; width: Integer): AnsiString;
{ One Char as a string, space-padded on the LEFT to `width` (width <= 1 = no
  padding), matching what StrInt/StrFloat do with their width argument.
  bug-p-writeln-text-rejects-char }
var r: AnsiString;
begin
  r := ' ';
  r[1] := c;
  while Length(r) < width do r := ' ' + r;
  StrChar := r;
end;

function StrStrW(const s: AnsiString; width: Integer): AnsiString;
{ see the interface comment. FPC pads on the LEFT and never truncates: a value
  wider than the field is written in full. }
var r: AnsiString;
begin
  r := s;
  while Length(r) < width do r := ' ' + r;
  StrStrW := r;
end;

function StrBool(b: Boolean; width: Integer): AnsiString;
begin
  if b then StrBool := StrStrW('TRUE', width)
  else StrBool := StrStrW('FALSE', width);
end;

function StrInt(v: Int64; width: Integer): AnsiString;
var
  neg: Boolean;
  digits: string;
  n: Int64;
  d: Integer;
begin
  digits := '';
  if v = 0 then
    digits := '0'
  else
  begin
    neg := v < 0;
    n := v;
    if neg then
    begin
      { Low(Int64) has no positive counterpart (-n wraps to itself and the
        digit loop then produced just "-"): peel the last digit in the
        NEGATIVE domain first — Pascal div/mod truncate toward zero, so
        n mod 10 is in -9..0 and n div 10 moves toward zero. }
      d := -(n mod 10);
      digits := Chr(Ord('0') + d);
      n := -(n div 10);
    end;
    while n > 0 do
    begin
      d := n mod 10;
      digits := Chr(Ord('0') + d) + digits;
      n := n div 10;
    end;
    if neg then digits := '-' + digits;
  end;
  Result := digits;
  while Length(Result) < width do
    Result := ' ' + Result;
end;

function StrQWord(v: QWord; width: Integer): AnsiString;
{ StrInt's UNSIGNED sibling: a QWord >= 2^63 must not print with a minus sign
  (write(Text, q) routes here; the console writeln path has its own unsigned
  emitter). }
var
  digits: string;
  n: QWord;
  d: Integer;
begin
  digits := '';
  if v = 0 then
    digits := '0'
  else
  begin
    n := v;
    while n > 0 do
    begin
      d := Integer(n mod 10);
      digits := Chr(Ord('0') + d) + digits;
      n := n div 10;
    end;
  end;
  Result := digits;
  while Length(Result) < width do
    Result := ' ' + Result;
end;

end.
