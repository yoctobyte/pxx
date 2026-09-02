/* A file-scope function must NOT shadow a function-pointer PARAMETER of the
   same name inside another function -- and the other function here is crtl's
   own, which is what made this silent.

   crtl's qsort is `void qsort(void*, size_t, size_t, int (*cmp)(...))` and its
   body calls `cmp(prv, cur)`. The C frontend resolved a called name by asking
   FindProc FIRST and only falling back to the symbol table, so a translation
   unit that ALSO defined a file-scope `cmp` re-aimed that call, inside crtl,
   at the user's function. `cmp` is one of the most common names in C.

   Every decoy below is DELIBERATELY WRONG IN A DIFFERENT DIRECTION, because a
   decoy that happens to agree with the real comparator is the case this bug
   was invisible in for as long as it existed: the first repro used a decoy
   named the same as the caller's own comparator and sorted correctly by
   coincidence.

     - cmp    returns 0 always  -> nothing swaps, the array stays as written
     - dcmp   sorts DESCENDING  -> an ascending request comes back reversed

   `decoy` IS the control and it is the only one: it proves the decoy is still
   callable and still returns what it says, so a "fix" that broke or dropped the
   user's own function would be caught here. It is also the only row the pre-fix
   compiler got right.

   `plain` is NOT a control, and calling it one was wrong the first time this
   file was written. It sorts three elements with no decoy passed anywhere, but
   `cmp` is in FILE scope, so it is in scope for that call too -- pre-fix it
   printed 213, unsorted, exactly like the others. It is a third instance of the
   defect, kept because it shows the damage is not confined to the first call in
   the function.

   POSITIVE CONTROL, run rather than asserted. The pre-fix compiler
   (90b2afd68ab7) prints

     asc=53917  desc=53917  found=5  decoy=0  plain=213

   against gcc's

     asc=13579  desc=97531  found=7  decoy=0  plain=123

   -- four of five rows wrong, and `asc` and `desc` wrong IDENTICALLY despite
   requesting opposite orders, which is the tell: both calls ran the same
   function and it was neither of the ones passed. */
#include <stdio.h>
#include <stdlib.h>

static int cmp(const void *a, const void *b) { (void)a; (void)b; return 0; }
static int dcmp(const void *a, const void *b) { return *(const int *)b - *(const int *)a; }

static int by_int(const void *a, const void *b) { return *(const int *)a - *(const int *)b; }

static void show(const char *tag, int *v, int n) {
  int i;
  printf("%s=", tag);
  for (i = 0; i < n; i++) printf("%d", v[i]);
  printf("\n");
}

int main(void) {
  int a[5] = {5, 3, 9, 1, 7};
  int b[5] = {5, 3, 9, 1, 7};
  int c[5] = {1, 3, 5, 7, 9};
  int k = 7;
  int *found;

  qsort(a, 5, sizeof(int), by_int);
  show("asc", a, 5);

  qsort(b, 5, sizeof(int), dcmp);
  show("desc", b, 5);

  found = (int *)bsearch(&k, c, 5, sizeof(int), by_int);
  printf("found=%d\n", found ? *found : -1);

  printf("decoy=%d\n", cmp(&k, &k));
  {
    int p[3] = {2, 1, 3};
    qsort(p, 3, sizeof(int), by_int);
    show("plain", p, 3);
  }
  return 0;
}
