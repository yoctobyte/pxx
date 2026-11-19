unit usfalias;
{ A unit that does float arithmetic and does NOT name softfloat. On a no-FPU
  target the backend needs __pxx_* kernels while compiling this body. They
  were looked up with ordinary `uses` visibility, so the program's own
  `uses softfloat` (which the diagnostic told the user to add) could not
  reach them. See test_a_float_in_a_unit_finds_the_programs_softfloat.
  bug-a-the-no-fpu-diagnostic-advises-uses-softfloat-which-does-not-help }
interface
type TF = Double;
function Half(x: TF): TF;
implementation
function Half(x: TF): TF; begin Half := x / 2; end;
end.
