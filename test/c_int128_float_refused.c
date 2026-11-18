/* Converting an __int128 to a floating type must be REFUSED BY NAME until a
   correctly rounded conversion exists (gcc's __floattidf): one register holds
   only the low half, so a compiled conversion would be silently wrong above
   2^64. The Makefile row asserts the refusal; the same row compiles this
   file for aarch64 and asserts that target refuses the type itself.
   feature-c-int128-and-attribute-mode */
__int128 x = 5;
int main(void) { double d = (double)x; return (int)d; }
