/* A BY-VALUE STRUCT ARGUMENT, EVERY AAPCS64 CLASS, WITH A TRAILING SCALAR.
 *
 * `ABIA64CdeclArgSlot` advanced the next-stacked-argument address by a fixed 8
 * per argument, so an aggregate of any size got exactly one pointer-sized slot
 * and its three readers -- the callee spill, the direct call and the indirect
 * call -- all inherited that. Measured against
 * `clang --target=aarch64-linux-gnu -O1 -S`, four of five shapes were placed
 * wrongly and the fifth was RIGHT BY ACCIDENT: a 24-byte struct really is
 * indirect on this ABI, so "always a pointer" collides with the psABI on
 * exactly the shape a single hand-written probe would choose.
 * bug-a-an-aggregate-argument-is-a-pointer-by-construction-on-aarch64
 *
 * EVERY CALL HERE CARRIES A TRAILING INTEGER, and that is not decoration. The
 * GP and FP banks allocate INDEPENDENTLY, so the tail after an HFA belongs in
 * w0 and not w2; a fix that puts the HFA in d0,d1 and still advances the GP
 * index is wrong in a way NO SINGLE-ARGUMENT PROBE CAN SEE. The tail is the
 * only thing in this file that reports the bank state after the aggregate.
 *
 * The classes, and why each row is here rather than one of the others:
 *   i2   {int,int}      8  -- ONE GP register holding the PACKED VALUE. This is
 *                             the row whose description is indistinguishable
 *                             from a scalar's: 1 register, 8 bytes. A
 *                             marshaller that infers "is this an aggregate"
 *                             from the register count and the size sends it
 *                             down the scalar path and passes the ADDRESS.
 *   l2   {long,long}   16  -- two GP registers
 *   l3   {long,long,long} 24 -- INDIRECT: a pointer to a copy the CALLER makes
 *   d2   {double,double}  16 -- HFA, two d registers (same size as l2, other bank)
 *   f3   {float,float,float} 12 -- HFA, three s registers, and NOT 16 bytes
 *   f4   {float x4}    16  -- HFA at the four-member limit
 *
 * `five` exhausts the FP bank: four {double,double} fill d0..d7 and the fifth
 * goes to the stack ENTIRELY -- an aggregate is never split between a bank and
 * the stack, and placing an HFA's first registers while stranding the rest is a
 * plausible wrong answer rather than a crash. `nine` does the same to the GP
 * bank. Both read every member back, so a stranded half is visible.
 *
 * The `p1`/`p2`/`p3` rows call the SAME functions through a POINTER. Fixing the
 * direct arm and not the indirect one produces a gate that passes because the
 * subject contains no call through a function pointer -- the trap x86-64 and
 * i386 both walked into on the parent ticket.
 *
 * THIS FILE IS A REGRESSION GUARD AND IT IS NOT THE PROOF OF THE FIX. MEASURED:
 * it passes on the PRE-FIX compiler, byte for byte, on aarch64. That is not a
 * flaw in the rows -- it is the defect's class. Caller and callee were BOTH
 * built by pxx and BOTH used the one-pointer-slot convention, so they agreed
 * with each other and every value arrived intact; the parent ticket's whole
 * finding is that a calling convention cannot be judged from inside one
 * implementation. An outcome test on a pxx-only program is PHYSICALLY UNABLE
 * to observe this bug, so a green row here says "pxx still agrees with itself"
 * and says nothing about AAPCS64.
 *
 * What DID prove it is a PLACEMENT oracle:
 *   clang --target=aarch64-linux-gnu -O1 -S   (needs no sysroot, nothing links,
 *                                              nothing runs -- you read the
 *                                              CALL SITE)
 *   llvm-objdump-21 on pxx's own aarch64 ELF, addresses from the .map
 * with the five rows and clang's answers recorded in the ticket. The half that
 * is still missing is a mixed LINK -- a pxx-compiled callee receiving from
 * clang-compiled code -- which needs an aarch64 linker this box does not have.
 * Do not read this file's green as covering that.
 *
 * NO ROW PRINTS A SIZE OR A REGISTER NUMBER. Every value is arithmetic over the
 * members, so one .expected is correct on every target and this file is a
 * cross-target control as well as an aarch64 test: it must print the same lines
 * on x86-64, i386, arm32 and riscv32, where it passed before this change and
 * must keep passing. Diffed against gcc.
 */
#include <stdio.h>

struct i2 { int a, b; };
struct l2 { long a, b; };
struct l3 { long a, b, c; };
struct d2 { double x, y; };
struct f3 { float x, y, z; };
struct f4 { float a, b, c, d; };

static int ti2(struct i2 s, int t) { return s.a * 100 + s.b * 10 + t; }
static int tl2(struct l2 s, int t) { return (int)(s.a * 100 + s.b * 10) + t; }
static int tl3(struct l3 s, int t) { return (int)(s.a * 100 + s.b * 10 + s.c) + t; }
static int td2(struct d2 s, int t) { return (int)(s.x * 100 + s.y * 10) + t; }
static int tf3(struct f3 s, int t) { return (int)(s.x * 100 + s.y * 10 + s.z) + t; }
static int tf4(struct f4 s, int t) { return (int)(s.a + s.b * 2 + s.c * 4 + s.d * 8) + t; }

static int five(struct d2 a, struct d2 b, struct d2 c, struct d2 d,
                struct d2 e, int t)
{ return (int)(a.x + b.x * 2 + c.x * 4 + d.x * 8 + e.x * 16 + e.y * 32) + t; }

static int nine(struct i2 a, struct i2 b, struct i2 c, struct i2 d, struct i2 e,
                struct i2 f, struct i2 g, struct i2 h, struct i2 i, int t)
{ return a.a + b.a * 2 + c.a * 3 + d.a * 4 + e.a * 5 + f.a * 6 + g.a * 7 +
         h.a * 8 + i.a * 9 + i.b * 10 + t; }

int main(void)
{
  struct i2 a; struct l2 b; struct l3 c; struct d2 d; struct f3 e; struct f4 f;
  int (*p1)(struct i2, int);
  int (*p2)(struct d2, int);
  int (*p3)(struct l3, int);

  a.a = 1;   a.b = 2;
  b.a = 3;   b.b = 4;
  c.a = 5;   c.b = 6;   c.c = 7;
  d.x = 1.5; d.y = 2.5;
  e.x = 1.5; e.y = 2.5; e.z = 3.5;
  f.a = 1;   f.b = 2;   f.c = 3;   f.d = 4;

  p1 = ti2; p2 = td2; p3 = tl3;

  printf("gp   %d %d\n", ti2(a, 9), tl2(b, 9));
  printf("ind  %d\n", tl3(c, 9));
  printf("hfa  %d %d %d\n", td2(d, 9), tf3(e, 9), tf4(f, 9));
  printf("bank %d %d\n", five(d, d, d, d, d, 7), nine(a, a, a, a, a, a, a, a, a, 7));
  printf("fptr %d %d %d\n", p1(a, 9), p2(d, 9), p3(c, 9));
  return 0;
}
