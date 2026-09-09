/* THE NEGATIVE CONTROL for the call-in-a-VLA-bound fix. A declared function is
   tolerated in an array DIMENSION, where it is a VLA bound, and nowhere else --
   gcc says "initializer element is not constant" for the shape below and so
   must we. Without this row the fix for dpkg.c silently turns every call in a
   file-scope initializer into a fold of 0, which is the exact class a157e88ee
   was landed to stop.

   The message is asserted, not merely the refusal: the old one called `f' an
   UNDECLARED identifier, which is a false statement about a function declared
   two lines above it, and a reader who believed it went looking for a missing
   header. */
static int f(void) { return 1; }
static int x = f();
int main(void) { return x; }
