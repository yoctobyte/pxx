unit eduth;

{ eduth (עדות, "testimony") — the validator. Witnesses results produced by a
  driver (bochan) and attests whether they match expected truth. Tallies
  pass/fail and yields the verdict as a process exit code.

  Minimal assertion API; golden truth is inline for now (golden files later). }

interface

type
  TEduth = record
    Passed: Integer;
    Failed: Integer;
  end;

procedure EduthInit(var e: TEduth);
procedure CheckTrue(var e: TEduth; const name: AnsiString; cond: Boolean);
procedure CheckInt(var e: TEduth; const name: AnsiString; got, want: Integer);
procedure CheckStr(var e: TEduth; const name, got, want: AnsiString);
function EduthReport(var e: TEduth): Integer;

implementation

uses sysutils;

procedure EduthInit(var e: TEduth);
begin
  e.Passed := 0;
  e.Failed := 0;
end;

procedure Pass(var e: TEduth; const name: AnsiString);
begin
  Inc(e.Passed);
  writeln('  PASS  ', name);
end;

procedure Fail(var e: TEduth; const name, detail: AnsiString);
begin
  Inc(e.Failed);
  writeln('  FAIL  ', name, '  -- ', detail);
end;

procedure CheckTrue(var e: TEduth; const name: AnsiString; cond: Boolean);
begin
  if cond then
    Pass(e, name)
  else
    Fail(e, name, 'expected true');
end;

procedure CheckInt(var e: TEduth; const name: AnsiString; got, want: Integer);
begin
  if got = want then
    Pass(e, name)
  else
    Fail(e, name, 'got=' + IntToStr(got) + ' want=' + IntToStr(want));
end;

procedure CheckStr(var e: TEduth; const name, got, want: AnsiString);
begin
  if got = want then
    Pass(e, name)
  else
    Fail(e, name, 'got=[' + got + '] want=[' + want + ']');
end;

function EduthReport(var e: TEduth): Integer;
begin
  writeln('eduth verdict: ', e.Passed, ' passed, ', e.Failed, ' failed');
  if e.Failed = 0 then
    Result := 0
  else
    Result := 1;
end;

end.
