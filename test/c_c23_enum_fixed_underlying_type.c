/* C23 6.7.2.2: an enum with a fixed underlying type has that type's size,
   alignment and signedness, at its definition and at every later `enum Tag`.
   FreeBSD's sys/types.h (__enum_uint8_decl) is the shape that needed it.
   feature-c-c23-enum-with-a-fixed-underlying-type. Expected output is gcc's. */
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>

#define __enum_uint8_decl(name) enum enum_ ## name ## _uint8 : uint8_t
#define __enum_uint8(name)      enum enum_ ## name ## _uint8

__enum_uint8_decl(vtype) { VNON, VREG, VDIR, VBAD = 200 };
enum small16 : short { S_NEG = -2, S_ONE = 1 };
typedef enum wide : unsigned long long { W_BIG = 1 } wide_t;
enum plain { P_A, P_B };
enum bf { BF_A, BF_B };

struct vnode {
  __enum_uint8(vtype) v_type;
  char v_tag;
  enum small16 s;
  wide_t w;
};
struct withbf {
  enum bf : 3;          /* an unnamed bitfield, not C23's fixed type */
  enum bf kind : 2;
  int after;
};

static __enum_uint8(vtype) pick(int x) { return x ? VBAD : VREG; }

int main(void) {
  __enum_uint8(vtype) t = pick(1);
  enum small16 s = S_NEG;
  struct withbf b = { .kind = BF_B, .after = 9 };
  printf("sizeof vtype %zu small16 %zu wide %zu plain %zu\n",
         sizeof(__enum_uint8(vtype)), sizeof(enum small16), sizeof(wide_t), sizeof(enum plain));
  printf("struct vnode size %zu offsets %zu %zu %zu %zu\n", sizeof(struct vnode),
         offsetof(struct vnode, v_type), offsetof(struct vnode, v_tag),
         offsetof(struct vnode, s), offsetof(struct vnode, w));
  printf("t %d (unsigned: %d) s %d enum value VBAD %d\n", (int)t, (__enum_uint8(vtype))-1 > 0, (int)s, VBAD);
  t = (__enum_uint8(vtype))257;   /* wraps in 8 bits */
  printf("wrapped %d, bitfield kind %d after %d sizeof withbf %zu\n", (int)t, (int)b.kind, b.after, sizeof(struct withbf));
  return 0;
}
