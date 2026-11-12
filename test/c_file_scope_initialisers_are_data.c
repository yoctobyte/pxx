/* File-scope initialisers in every form a kernel writes (Gibux), built with
   --c-static-data (or under --freestanding), where each becomes .data with
   relocations instead of a store run before main. The same file runs with
   and without the flag and prints gcc's output both ways:
   - integer scalars, a large unsigned constant, constant expressions with
     | & ^ << >> ~ / % and enum constants;
   - a byte array, a char array from a string, a float and a double;
   - a string pointer, an array of string pointers with a NULL tail;
   - a designated struct initialiser with a pointer to another global
     (`.tty = &console_tty`), and one to an element/field inside it;
   - a function pointer, an array of them, one to a function defined later;
   - a bit-field struct;
   - a const pointer table to strings (`const char *const names[]`);
   - __attribute__((aligned(N))) on initialised and uninitialised globals. */
#include <stdio.h>
#include <stdint.h>

enum { MODE_A = 3, MODE_B = 9 };
#define S_IFCHR 0020000
#define VMALLOC_BASE 0xFFFFC90000000000ull

struct tty { int index; char name[8]; };
struct file { int kind; int refs; int flags; struct tty *tty; int *pidx; };
struct bits { unsigned a : 3; unsigned b : 5; int c : 7; unsigned d : 1; };

struct tty console_tty = { 7, "ttyS0" };
static int next_pid = 1;
static uint64_t vmalloc_next = VMALLOC_BASE;
static unsigned mode = S_IFCHR | 0620;
static int mixed = ((1 << 4) | 3) ^ (0xF0 & ~0x30) ;
static long divmod = (100 / 7) * 10 + (100 % 7) - (-17 / 4) + (17 >> 2);
static unsigned long ushr = 0xFFFFFFFFul >> 28;
static int en = MODE_A * MODE_B;
static const uint8_t broadcast[6] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F };
static char banner[16] = "gibux";
static double ratio = 2.5;
static float half = -0.5f;
static double from_int = 3;
static char *opt_cwd = "/";
static char *init_argv[4] = { "/init", "-s", 0 };
static const char *const names[] = { "stat", "statm", "status" };
static struct file console_file = { .kind = 2, .refs = 1, .flags = 2, .tty = &console_tty };
static struct file *pick = &console_file;
static int *idx_ptr = &console_tty.index;
static char *name_ptr = &console_tty.name[2];
static struct bits bf = { 5, 17, -9, 1 };
static int square(int x) { return x * x; }
static int later(int x);
static int (*fp)(int) = square;
static int (*ops[])(int) = { square, later, 0 };
static uint8_t page[64] __attribute__((aligned(4096))) = { 1, 2, 3 };
static uint8_t fxa[512] __attribute__((aligned(64)));

static int later(int x) { return x + 100; }

int main(void)
{
    printf("%d %llx %o %d %ld %lu %d\n", next_pid, (unsigned long long)vmalloc_next,
           mode, mixed, divmod, ushr, en);
    printf("%x %x %s %.2f %.2f %.1f\n", broadcast[0], broadcast[5], banner, ratio,
           (double)half, from_int);
    printf("%s %s %s %d\n", opt_cwd, init_argv[0], init_argv[1], init_argv[2] == 0);
    printf("%s %s\n", names[1], names[2]);
    printf("%d %d %d %s %d\n", console_file.kind, console_file.refs,
           console_file.tty->index, console_file.tty->name, console_file.pidx == 0);
    printf("%d %d %s\n", pick->tty == &console_tty, *idx_ptr, name_ptr);
    printf("%u %u %d %u\n", bf.a, bf.b, bf.c, bf.d);
    printf("%d %d %d %d\n", fp(6), ops[0](3), ops[1](1), ops[2] == 0);
    printf("%d %d %lu %lu\n", page[1], page[2], (unsigned long)((uintptr_t)page % 4096),
           (unsigned long)((uintptr_t)fxa % 64));
    next_pid++;
    banner[0] = 'G';
    printf("%d %s\n", next_pid, banner);
    return 0;
}
