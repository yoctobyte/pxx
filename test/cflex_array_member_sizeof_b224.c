/* A flexible array member `T x[]` (C99 6.7.2.1) contributes 0 to sizeof and is
   still addressable. It was parsed as [1] -> sizeof over-counted one element. */
typedef unsigned char u8;
struct S { u8 a, b; u8 c[2]; };          /* 4 */
struct V { struct S s; u8 t[16]; u8 x; }; /* 21 */
struct Wr { struct V t; struct S s[]; };  /* flex: sizeof == sizeof(V) */
struct Fi { int n; int r[]; };            /* scalar flex */
int main(void) {
  return (sizeof(struct Wr) == sizeof(struct V) && sizeof(struct Fi) == sizeof(int)) ? 42 : 1;
}
