unit mimic_reportlab_lib_colors;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ `from reportlab.lib.colors import white, black, red` — colour objects with
  `.red` / `.green` / `.blue` components in 0..1, which is the whole of the
  interface an application touches (songformatter's render backend reads exactly
  those three). A T1 name shim; see mimic_reportlab_pdfgen for the policy.

  reportlab's colors module also carries a large named-colour table, alpha, CMYK
  and HexColor. Only the three names an application here imports are provided;
  add a name when something needs it rather than guessing a palette. }

interface

type
  Color = class
  public
    red, green, blue, alpha: Double;
    constructor Create(r, g, b: Double);
  end;

var
  white: Color;
  black: Color;
  red: Color;
  green: Color;
  blue: Color;

implementation

constructor Color.Create(r, g, b: Double);
begin
  { the class's own fields, not the unit-level variables of the same name —
    a method's field wins over a unit name (bug-unit-const-shadows-a-field) }
  Self.red := r;
  Self.green := g;
  Self.blue := b;
  alpha := 1.0;
end;

initialization
  white := Color.Create(1.0, 1.0, 1.0);
  black := Color.Create(0.0, 0.0, 0.0);
  red   := Color.Create(1.0, 0.0, 0.0);
  green := Color.Create(0.0, 1.0, 0.0);
  blue  := Color.Create(0.0, 0.0, 1.0);
end.
