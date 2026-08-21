unit ugspecgen;
{ The GENERIC TTest. Its non-generic homonym lives in ugspecnon — FPC resolves
  the two by ARITY, not by which unit came last in the uses clause. A plain
  field keeps this about the specialization DECLARATION; cross-unit generic
  METHOD bodies are their own gap (tgeneric91). }
{$mode objfpc}
interface

type
  generic TTest<T> = class
  public
    Val: T;
  end;

implementation

end.
