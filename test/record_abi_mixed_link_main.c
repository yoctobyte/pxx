/* THE THIRD, INDEPENDENT COPY. gcc compiles this main and its own struct
   definitions; the pxx C frontend compiles record_abi_mixed_link_pxx.c and the
   pxx Pascal frontend compiles record_abi_mixed_link_pxx.pas, from the same
   fields. All three answers are compared, because two of them come from one
   compiler and would agree by construction -- which is the exact state this
   replaced: every frontend's i386 layout was self-consistent, so a whole
   program agreed with itself while disagreeing with the platform.

   The row that matters is the LAST one. `GMix` is a Pascal `cvar` global; this
   main writes both fields through its own struct definition and Pascal reads
   them back. Before the fix that read `y` from offset 8 where C had written it
   at 4, and returned a wrong VALUE with no diagnostic anywhere -- the offsets
   above only say the layouts differ, this says what it costs.

   The mismatch line names which of the three disagrees, so a failure does not
   need a debugger to attribute.
   bug-a-pascal-nilpy-rust-and-zig-over-align-an-8-byte-member-on-i386 */
#include <stdio.h>
#include <stddef.h>
struct MIX   { int a; double y; };
struct CHARQ { unsigned char c; long long q; };
struct WIDEC { double y; unsigned char c; };
struct NEST  { int h; struct MIX inner; };
extern int c_size(int), c_off(int), p_size(int), p_off(int);
extern int p_mix_a(void), p_mix_y_is(double);
extern struct MIX GMix;
static const char *nm[4] = {"MIX","CHARQ","WIDEC","NEST"};
int main(void){
  int gs[4], go[4], k, bad=0;
  gs[0]=sizeof(struct MIX);   go[0]=offsetof(struct MIX,y);
  gs[1]=sizeof(struct CHARQ); go[1]=offsetof(struct CHARQ,q);
  gs[2]=sizeof(struct WIDEC); go[2]=offsetof(struct WIDEC,c);
  gs[3]=sizeof(struct NEST);  go[3]=offsetof(struct NEST,inner);
  for(k=0;k<4;k++){
    printf("%-6s gcc=%2d/%2d  pxx-C=%2d/%2d  pxx-Pascal=%2d/%2d",
           nm[k], gs[k], go[k], c_size(k), c_off(k), p_size(k), p_off(k));
    if (c_size(k)!=gs[k]||c_off(k)!=go[k]||p_size(k)!=gs[k]||p_off(k)!=go[k]) { printf("   MISMATCH"); bad=1; }
    printf("\n");
  }
  GMix.a = 4242; GMix.y = 2.5;
  printf("round-trip a=%d y=%d\n", p_mix_a(), p_mix_y_is(2.5));
  if (p_mix_a()!=4242 || !p_mix_y_is(2.5)) bad=1;
  return bad;
}
