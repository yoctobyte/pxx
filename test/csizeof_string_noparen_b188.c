/* b188: unparenthesized `sizeof "lit"` is the char-ARRAY size (decoded
   length + NUL), not the pointer size. tcc's ld path seeks with
   `sizeof ARMAG - 1` (ARMAG = "!<arch>\n"): the pointer-size default gave 7
   instead of 8, every archive member read off by one -> "invalid archive". */
#define ARMAG "!<arch>\n"
int main(void)
{
    unsigned long file_offset = sizeof ARMAG - 1;
    int b = sizeof "ab";
    int c = sizeof ARMAG;
    if (file_offset != 8) return 1;
    if (b != 3) return 2;
    if (c != 9) return 3;
    if (sizeof("xy") != 3) return 4;   /* parenthesized stays right */
    return 42;
}
