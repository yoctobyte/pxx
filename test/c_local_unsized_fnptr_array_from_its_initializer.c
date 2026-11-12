/* A block-scope array of function pointers sized by its initializer,
   `long (*gens[])(...) = { f, g, ... };` (Gibux's fs/procfs.c), and a sized
   one with a short list, whose remaining elements C zero-fills. Before
   2026-11-12 the unsized form was "expected C expression" and the short list
   left the tail as whatever the stack held (dirty() makes sure it holds
   something). Output is gcc's. */
#include <stdio.h>
#include <stddef.h>
#include <string.h>

static long a(int x, char *s, size_t n) { return x + 1; }
static long b(int x, char *s, size_t n) { return x * 10; }
static long (*gfs[])(int, char *, size_t) = { a, b };

static void __attribute__((noinline)) dirty(void)
{
    volatile char junk[512];
    memset((char *)junk, 0x5a, sizeof junk);
}

static void __attribute__((noinline)) run(void)
{
    long (*fs[])(int, char *, size_t) = { a, b, a, };
    long (*fs2[3])(int, char *, size_t) = { &b };
    printf("%ld %ld %ld %zu\n", fs[0](1, 0, 0), fs[1](2, 0, 0), fs[2](3, 0, 0),
           sizeof fs / sizeof fs[0]);
    printf("%ld %d %d %ld\n", fs2[0](4, 0, 0), fs2[1] == 0, fs2[2] == 0, gfs[1](5, 0, 0));
}

int main(void)
{
    dirty();
    run();
    return 0;
}
