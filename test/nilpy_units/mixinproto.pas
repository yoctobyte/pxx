unit mixinproto;
{ A protocol class for the NilPy multiple-inheritance tests: the IMPORTED half
  of `class StreamWriter(Codec, codecs.StreamWriter)`, the shape every one of
  CPython's encodings modules is written in. It carries a field, a virtual
  method and a non-virtual one, so a flattened local mixin that redefines the
  name has something real to beat.
  bug-nilpy-multiple-inheritance-from-an-imported-base-is-refused }
interface

type
  Protocol = class
    tag: Integer;
    function Kind: AnsiString; virtual;
    function Plain: AnsiString;
    function Twice: Integer;
  end;

implementation

function Protocol.Kind: AnsiString; begin Kind := 'proto'; end;
function Protocol.Plain: AnsiString; begin Plain := 'plain'; end;
function Protocol.Twice: Integer; begin Twice := tag * 2; end;

end.
