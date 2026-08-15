unit mixinproto2;
{ A SECOND imported protocol class, so the "two bases whose bodies are not in
  this file" refusal has something to refuse. Only one imported base can become
  the parent; the other would have to be flattened, and flattening replays a
  body this compilation does not have.
  bug-nilpy-multiple-inheritance-from-an-imported-base-is-refused }
interface
type
  Protocol2 = class
    tag: Integer;
    function Kind: AnsiString;
    function Twice: Integer;
  end;
implementation
function Protocol2.Kind: AnsiString; begin Kind := 'proto'; end;
function Protocol2.Twice: Integer; begin Twice := tag * 2; end;
end.
