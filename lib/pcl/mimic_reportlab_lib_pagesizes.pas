unit mimic_reportlab_lib_pagesizes;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ `from reportlab.lib.pagesizes import A4` — a (width, height) pair in points,
  which is what a Canvas takes as `pagesize=`. reportlab hands back a tuple; here
  it is the same shape a NilPy tuple has, a TPyList of two floats.
  A T1 name shim; see mimic_reportlab_pdfgen for the policy. }

interface

uses pylib;

var
  A4: TPyList;
  A5: TPyList;
  LETTER: TPyList;
  letter: TPyList;
  landscape_A4: TPyList;

implementation

function Pair(w, h: Double): TPyList;
var l: TPyList;
begin
  l := TPyList.Create;
  l.append(w);
  l.append(h);
  Pair := l;
end;

initialization
  { ISO 216 sizes rounded to points, exactly as reportlab states them }
  A4 := Pair(595.2755905511812, 841.8897637795277);
  A5 := Pair(419.5275590551181, 595.2755905511812);
  LETTER := Pair(612.0, 792.0);
  letter := LETTER;
  landscape_A4 := Pair(841.8897637795277, 595.2755905511812);
end.
