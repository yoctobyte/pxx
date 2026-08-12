program test_variant_arg_prefers_variant_overload;
{ A VARIANT argument must bind a VARIANT parameter when one is declared, even
  when another argument is merely COMPATIBLE rather than exact.

  A Variant is TypesCompatible with every scalar parameter, so the compatible
  phases of the overload ladder used to bind whichever candidate was DECLARED
  FIRST — here Int64 — and the exact Variant candidate was never reached. The
  result was not a diagnostic but a coercion: a Variant holding 7.5 printed as
  7 and one holding a string raised at run time.

  It stayed hidden because an ALL-EXACT call already won in phase 1; the second
  argument below is a ShortString against an AnsiString parameter, which is the
  shape that drops the whole call into the compatible phases.

  Expectations are FPC 3.2.2's own output.
  bug-a-a-variant-argument-binds-the-first-compatible-overload }
{$mode objfpc}{$H+}

function pick(i: Int64; const spec: AnsiString): AnsiString;
begin Result := 'int'; end;
function pick(const s: AnsiString; const spec: AnsiString): AnsiString; overload;
begin Result := 'str'; end;
function pick(d: Double; const spec: AnsiString): AnsiString; overload;
begin Result := 'float'; end;
function pick(const v: Variant; const spec: AnsiString): AnsiString; overload;
begin Result := 'variant'; end;

{ The Variant candidate DECLARED LAST above and FIRST here: the rule must not
  depend on declaration order in either direction. }
function last(const v: Variant): AnsiString;
begin Result := 'variant'; end;
function last(i: Int64): AnsiString; overload;
begin Result := 'int'; end;

{ No Variant candidate at all — a Variant argument must still bind a compatible
  overload rather than becoming a no-match. }
function only(i: Int64; const spec: AnsiString): AnsiString;
begin Result := 'int'; end;

var v: Variant; sp: ShortString; s: AnsiString; d: Double; n: Int64;
begin
  sp := '6.2f';
  s := 'exact';
  d := 1.5;
  n := 7;

  v := 7.5;   WriteLn(pick(v, sp));      { variant }
  v := 'hi';  WriteLn(pick(v, sp));      { variant }
  v := 3;     WriteLn(pick(v, sp));      { variant }
  v := 7.5;   WriteLn(pick(v, s));       { variant — the all-exact call, unchanged }

  { a NON-variant argument must be unaffected by the new phase }
  WriteLn(pick(n, sp));                  { int }
  WriteLn(pick(s, sp));                  { str }
  WriteLn(pick(d, sp));                  { float }

  v := 1;     WriteLn(last(v));          { variant }
  WriteLn(last(n));                      { int }

  v := 5;     WriteLn(only(v, sp));      { int — no variant candidate exists }
end.
