/* A pointer to a pointer typedef, or to a typeof of a pointer, keeps the
   struct two levels down: sizeof(**q), typeof(*q) and ->member through it.
   NetBSD atomic_load_consume(&fdp->fd_dt)->dt_ff[0] is the shape (rump fd_free).
   bug-c-a-pointer-to-a-pointer-typedef-loses-the-pointee-two-levels-down */
#include <stdio.h>
typedef struct dt { unsigned nf; struct dt *link; void *dt_ff[20]; } dt_t;
typedef struct fd { long lock; dt_t *fd_dt; dt_t builtin; unsigned char dfd[6][48]; } fd_t;
typedef dt_t *dtp;
static dt_t B; static dt_t *P = &B; static dt_t **PP = &P; static fd_t F;
int main(void) {
  fd_t *fdp = &F; dtp *q5 = PP; __typeof__(P) *q3 = PP; __typeof__(dt_t *) *q4 = PP;
  __typeof__(*q3) a3 = *q3; __typeof__(*q4) a4 = *q4; __typeof__(*(&fdp->fd_dt)) a7;
  B.nf = 7; B.dt_ff[0] = &B; fdp->fd_dt = &fdp->builtin; fdp->builtin.dt_ff[0] = (void *)fdp->dfd[0]; a7 = fdp->fd_dt;
  printf("%d %d %d %d %d %d\n", (int)sizeof(**q5), (int)sizeof(**q3), (int)sizeof(*a3), (int)sizeof(*a4), (int)sizeof(*a7), (*q5)->nf);
  printf("%d %d\n", ({ const volatile __typeof__(*(&fdp->fd_dt)) *p = (&fdp->fd_dt); const __typeof_unqual__(*(p)) v = *(p); v; })->dt_ff[0] == (void *)fdp->dfd[0],
         ({ const volatile __typeof__(*PP) *q = PP; const __typeof_unqual__(*q) v = *q; v; })->dt_ff[0] == &B);
  return 0; }
