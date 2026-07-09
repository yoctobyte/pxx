/* b207: C switch as labels-on-statements (bug-c-switch-nonblock-and-duffs-device,
   c-testsuite 00051/00143).
   - non-compound switch body (`switch(x) case 0: stmt;`)
   - case/default labels on nested statements + fallthrough
   - Duff's device: case labels interleaved with a do-while body; dispatch must
     jump straight INTO the loop, then subsequent iterations run the full body.
   Returns 42 on success. */

int copy_duff(short *to, short *from, int count) {
    int n = (count + 7) / 8;
    switch (count % 8) {
    case 0: do { *to++ = *from++;
    case 7:      *to++ = *from++;
    case 6:      *to++ = *from++;
    case 5:      *to++ = *from++;
    case 4:      *to++ = *from++;
    case 3:      *to++ = *from++;
    case 2:      *to++ = *from++;
    case 1:      *to++ = *from++;
            } while (--n > 0);
    }
    return 0;
}

int main(void) {
    short a[39], b[39];
    int i, x = 0, hits = 0;

    /* non-compound switch body */
    switch (x)
        case 0:
            hits = 1;
    if (hits != 1) return 1;

    /* fallthrough through a braced body */
    switch (x) {
        case 0: hits = hits + 10;   /* falls through */
        case 1: hits = hits + 100;
    }
    if (hits != 111) return 2;

    for (i = 0; i < 39; i++) { a[i] = i; b[i] = 0; }
    copy_duff(b, a, 39);
    for (i = 0; i < 39; i++)
        if (a[i] != b[i]) return 3;

    return 42;
}
