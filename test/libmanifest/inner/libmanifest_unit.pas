unit libmanifest_unit;
{ Sits one directory BELOW the manifest, so this also proves the walk is
  nearest-ANCESTOR and not same-directory-only. }
interface
function LibSees: AnsiString;
implementation

{ Delphi dotted unit-scope name. There is no unit called `Scoped.Alias`; the
  manifest ONE DIRECTORY UP maps it to libmanifest_alias, so this line also
  proves the alias walk is nearest-ANCESTOR rather than same-directory-only.
  The program that uses this unit cannot spell it this way — asserted in
  test/refuse/unitalias_out_of_scope.pas. }
uses Scoped.Alias;

type TIntFn = function(x: Integer): Integer;

function Double_(x: Integer): Integer;
begin
  Double_ := x + x;
end;

function ModeDelphiWorks: Integer;
{ `f := Double_` with NO @ is the one behavioural delta {$mode delphi} buys, so
  this line compiles here ONLY because the manifest said `mode delphi`. It is
  the observable half of that directive: without it the compiler rejects the
  bare name, which is why this is in the library unit and not in the program. }
var f: TIntFn;
begin
  f := Double_;
  ModeDelphiWorks := f(21);
end;
function LibSees: AnsiString;
begin
  Result := '';
{$ifdef MANIFEST_ON}
  Result := Result + 'manifest ';
{$else}
  Result := Result + 'NO-manifest ';
{$endif}
{$ifdef PROGDEF}
  Result := Result + 'progdef';
{$else}
  Result := Result + 'no-progdef';
{$endif}
  if ModeDelphiWorks = 42 then Result := Result + ' delphi-ok'
  else Result := Result + ' DELPHI-BAD';
  Result := Result + ' ' + AliasSees;
end;
end.
