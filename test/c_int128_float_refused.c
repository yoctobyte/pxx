/* Once two rows; the x86-64 one went when __int128 -> double was lowered
   (c_int128_float_conversion), and aarch64 has __int128 now too. What is
   left: i386 refuses the type itself with gcc's words, as gcc does.
   feature-c-int128-other-targets-float-and-narrow-modes */
__int128 x = 5;
int main(void) { double d = (double)x; return (int)d; }
