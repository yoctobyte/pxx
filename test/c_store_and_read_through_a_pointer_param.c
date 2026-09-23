/* A store and a read through a POINTER PARAMETER, in a translation unit that
 * pulls no Pascal unit in.
 *
 * WHY THIS FILE EXISTS
 * --------------------
 * `char *f(char *d){ *d = 0; return d; }` refused outright on xtensa with
 * `IR_UNSUPPORTED: frontend could not lower AST node (kind 5)` while compiling
 * on riscv32, i386 and x86-64. The cause was not in the backend and not in the
 * store: LastTypePointerElemArrAi is documented "that ArrType index, else -1"
 * and is a Pascal global, so it STARTS AT 0 -- and 0 is a valid ArrType row.
 * Only ParseTypeKindInner ever assigns it, so a compile that parses no Pascal
 * type at all ran the whole way holding 0, SetPtrElemArrayInfo read row 0 for
 * every pointer symbol it recorded, and CDerefDecayStride then took every `*p`
 * for the no-op deref of a pointer-to-ARRAY and rewrote it as `p + 0`.
 *
 * Every other target parses the RTL first and is left holding -1 by accident,
 * which is the whole reason this looked like an xtensa codegen bug.
 *
 * THE REFUSAL WAS THE SAFE HALF, AND IT IS NOT WHAT THIS FILE IS MOSTLY FOR
 * ------------------------------------------------------------------------
 * A store through the rewritten `p + 0` could not be lowered as an lvalue, so
 * it stopped. A READ could: `char g(char *d){ return *d; }` COMPILED on xtensa
 * and returned the POINTER instead of the pointed-at byte. That is a plausible
 * wrong value a long way from its cause, and no compile-only row can see it --
 * which is why the reads below assert values and not exit codes.
 *
 * WHY EACH READ IS CHECKED TWICE, AGAINST TWO DIFFERENT VALUES
 * ------------------------------------------------------------
 * The broken form yields the ADDRESS. Checking `read_char(cp) == 65` once
 * would let the bug pass whenever the low byte of that address happened to be
 * 65 -- an expected value colliding with the failure value, on a probe whose
 * failure value is not under the test's control. Reading the SAME pointer
 * twice while changing the value behind it removes that: the address does not
 * change between the two reads, so a broken read returns the same number both
 * times and cannot equal 65 and then 66.
 *
 * Deliberately free of any libc call, so the identical source serves the
 * --emit-obj rows on targets that cannot link one.
 *
 * bug-a-xtensa-cannot-lower-a-store-through-a-pointer-so-no-c-program-that-writes-through-a-parameter-compiles
 */

char *store_char(char *d) { *d = 65; return d; }
char  read_char (char *d) { return *d; }
int  *store_int (int *p)  { *p = 7;  return p; }
int   read_int  (int *p)  { return *p; }

int main(void)
{
    int rc = 0;
    char c = 0;
    char *cp = &c;
    int n = 0;
    int *np = &n;

    /* the store: the half that refused */
    if (store_char(cp) != cp) rc |= 1;
    if (c != 65) rc |= 2;
    if (store_int(np) != np) rc |= 4;
    if (n != 7) rc |= 8;

    /* the read: the half that compiled and answered the pointer. Twice, with
       the pointer held fixed and the value moved. */
    c = 65;
    if (read_char(cp) != 65) rc |= 16;
    c = 66;
    if (read_char(cp) != 66) rc |= 32;

    n = 7;
    if (read_int(np) != 7) rc |= 64;
    n = 8;
    if (read_int(np) != 8) rc |= 128;

    return rc;
}
