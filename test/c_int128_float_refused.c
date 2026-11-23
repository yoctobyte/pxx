/* The aarch64 half of a row that once also asserted x86-64 refused an
   __int128 -> double conversion; that conversion exists now
   (c_int128_float_conversion). Other targets still refuse the type itself.
   feature-c-int128-other-targets-float-and-narrow-modes */
__int128 x = 5;
int main(void) { double d = (double)x; return (int)d; }
