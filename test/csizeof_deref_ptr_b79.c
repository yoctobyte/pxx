/* sizeof(*p) must yield the size of the pointed-at type, not the pointer size.
   Previously the operand of `sizeof` starting with `*` fell through to the
   default pointer size (8), so e.g. lua's
   `memcpy(ra+4, ra, 3*sizeof(*ra))` (ra a 16-byte StackValue*) copied 3*8=24
   bytes instead of 3*16=48, dropping the generic-for state/control values and
   breaking ipairs/pairs. */

extern long __pxx_write(int, const void *, unsigned long);

typedef struct Big { long a; long b; } Big;             /* 16 bytes */
typedef union Cell { Big v; struct { long x; short d; } s; } Cell;  /* 16 */

int main(void) {
  Big big; Big *bp = &big;
  Cell arr[4]; Cell *cp = arr;
  int n[3]; int *ip = n;

  if (sizeof(Big) != 16) return 1;
  if (sizeof(*bp) != 16) return 2;      /* deref of struct ptr */
  if (sizeof(Cell) != 16) return 3;
  if (sizeof(*cp) != 16) return 4;      /* deref of union ptr */
  if (3 * sizeof(*cp) != 48) return 5;  /* the lua memcpy size */
  if (sizeof(*ip) != sizeof(int)) return 6;  /* deref of scalar ptr */
  if (sizeof(bp) != sizeof(void *)) return 7;  /* the pointer itself */
  if (sizeof(cp) != sizeof(void *)) return 8;
  return 42;
}
