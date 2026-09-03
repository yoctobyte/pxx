/* AAPCS64 by-value aggregate classification, checked against an ORACLE before
   any codegen reads it — the same discipline as `PXXDBG=a.sysvcls` for SysV,
   and for the same reason: the classifier and the marshalling must never be
   debugged at the same time.

   PROVENANCE OF .expected, stated exactly because it is the thing that goes
   wrong: the file was PRODUCED by this probe and then CHECKED, row by row,
   against `clang --target=aarch64-linux-gnu -O1 -S`. It is not a transcript of
   clang's output. Saying otherwise would be the same error as writing today's
   answer into a .expected and calling it an oracle — so the clang evidence for
   each row is recorded below and can be re-run in one command.

   The clang method needs nothing installed and neither links nor runs: declare
   each callee `extern`, never define it, give every call a distinct integer
   TAIL argument, and read which register that tail lands in — that names how
   many slots of each bank the aggregate ahead of it consumed. `w1` after a
   4-byte struct means the struct took one GP register; `w0` after an HFA means
   it took none, so it went to the FP bank.
   devdocs/dev/differential-probes.md, "A CROSS-TARGET ABI ORACLE EXISTS ON THIS
   BOX, AND IT IS NOT A CROSS GCC".

   Measured 2026-09-03, clang 21.1.8, tail register per shape:
     s4 w1 | s8 w1 | s12 w2 | s16 w2 | s24 w1 + `mov x0, sp` (indirect)
     hfa1 w0 | hfa2 w0 | hfa3 w0 | hfa4 w0 | hfa5 w1 + `mov x0, sp` | mix w2
   and, from the same oracle on a separate probe, the FP register COUNT that the
   tail alone cannot show: `{double,double}` occupies d0,d1 and
   `{float,float,float}` occupies s0,s1,s2. Five `{double,double}` arguments put
   four in d0..d7 and the fifth ENTIRELY on the stack — an HFA that does not fit
   the remaining FP bank is never split, which is the all-or-nothing rule the
   PLACEMENT step must honour and which this classification step does not model.

   Every line here disagrees with what the compiler currently DOES: pxx passes
   every aggregate as one pointer slot on this target. The one row where the two
   agree is `s24`, and that agreement is a hazard rather than a comfort — a
   struct over 16 bytes really is indirect on AAPCS64, so it is the shape a
   single hand-written probe would pick and the only one that would report no
   defect. bug-a-an-aggregate-argument-is-a-pointer-by-construction-on-aarch64

   The rows are chosen so no rule is tested only where it agrees with another:
   hfa2 and s16 are both 16 bytes and go to DIFFERENT banks, so only the member
   types separate them; hfa5 is homogeneous and still not an HFA, because the
   member limit is four and not the size; mix is 16 bytes with a double first
   and is not an HFA at all. */
struct s4   { int a; };
struct s8   { int a, b; };
struct s12  { int a, b, c; };
struct s16  { long a, b; };
struct s24  { long a, b, c; };
struct hfa1 { double x; };
struct hfa2 { double x, y; };
struct hfa3 { float x, y, z; };
struct hfa4 { float x, y, z, w; };
struct hfa5 { float a, b, c, d, e; };
struct mix  { double x; int y; };

int f4 (struct s4   v) { return v.a; }
int f8 (struct s8   v) { return v.a; }
int f12(struct s12  v) { return v.a; }
int f16(struct s16  v) { return (int)v.a; }
int f24(struct s24  v) { return (int)v.a; }
int g1 (struct hfa1 v) { return (int)v.x; }
int g2 (struct hfa2 v) { return (int)v.x; }
int g3 (struct hfa3 v) { return (int)v.x; }
int g4 (struct hfa4 v) { return (int)v.x; }
int g5 (struct hfa5 v) { return (int)v.a; }
int gm (struct mix  v) { return v.y; }
int main(void) { return 0; }
