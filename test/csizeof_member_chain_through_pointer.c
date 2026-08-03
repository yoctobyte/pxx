/* sizeof(p->arr) where the chain is longer than ONE link. `->` and `.` both
   lex as tkDot, and the sizeof member walk stopped after the first field: it
   sized the intermediate POINTER (8) and let the balanced-paren scan swallow
   the rest. Direct `.` access was right, which is why this survived.

   Where the real array is SMALLER than a pointer, the bogus 8 is a BOUND that
   OVERFLOWS — `memset(h.s->buf, 'X', sizeof(h.s->buf))` wrote 8 bytes into 4
   and clobbered the adjacent field. Found via vendored pdfgen writing a
   truncated PDF /CreationDate against a gcc-built oracle.
   bug-cfront-sizeof-array-member-through-pointer-gives-pointer-size */

struct info   { char title[64]; char date[64]; };
struct doc    { struct info *info; };
struct small  { char buf[4]; int guard; };
struct holder { struct small *s; };
struct deep   { struct doc *d; };

int main(void) {
    struct info i;   struct doc d;    struct doc *pd = &d;
    struct small sm; struct holder h;
    struct deep dp;
    d.info = &i;
    h.s = &sm;
    dp.d = &d;

    if (sizeof(struct info) != 128) return 1;
    if (sizeof(i.date) != 64) return 2;              /* direct: was already right */
    if (sizeof(d.info->date) != 64) return 3;        /* two links: was 8 */
    if (sizeof(pd->info->date) != 64) return 4;      /* three links: was 8 */
    if (sizeof(dp.d->info->title) != 64) return 5;   /* four links */

    /* Smaller than a pointer: the wrong answer is an overflowing BOUND. */
    if (sizeof(h.s->buf) != 4) return 6;
    sm.guard = 0x41414141;
    { unsigned k; for (k = 0; k < sizeof(h.s->buf); k++) h.s->buf[k] = 'X'; }
    if (sm.guard != 0x41414141) return 7;            /* was 0x58585858 */

    /* An element THROUGH the chain is still one element, not the array. */
    if (sizeof(d.info->date[0]) != 1) return 8;
    if (sizeof(d.info->date) / sizeof(d.info->date[0]) != 64) return 9;

    return 42;
}
