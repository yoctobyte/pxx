unit ugdgobj;
{ The objfpc half of the same defect: an INLINE `specialize TSack<LongInt>` in a
  non-binder position (a var, a field, a parameter) is rewritten by the very
  same sweep, so it failed cross-unit too -- `unknown type: specialize`. The
  binder form `X = specialize TSack<LongInt>;` was always fine, which is why the
  original report read as "only the Delphi surface is broken". }
{$MODE OBJFPC}
interface

type
  generic TSack<T> = class
    Val: Integer;
  end;

implementation

end.
