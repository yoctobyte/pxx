/* `extern T * const a, * const b, * const c;` declares three EXTERNS. b and c
   came out defined (4 bytes of .bss each), and a rump link then said
   `multiple definition`. Checked with nm: all three are U.
   bug-c-a-later-declarators-const-after-the-star-was-not-skipped */
struct d { int x; };
extern const struct d * const a, * const b, * const c;
int f(void) { return a->x + b->x + c->x; }
