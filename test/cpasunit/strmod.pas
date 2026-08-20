{ A Pascal unit with a routine C cannot be handed: AnsiString is a MANAGED type
  with a refcounted lifetime, and a C caller has no way to participate in it.
  The refusal is by name at compile time (§5), not a silent pointer pun. }
unit strmod;
interface
function Greet(const s: AnsiString): Integer;
function Plain(x: Integer): Integer;
{ ...and the RESULT side of the same rule. Its BODY also builds a managed
  string, which is what made this unit uncompilable from C until the driver
  emitted the AnsiString runtime shims
  (bug-a-c-driver-omits-rtl-stubs-for-an-imported-pascal-unit) -- the §5
  refusal below could not be reached, because nothing got that far. }
function Tag: AnsiString;
implementation
function Greet(const s: AnsiString): Integer;
begin
  Greet := Length(s);
end;
function Plain(x: Integer): Integer;
begin
  Plain := x + 1;
end;
function Tag: AnsiString;
begin
  Tag := 'pxx' + '-' + 'ok';
end;
end.
