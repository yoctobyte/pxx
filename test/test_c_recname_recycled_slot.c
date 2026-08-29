/* bug-a-allocarray-leaves-recname-stale-on-a-recycled-symbol-slot
 *
 * The SILENT face of the defect that test_rust_recname_recycled_slot.rs
 * catches loudly. AllocArray writes ElemRecName and never RecName; slots are
 * recycled; so `a` inherits the record id of the by-value `struct B` param of
 * the function declared before it, and _Generic resolves the array to
 * `struct B`.
 *
 * gcc says "other" (an array of A is neither A nor B). pxx said "B".
 * It compiled clean, ran clean, and printed a wrong answer -- the failure
 * mode that has no location.
 *
 * The mechanism was confirmed by two variants that are NOT in this file
 * because they need the function removed or retyped: delete `by_value`, or
 * change its parameter to `struct B *`, and pxx agreed with gcc even before
 * the fix. A pointer param allocates no record symbol, so it leaves a clean
 * slot behind.
 *
 * `ctl` is a SECOND array, not a control: before the fix this program printed
 * "B B", so the staleness reached both. It is here because "both arrays" and
 * "only the first" are different bugs, and the expected output distinguishes
 * them.
 */
#include <stdio.h>

struct A { long x; };
struct B { long y; long z; };

void by_value(struct B b, long i) { (void)b; (void)i; }
void by_pointer(struct B *b, long i) { (void)b; (void)i; }

int main(void)
{
    struct A a[4];
    struct A ctl[4];
    a[0].x = 1;
    ctl[0].x = 2;
    /* the case that was wrong: expect "other", not "B" */
    printf("%s\n", _Generic(a, struct A: "A", struct B: "B", default: "other"));
    /* control that was always right, kept so a regression is distinguishable */
    printf("%s\n", _Generic(ctl, struct A: "A", struct B: "B", default: "other"));
    printf("%ld\n", a[0].x + ctl[0].x);
    return 0;
}
