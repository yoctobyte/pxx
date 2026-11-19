/* C const objects in an x86-64 pxx object: baked ones go to .rodata.<name>
   (SHF_ALLOC only) as gcc places them; ones holding an address, or written
   at start-up, stay writable. Linked into a gcc main by test-emit-obj.
   feature-c-const-objects-go-to-rodata-in-x86-64-objects */
static const int a = 5;
const int ga = 7;
static const int arr[4] = {1, 2, 3, 4};
static const char s[] = "hello";
static const struct { int x; double y; } st = {11, 2.5};
static const char *const tab[] = {"aa", "bb"};
static const int *const pp = &a;
static const int al __attribute__((aligned(32))) = 42;
static int counter = 100;                  /* writable neighbour */
static const double third = 1.0 / 3.0;
const unsigned long long big = 0xFFFFFFFFFFFFFFFFull;

int ro_sum(void) {
  counter++;
  return a + ga + arr[0] + arr[3] + s[1] + st.x + (int)(st.y * 2) + tab[1][0] +
         *pp + al + counter + (int)(third * 300) + (int)(big & 0xff);
}
long ro_aladdr(void) { return (long)&al & 31; }
