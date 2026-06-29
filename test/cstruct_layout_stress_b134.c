/* Packed/aligned/nested C struct stress test. Exercises byte-sized _Bool,
   single-bit _Bool bit-fields, nested packed/default/over-aligned records,
   odd offsets, array stride through sizeof, and unaligned field access.
   Exit 42. */

typedef struct {
  char c;
  _Bool b;
  unsigned short w;
  long i;
  char tail;
} Inner;

typedef struct __attribute__((packed)) {
  char c;
  long i;
  _Bool b;
  unsigned short w;
} PackedInner;

typedef struct {
  char c;
  long i __attribute__((aligned(16)));
  _Bool b;
} FieldAligned;

typedef struct __attribute__((aligned(32))) {
  char c;
  int x;
} TypeAligned;

typedef struct __attribute__((packed)) {
  char tag;
  Inner inner;
  PackedInner packed;
  FieldAligned fa;
  long last;
} PackedOuter;

typedef struct {
  char tag;
  PackedInner packed;
  FieldAligned fa;
  TypeAligned ta;
  _Bool done;
} DefaultOuter;

typedef struct {
  unsigned a : 1;
  _Bool b : 1;
  unsigned c : 3;
  unsigned d : 5;
  char tail;
} Bits;

static long off_inner_i(Inner *p) { return (long)&p->i - (long)p; }
static long off_packed_i(PackedInner *p) { return (long)&p->i - (long)p; }
static long off_field_i(FieldAligned *p) { return (long)&p->i - (long)p; }
static long off_default_ta(DefaultOuter *p) { return (long)&p->ta - (long)p; }
static long off_packed_last(PackedOuter *p) { return (long)&p->last - (long)p; }
static long off_bits_tail(Bits *p) { return (long)&p->tail - (long)p; }

int main(void) {
  Inner in;
  PackedInner pi;
  FieldAligned fa;
  TypeAligned ta[2];
  PackedOuter po;
  DefaultOuter def[2];
  Bits bits;

  if (sizeof(_Bool) != 1) return 1;

  if (sizeof(Inner) != 24) return 2;
  if (((long)&in.b - (long)&in) != 1) return 3;
  if (((long)&in.w - (long)&in) != 2) return 4;
  if (off_inner_i(&in) != 8) return 5;
  if (((long)&in.tail - (long)&in) != 16) return 6;

  if (sizeof(PackedInner) != 12) return 7;
  if (off_packed_i(&pi) != 1) return 8;
  if (((long)&pi.b - (long)&pi) != 9) return 9;
  if (((long)&pi.w - (long)&pi) != 10) return 10;

  if (sizeof(FieldAligned) != 32) return 11;
  if (off_field_i(&fa) != 16) return 12;
  if (((long)&fa.b - (long)&fa) != 24) return 13;

  if (sizeof(TypeAligned) != 32) return 14;
  if (((long)&ta[0].x - (long)&ta[0]) != 4) return 15;
  if (((long)&ta[1] - (long)&ta[0]) != 32) return 16;

  if (sizeof(PackedOuter) != 77) return 17;
  if (((long)&po.inner - (long)&po) != 1) return 18;
  if (((long)&po.packed - (long)&po) != 25) return 19;
  if (((long)&po.fa - (long)&po) != 37) return 20;
  if (off_packed_last(&po) != 69) return 21;

  if (sizeof(DefaultOuter) != 128) return 22;
  if (((long)&def[0].packed - (long)&def[0]) != 1) return 23;
  if (((long)&def[0].fa - (long)&def[0]) != 16) return 24;
  if (off_default_ta(&def[0]) != 64) return 25;
  if (((long)&def[0].done - (long)&def[0]) != 96) return 26;
  if (((long)&def[1] - (long)&def[0]) != 128) return 27;

  if (sizeof(Bits) != 4) return 28;
  if (off_bits_tail(&bits) != 2) return 29;

  po.tag = 3;
  po.inner.i = 100;
  po.inner.b = 1;
  po.packed.i = 200;
  po.packed.b = 1;
  po.packed.w = 7;
  po.fa.i = 300;
  po.fa.b = 1;
  po.last = 400;

  if (po.tag + po.inner.i + po.packed.i + po.fa.i + po.last != 1003) return 30;
  if (!po.inner.b || !po.packed.b || !po.fa.b) return 31;
  if (po.packed.w != 7) return 32;

  bits.a = 1;
  bits.b = 1;
  bits.c = 5;
  bits.d = 17;
  bits.tail = 19;
  if (!bits.a || !bits.b || bits.c != 5 || bits.d != 17 || bits.tail != 19) return 33;

  def[0].packed.i = 11;
  def[0].fa.i = 13;
  def[0].ta.x = 17;
  def[0].done = 1;
  if (def[0].packed.i + def[0].fa.i + def[0].ta.x != 41) return 34;
  if (!def[0].done) return 35;

  return 42;
}
