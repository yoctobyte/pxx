unit libmanifest_sibling;
{ A SIBLING library with no manifest of its own. It must see neither the
  manifest's define nor its undef — the defines of one library tree are not
  ambient for the next one. }
interface
function SiblingSees: AnsiString;
implementation
function SiblingSees: AnsiString;
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
  Result := Result + 'NO-progdef';
{$endif}
end;
end.
