/* Records, bitfields, unions and layout — the shapes a member-parser or
   struct-layout change moves. Prints sizes and offsets as well as values,
   because a layout bug that keeps the values right is the expensive kind. */
#include <stdio.h>
#include <string.h>

struct Flags {
  unsigned a : 1;
  unsigned b : 3;
  signed   c : 7;
  unsigned   : 0;      /* forces the next field into a new unit */
  unsigned d : 5;
  long long  e : 40;
};

struct Inner { char tag; int val; };

struct Outer {
  char           name[8];
  struct Inner   in;
  union { int i; float f; unsigned char bytes[4]; } u;
  int          (*fp)(int);
  struct Flags   fl;
};

static int twice(int x) { return x * 2; }
static int square(int x) { return x * x; }

int main(void) {
  struct Outer o;
  struct Flags f;
  unsigned long checksum = 0;
  int i, a, b;

  printf("sizes %d %d %d %d\n", (int)sizeof(struct Flags), (int)sizeof(struct Inner),
         (int)sizeof(struct Outer), (int)sizeof(o.u));
  printf("offs %d %d %d\n", (int)((char *)&o.in - (char *)&o),
         (int)((char *)&o.u - (char *)&o), (int)((char *)&o.fl - (char *)&o));

  memset(&o, 0, sizeof o);
  strcpy(o.name, "corpus");
  o.in.tag = 'z'; o.in.val = -1234;
  o.u.i = 0x01020304;
  o.fp = twice;

  printf("name %s tag %c val %d\n", o.name, o.in.tag, o.in.val);
  printf("union %d %d %d %d\n", o.u.bytes[0], o.u.bytes[1], o.u.bytes[2], o.u.bytes[3]);
  /* SEQUENCED, not printed from one argument list. Argument evaluation order is
     unspecified, gcc evaluates right-to-left, and pxx orders differently on some
     targets -- `printf("%d %d", o.fp(21), (o.fp = square, o.fp(7)))` is legal C
     that legitimately prints two different answers, so a corpus program written
     that way reports a phantom compiler bug. The same rule gcc_diff_probe.sh's
     header records after being burned by it four times. */
  a = o.fp(21);
  o.fp = square;
  b = o.fp(7);
  printf("fp %d %d\n", a, b);

  f.a = 1; f.b = 5; f.c = -3; f.d = 17; f.e = -549755813887LL;   /* fits a signed 40-bit field exactly */
  printf("bits %u %u %d %u %lld\n", f.a, f.b, f.c, f.d, (long long)f.e);

  /* every signed width, so a sign-extension that only works at some widths shows */
  for (i = 1; i <= 7; i++) {
    struct Flags g;
    memset(&g, 0, sizeof g);
    g.c = -1;
    checksum = checksum * 31u + (unsigned long)(g.c & 0xff);
  }
  printf("checksum %lu\n", checksum);
  return 0;
}
