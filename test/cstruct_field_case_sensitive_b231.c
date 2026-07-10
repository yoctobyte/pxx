/* b231 (bug-c-duktape-double-formatting): C struct fields are CASE-SENSITIVE.
   FindUField folded case (Pascal heritage), so `b` and `B` collapsed to one
   field — a store to .B clobbered .b and both reads returned the same slot.
   This corrupted duktape's dragon4 numconv ctx (fields `b`=input radix,
   `B`=output radix), scaling every JS double by ~5^k. Per-UClass
   UClsCaseSensFields flag (set by cparser) makes C field lookup exact.
   Exit 42 = pass. */
struct S { int b; int B; };
struct T { double lo; double LO; char Ab; char aB; };
int main(void) {
    struct S s;
    s.b = 10;
    s.B = 2;
    if (s.b != 10) return 1;   /* would be 2 under the case-fold bug */
    if (s.B != 2)  return 2;

    struct T t;
    t.lo = 1.5; t.LO = 9.5;
    t.Ab = 'x'; t.aB = 'y';
    if (t.lo != 1.5) return 3;
    if (t.LO != 9.5) return 4;
    if (t.Ab != 'x') return 5;
    if (t.aB != 'y') return 6;
    return 42;
}
