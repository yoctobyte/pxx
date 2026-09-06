{ The offending statement is on LINE 18 and that number is the whole point of
  the fixture beside it — a semantic diagnostic raised while lowering a node
  from a `uses`d unit used to print `pascal26:0:`.

  `r := p` is a Pointer stored into a record: refused by the AN_ASSIGN kind
  check in ir.inc, which reports through ASTLine. Deliberately a SEMANTIC
  refusal and not a parse error — a parse error is reported off the lexer's
  own position and never lost its coordinate, so it cannot see this defect. }
unit unit_a_semantic_error_in_a_unit;
interface
procedure Go;
implementation
type TR = record a, b: Integer; end;
var r: TR; p: Pointer;
procedure Go;
begin
  p := nil;
  r := p;
  WriteLn(r.a);
end;
end.
