/* SPDX-License-Identifier: MPL-2.0 */
/* Block-scope static with an initializer must run the initializer ONCE, not
   on every call (bug-c-static-local-initializer-reruns-every-call: the
   storage moved to BSS but the init assignment stayed inline in the body,
   silently resetting the state each entry). Exit 42 on success. */

int counter(void) {
    static int n = 10;
    n = n + 1;
    return n;
}

int base = 100;

int computed(void) {
    static int c = 0;      /* explicit zero initializer (masked the bug) */
    static int seeded;     /* implicit zero (always worked) */
    c = c + base;          /* c grows 100, 200, 300 across calls */
    seeded = seeded + 1;
    return c + seeded;
}

int multi(void) {
    static int a = 1, b = 2;   /* multi-declarator static line */
    a = a + b;
    return a;
}

int main(void) {
    int ok = 1;
    if (counter() != 11) ok = 0;
    if (counter() != 12) ok = 0;
    if (counter() != 13) ok = 0;
    if (computed() != 101) ok = 0;   /* 100 + 1 */
    if (computed() != 202) ok = 0;   /* 200 + 2 */
    if (multi() != 3) ok = 0;        /* 1+2 */
    if (multi() != 5) ok = 0;        /* 3+2 */
    return ok ? 42 : 1;
}
