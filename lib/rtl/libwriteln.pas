unit libwriteln;
{ `write` / `writeln` as ORDINARY LIBRARY ROUTINES over `array of const`.

  Phase 3 of feature-writeln-as-library. The builtin write/writeln are
  special-cased in codegen (IR_WRITE / IR_WRITELN); this unit does the same job
  with no compiler support beyond `array of const` itself, which is what makes
  the formatting rules readable, testable and extendable in Pascal instead of
  in the backend.

  IT DOES NOT REPLACE THE BUILTIN AND MUST NOT. `compiler.pas` self-hosts on the
  builtin writeln, so the builtin is load-bearing for the whole toolchain. Using
  this unit is the opt-in: the routines are separately named and nothing is
  shadowed. Do not add `writeln` overloads here.

  WHY IT IS USABLE AT ALL, which was not true until 2026-09-01: phase 1 landed
  variadic bracket-elision, so `LibWriteLn('x=', x)` compiles against
  `array of const` without the caller writing the brackets. Before that the
  ticket's own note called phase 3 "a strictly worse writeln nobody would use",
  and it was right -- with brackets mandatory this is worse than the builtin in
  every way.

  THE BYTE SINK IS STILL THE BUILTIN, DELIBERATELY. Each routine assembles one
  AnsiString and hands it to `write(s)` / `write(StdErr, s)`. That is the whole
  of what stays in the compiler: emitting bytes to a descriptor. All the
  FORMATTING -- which is where the builtin is incomplete and hard to change --
  is here. It also keeps this unit portable to every backend including ESP,
  since it needs no syscall of its own.

  KNOWN DIVERGENCE FROM THE BUILTIN, measured, in the BOXING and so unreachable
  from here. A reader of the vector cannot recover what the tag never carried,
  so it cannot be fixed in this unit:

    * WordBool / LongBool / ByteBool box as vtInteger and render as 1/0, where
      the builtin prints TRUE/FALSE. A plain Boolean is correct.
      bug-a-the-sized-booleans-render-as-a-digit-in-both-str-and-writeln

  The QWord entry that used to head this list is GONE, and the way it went is
  worth one line: d210325a6 gave QWord its own tag, which fixed the BOXING half
  and silently broke this unit, because a `case` over tags renders the empty
  string for one it does not list. The divergence went from "renders signed" to
  "renders nothing" and the test caught the second, not the first. Measured
  2026-09-06 at 18000000000000000000: builtin and LibWriteLn now agree.

  Everything else is byte-identical to the builtin, which is asserted row by row
  in test/test_libwriteln_parity.pas rather than claimed here. }

interface

uses sysutils;

{ One element, rendered exactly as the builtin `write` would render it. }
function VarRecToText(const v: TVarRec): AnsiString;

{ The whole vector, concatenated, no separators -- `write`'s contract. }
function VarRecsToText(const a: array of const): AnsiString;

procedure LibWrite(const a: array of const);
procedure LibWriteLn(const a: array of const);
procedure LibWriteErr(const a: array of const);
procedure LibWriteLnErr(const a: array of const);

implementation

function VarRecToText(const v: TVarRec): AnsiString;
var d: Double; s: ShortString;
begin
  case v.VType of
    vtInteger:
      VarRecToText := IntToStr(v.VInteger);
    vtBoolean:
      { the builtin prints these upper-case and unpadded; sysutils' BoolToStr
        spells them 'True'/'False', which is a DIFFERENT contract -- do not
        route this through it }
      if v.VBoolean then VarRecToText := 'TRUE' else VarRecToText := 'FALSE';
    vtChar:
      VarRecToText := v.VChar;
    vtExtended:
      begin
        { `Str` with no width is FPC's default scientific form for a real --
          ` d.dddddddddddddddddE+eee`, leading space for a positive value. That
          is exactly what builtin writeln emits, so this is the one renderer
          that must NOT use FloatToStr: FloatToStr gives natural decimal ('3.5')
          and would diverge on every float row. }
        d := PDoubleRec(v.VExtended)^;
        Str(d, s);
        VarRecToText := s;
      end;
    vtAnsiString:
      VarRecToText := StrPas(PChar(v.VAnsiString));
    vtPChar:
      VarRecToText := StrPas(PChar(v.VPChar));
    vtInt64:
      VarRecToText := IntToStr(PInt64Rec(v.VInt64)^);
    vtQWord:
      { d210325a6 gave QWord its own tag. Until then it arrived as vtInt64 and
        rendered signed; this arm did not exist, so every QWord fell to the
        `else` below and printed the EMPTY STRING -- an arm whose comment calls
        an empty result honest, which is true of the tags it was written for and
        false for a tag added later. UIntToStr, not IntToStr: rendering signed
        is the defect the new tag exists to fix. }
      VarRecToText := UIntToStr(PQWordRec(v.VInt64)^);
  else
    { A tag this compiler does not emit, or one whose payload is not text --
      vtPointer, vtObject, vtClass. The builtin refuses those at compile time
      rather than printing something, so there is no rendering to match and an
      empty string is the honest answer. Deliberately not an Error: this is a
      library routine, and a program that reaches here has already compiled. }
    VarRecToText := '';
  end;
end;

function VarRecsToText(const a: array of const): AnsiString;
var i: Integer; r: AnsiString;
begin
  r := '';
  for i := 0 to High(a) do
    r := r + VarRecToText(a[i]);
  VarRecsToText := r;
end;

procedure LibWrite(const a: array of const);
var s: AnsiString;
begin
  s := VarRecsToText(a);
  if Length(s) > 0 then write(s);
end;

procedure LibWriteLn(const a: array of const);
begin
  { one write, not write-then-newline: the builtin emits the line as a unit and
    a second call would interleave differently under a concurrent writer }
  write(VarRecsToText(a) + #10);
end;

procedure LibWriteErr(const a: array of const);
var s: AnsiString;
begin
  s := VarRecsToText(a);
  if Length(s) > 0 then write(StdErr, s);
end;

procedure LibWriteLnErr(const a: array of const);
begin
  write(StdErr, VarRecsToText(a) + #10);
end;

end.
