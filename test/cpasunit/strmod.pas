{ A Pascal unit with a routine C cannot be handed: AnsiString is a MANAGED type
  with a refcounted lifetime, and a C caller has no way to participate in it.
  The refusal is by name at compile time (§5), not a silent pointer pun. }
unit strmod;
interface
function Greet(const s: AnsiString): Integer;
function Plain(x: Integer): Integer;
implementation
function Greet(const s: AnsiString): Integer;
begin
  Greet := Length(s);
end;
function Plain(x: Integer): Integer;
begin
  Plain := x + 1;
end;
end.
