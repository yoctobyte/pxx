typedef unsigned int Instruction;

#define UINT_MAX 4294967295U

#define SIZE_C 8
#define SIZE_B 8
#define SIZE_Bx (SIZE_C + SIZE_B + 1)
#define SIZE_A 8
#define SIZE_OP 7

#define POS_OP 0
#define POS_A (POS_OP + SIZE_OP)
#define POS_k (POS_A + SIZE_A)
#define POS_Bx POS_k

#define L_INTHASBITS(b) ((UINT_MAX >> ((b) - 1)) >= 1)

#if L_INTHASBITS(SIZE_Bx)
#define MAXARG_Bx ((1 << SIZE_Bx) - 1)
#else
#define MAXARG_Bx 2147483647
#endif
#define OFFSET_sBx (MAXARG_Bx >> 1)

#define cast(t, exp) ((t)(exp))
#define cast_int(i) cast(int, (i))
#define cast_uint(i) cast(unsigned int, (i))

#define MASK1(n,p) ((~((~(Instruction)0) << (n))) << (p))
#define getarg(i,pos,size) (cast_int(((i) >> (pos)) & MASK1(size,0)))
#define GETARG_Bx(i) getarg(i, POS_Bx, SIZE_Bx)
#define GETARG_sBx(i) (GETARG_Bx(i) - OFFSET_sBx)
#define SETARG_sBx(i,b) ((i) = (((i) & (~(MASK1(SIZE_Bx,POS_Bx)))) | ((cast_uint((b) + OFFSET_sBx) << POS_Bx) & MASK1(SIZE_Bx,POS_Bx))))
#define CREATE_ABx(o,a,bc) ((cast(Instruction, o) << POS_OP) | (cast(Instruction, a) << POS_A) | (cast(Instruction, bc) << POS_Bx))

int main(void) {
  Instruction i = CREATE_ABx(1, 0, 2 + OFFSET_sBx);
  if (MASK1(17, 0) != 131071u) return 1;
  if (GETARG_Bx(i) != 65537) return 2;
  if (GETARG_sBx(i) != 2) return 3;
  SETARG_sBx(i, -1);
  if (GETARG_sBx(i) != -1) return 4;
  return 42;
}
