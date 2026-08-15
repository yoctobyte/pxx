unit samenamebase;
{ A Pascal class whose name COLLIDES with the NilPy class that subclasses it.
  The collision is the point: NilPy's shell pre-pass registers a FORWARD row per
  `class X` in the .npy before any import is parsed, so this unit's declaration
  used to fill the PROGRAM's row instead of getting one of its own — the two
  classes became a single row, and the subclass was its own parent.
  bug-nilpy-class-named-after-its-imported-base-hangs-the-compiler }
interface

type
  Widget = class
    function Kind: AnsiString; virtual;
    function FromTheUnit: AnsiString;
  end;

implementation

function Widget.Kind: AnsiString; begin Kind := 'base'; end;
function Widget.FromTheUnit: AnsiString; begin FromTheUnit := 'pascal-side'; end;

end.
