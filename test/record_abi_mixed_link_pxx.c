/* The C half of the i386 aggregate-layout oracle, compiled by PXX -- not by
   gcc. Its answers are what pxx's C frontend believes; the gcc main carries the
   third, independent copy. See test/record_abi_mixed_link_pxx.pas for why three.
   bug-a-pascal-nilpy-rust-and-zig-over-align-an-8-byte-member-on-i386 */
#include <stddef.h>

struct MIX   { int a; double y; };
struct CHARQ { unsigned char c; long long q; };
struct WIDEC { double y; unsigned char c; };
struct NEST  { int h; struct MIX inner; };

int c_size(int k)
{
  switch (k) {
    case 0: return (int)sizeof(struct MIX);
    case 1: return (int)sizeof(struct CHARQ);
    case 2: return (int)sizeof(struct WIDEC);
    case 3: return (int)sizeof(struct NEST);
  }
  return -1;
}

int c_off(int k)
{
  switch (k) {
    case 0: return (int)offsetof(struct MIX, y);
    case 1: return (int)offsetof(struct CHARQ, q);
    case 2: return (int)offsetof(struct WIDEC, c);
    case 3: return (int)offsetof(struct NEST, inner);
  }
  return -1;
}
