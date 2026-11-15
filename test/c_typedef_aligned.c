/* An aligned TYPEDEF aligns what is declared with it: struct members, the
   struct, an alias of it, _Alignof, and globals. packed and #pragma pack
   still cap it (it is the type's own alignment, not a member attribute).
   bug-c-an-aligned-typedef-member-does-not-align-the-member */
#include <stdio.h>
#include <stddef.h>
typedef int al_t __attribute__((aligned(16)));
typedef struct { char c; } __attribute__((aligned(8))) as_t;
typedef double __attribute__((aligned(32))) ad_t;
typedef al_t al2_t;
typedef al_t *alp;
struct m1 { int x __attribute__((aligned(16))); char c; };
struct sa { char c; al_t x; };
struct sb { char c; as_t s; int t; };
struct sc { char c; ad_t d; };
struct sd { char c; al2_t x; };
struct sf { char c; struct sa inner; };
struct __attribute__((packed)) p1 { char c; al_t x; };
#pragma pack(4)
struct p2 { char c; al_t x; };
#pragma pack()
struct p3 { char c; al_t *p; };
struct p4 { char c; alp p; };
al_t g1; char gpad; al_t g2; ad_t g3;
int main(void) {
    printf("m1 %zu %zu\n", sizeof(struct m1), _Alignof(struct m1));
    printf("sa %zu %zu %zu\n", sizeof(struct sa), offsetof(struct sa, x), _Alignof(struct sa));
    printf("sb %zu %zu %zu\n", sizeof(struct sb), offsetof(struct sb, s), offsetof(struct sb, t));
    printf("sc %zu %zu\n", sizeof(struct sc), offsetof(struct sc, d));
    printf("sd %zu %zu\n", sizeof(struct sd), offsetof(struct sd, x));
    printf("sf %zu %zu\n", sizeof(struct sf), offsetof(struct sf, inner));
    printf("p %zu %zu %zu %zu %zu %zu %zu\n", sizeof(struct p1), offsetof(struct p1, x),
           sizeof(struct p2), offsetof(struct p2, x), sizeof(struct p3), offsetof(struct p3, p), sizeof(struct p4));
    printf("sizes %zu %zu %zu %zu %zu %zu\n", sizeof(al_t), _Alignof(al_t), _Alignof(al2_t), _Alignof(ad_t), sizeof(as_t), _Alignof(as_t));
    printf("glob %d %d %d\n", (int)((size_t)&g1 % 16), (int)((size_t)&g2 % 16), (int)((size_t)&g3 % 32));
    return 0;
}
