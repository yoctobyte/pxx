{ A Pascal object IMPORTING C globals -- the other direction from
  c_obj_data_pascal.pas, which exports them.
  bug-a-a-pascal-global-cannot-import-a-c-global

  `external` on a variable used to be refused, because accepting the keyword
  without the writer half gives a variable that allocates its own storage and
  reads zero forever -- a program that compiles, links and is silently wrong.
  Both spellings are here on purpose: `cvar; external;` chains two directives,
  and the bare `external;` is what a Pascal programmer writes. A GROUP is here
  for the same reason -- the directive applies to every name in the
  declaration, and a per-declaration rule would import only the last. }
program c_obj_import_pascal;

var
  ImpCount: Integer; cvar; external;
  ImpA, ImpB: Integer; external;

function pxx_sum: Integer; cdecl;
begin
  pxx_sum := ImpCount + ImpA + ImpB;
end;

procedure pxx_bump; cdecl;
begin
  ImpCount := ImpCount + 1;      { the C side must observe this write }
end;

begin
end.
