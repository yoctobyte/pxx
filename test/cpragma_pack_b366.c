/* #pragma pack(N) / pack() / pack(push,N) / pack(pop): the alignment cap must
   be APPLIED, not parsed away — struct A used to lay out as 8/4 instead of
   gcc's 5/1, a silent ABI mismatch for any packed on-disk/on-wire structure
   (bug-c-pragma-pack-ignored, b366). Expected output = gcc's exactly. */
#include <stdio.h>
#include <stddef.h>
#pragma pack(1)
struct A { char c; int i; };
#pragma pack()
struct B { char c; int i; };
#pragma pack(push, 2)
struct C { char c; int i; };
#pragma pack(pop)
struct D { char c; short s; int i; };
int main(void) {
  printf("A=%d offA=%d\n", (int)sizeof(struct A), (int)offsetof(struct A, i));
  printf("B=%d offB=%d\n", (int)sizeof(struct B), (int)offsetof(struct B, i));
  printf("C=%d offC=%d\n", (int)sizeof(struct C), (int)offsetof(struct C, i));
  printf("D=%d offD=%d\n", (int)sizeof(struct D), (int)offsetof(struct D, i));
  return 0;
}
