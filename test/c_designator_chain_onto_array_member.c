/* A designator CHAIN ending on an array member, against gcc: `.d.magic =
 * {"littlefs"}` (a char array from a string, braced or not) and `.d.root =
 * {a, b}` (an array from a list), local and static. The chain's last member
 * was initialised as a scalar: the string stored its address, the list kept
 * only its first element. littlefs v1 builds its superblock this way, so
 * micropython's VfsLfs1 could not mount what it had just formatted.
 * Not covered: a chain ending in an index into a 2-D member, `.d.m2[1] = {8, 9}`
 * (bug-c-a-designator-ending-in-an-index-into-a-2d-member-stores-a-list-as-one-scalar).
 * bug-c-a-chained-designator-onto-an-array-member-stores-one-scalar */
#include <stdio.h>
#include <string.h>
struct In { unsigned char t; unsigned x; char magic[8]; unsigned root[2]; short m2[2][2]; };
struct Out { unsigned off; struct In d; };
struct Flat { int a; char m[8]; };
static void show(const char *k, const char *m) { printf("%s %.8s\n", k, m); }
int main(void) {
  struct Out a = { .off = 1, .d.t = 2, .d.magic = {"littlefs"}, .d.x = 3 };
  struct Out b = { .off = 1, .d.magic = "littlefs" };
  struct Out c = { .d = { .magic = {"littlefs"} } };
  struct Flat d = { .m = {"abcdefgh"} };
  struct Flat e = { 1, {"abcdefgh"} };
  struct Flat f = { 1, "abc" };
  static struct Out g = { .off = 1, .d.magic = {"littlefs"} };
  show("nested-desig-braced", a.d.magic); printf("  %u %u %u\n", a.off, a.d.t, a.d.x);
  show("nested-desig-bare", b.d.magic);
  show("nested-brace", c.d.magic);
  show("flat-desig-braced", d.m);
  show("positional-braced", e.m);
  show("positional-bare", f.m);
  show("static-nested-braced", g.d.magic);
  { unsigned r0 = 7, r1 = 9;
    struct Out h = { .off = 1, .d.root = {r0, r1}, .d.x = 5, .d.m2 = {{1, 2}, {3, 4}} };
    struct Out i = { .d.root = {r0}, .d.m2 = {{0, 0}, {8, 9}} };
    static struct Out j = { .d.root = {11, 12}, .d.m2 = {1, 2, 3} };
    printf("array-members %u %u %u | %u %u %d %d %d %d | %u %u %d %d %d %d\n", h.d.root[0], h.d.root[1], h.d.x,
           i.d.root[0], i.d.root[1], i.d.m2[0][0], i.d.m2[0][1], i.d.m2[1][0], i.d.m2[1][1],
           j.d.root[0], j.d.root[1], j.d.m2[0][0], j.d.m2[0][1], j.d.m2[1][0], j.d.m2[1][1]);
    printf("h.m2 %d %d %d %d\n", h.d.m2[0][0], h.d.m2[0][1], h.d.m2[1][0], h.d.m2[1][1]); }
  return 0;
}
