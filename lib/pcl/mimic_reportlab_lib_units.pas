unit mimic_reportlab_lib_units;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ `from reportlab.lib.units import mm, cm` — how many PDF points one of each is.
  A PDF point is 1/72 inch, so a millimetre is 72/25.4. These are reportlab's own
  values to the digit. A T1 name shim; see mimic_reportlab_pdfgen for the policy. }

interface

{ Written out rather than computed: a const expression here is folded by the
  integer constant evaluator, and `72.0 / 2.54` is not an integer. Values are
  reportlab's own, to the digit. }
const
  inch: Double = 72.0;
  cm: Double = 28.346456692913385;
  mm: Double = 2.834645669291339;
  pica: Double = 12.0;

implementation

end.
