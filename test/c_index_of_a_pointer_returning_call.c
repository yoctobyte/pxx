/* `f(x)[i].member` on a call returning a pointer to struct: the record was
   resolved as the call's own (none), so the member read and wrote offset 0
   (Gibux fs/ext2.c: `ext_index(h)[pick].leaf_lo` read `.block`, and ext4
   files past 4 extents lost data). Through a function pointer the element
   stride was lost too: `fi()[2]` on `int *(*)(void)` stepped by bytes.
   Built by pxx and by gcc; the outputs must match.
   bug-c-a-member-of-an-indexed-pointer-returning-call-reads-offset-0 */
#include <stdint.h>
#include <stdio.h>

struct hdr { uint16_t magic, entries, max, depth; uint32_t generation; };
struct idx { uint32_t block; uint32_t leaf_lo; uint16_t leaf_hi, unused; };

static struct idx *index_of(struct hdr *h) { return (struct idx *)(h + 1); }
static uint32_t w[15];

struct pair { unsigned block, leaf_lo; };
static struct pair arr[2] = {{11, 777}, {12, 778}};
static struct pair *get(void) { return arr; }
static int *geti(void) { static int v[3] = {5, 6, 7}; return v; }

int main(void)
{
    struct hdr *r = (struct hdr *)w;
    w[3] = 11; w[4] = 777; w[6] = 21; w[7] = 888;
    int k = 1;
    printf("ext %u %u %u %u %u\n", index_of(r)[0].leaf_lo, index_of(r)[0].block,
           index_of(r)[k].leaf_lo, index_of(r)[k].block, index_of(r)->leaf_lo);

    struct pair *(*fp)(void) = get;
    int *(*fi)(void) = geti;
    get()[1].leaf_lo = 5;
    fp()[0].leaf_lo += 1;
    printf("direct %u %u %u\n", get()[0].leaf_lo, get()[1].leaf_lo, get()[1].block);
    printf("ind %u %u %u %u %d %d\n", fp()[0].block, fp()[1].block, fp()[0].leaf_lo,
           (*fp)()[1].leaf_lo, fi()[2], *(fi() + 1));
    return 0;
}
