/* bug-c-undeclared-identifier-as-function-pointer-becomes-null: an undeclared
   identifier passed where a KNOWN callee's parameter is a pointer must be a
   hard compile error, not a warning-plus-0-that-crashes-later. */
extern void *bsearch(const void *key, const void *base, unsigned long nmemb,
                      unsigned long size,
                      int (*compar)(const void *, const void *));
static int arr[4] = {1, 3, 5, 7};
int main(void) {
  int key = 5;
  bsearch(&key, arr, 4, sizeof(int), undeclared_cmp);
  return 0;
}
