/* Array-to-pointer DECAY of a FLOAT-element array under an explicit cast.

   `(void*)A` on a `double A[]` used to yield a stack address, not &A[0]: the
   array's rvalue IR_LEA carried the ELEMENT type, so an address node claimed to
   be a double and the backend routed it to an xmm register — the callee read
   whatever stale value sat in the integer register. `int B[]` was correct only
   because tyInt32 shares the general-register class. `A == &A[0]` answered 0,
   with no diagnostic, which is silent memory corruption for every memcpy /
   fwrite / qsort that hands over a double array.

   Covers both element types (double, float), both scopes (file, block), and
   the cast targets the ticket asked for (void*, double*, char*), plus the
   parameter-decay form that always worked — that one is the control.
   bug-c-cast-of-a-float-element-array-to-a-pointer-yields-a-wrong-address

   exits 42 on success. */
static double A[] = {1.5, 2.5, 3.5};
static float  F[] = {1.5f, 2.5f};
static int    B[] = {1, 2, 3};

static int viaparam(void *p, void *want) { return p == want; }

int main(void)
{
  double L[4];
  float  G[4];
  int    ok = 0;

  /* file scope, every cast target */
  ok += ((void*)A          == (void*)&A[0]);
  ok += ((void*)(double*)A == (void*)&A[0]);
  ok += ((void*)(char*)A   == (void*)&A[0]);
  ok += ((void*)(A + 0)    == (void*)&A[0]);
  ok += ((void*)F          == (void*)&F[0]);
  ok += ((void*)(float*)F  == (void*)&F[0]);
  /* block scope */
  ok += ((void*)L          == (void*)&L[0]);
  ok += ((void*)G          == (void*)&G[0]);
  /* the int array: correct before the fix too, so a guard against over-reach */
  ok += ((void*)B          == (void*)&B[0]);
  /* decay through a parameter: the form that always worked (control) */
  ok += viaparam(A, &A[0]);
  ok += viaparam(L, &L[0]);
  ok += viaparam(B, &B[0]);

  if (ok != 12) return 1;
  return 42;
}
