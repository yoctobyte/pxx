/* Fixture for bug-n-a-c-header-import-lowercases-the-library-name-so-gl-does-not-link.

   There is no `libnolib.so` on any machine, and that is the entire point: the
   compiler derives a DT_NEEDED soname from this file's NAME, which is not a
   library name and here cannot be one. Referencing the function below must be a
   COMPILE error rather than a green build that dies at exec; importing the
   header without referencing it must still work, because an unreferenced import
   emits no DT_NEEDED and is a perfectly good program.

   Hermetic on purpose -- it asserts the guard's behaviour without depending on
   which libraries this box happens to have installed. */
#define NOLIB_MARKER 7
int nolib_add(int a, int b);
