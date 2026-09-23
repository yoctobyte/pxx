/* A READ through a pointer parameter must lower to a DEREFERENCE, not to
 * pointer arithmetic. Reads only, deliberately -- see below.
 *
 * This is the SILENT half of
 * bug-a-xtensa-cannot-lower-a-store-through-a-pointer-so-no-c-program-that-writes-through-a-parameter-compiles.
 * With the pointee-shape carriers left at their zero-initialised 0 (a valid
 * ArrType row, where the contract says -1), CDerefDecayStride took every `*p`
 * for the no-op deref of a pointer-to-ARRAY and rewrote it as `p + 0`. A STORE
 * through that could not be lowered as an lvalue and refused loudly; a READ
 * lowered fine and yielded the POINTER.
 *
 * WHY THIS FILE HAS NO STORE IN IT, AND THAT IS THE ENTIRE POINT
 * -------------------------------------------------------------
 * Its sibling c_store_and_read_through_a_pointer_param.c carries both, and
 * under the unfixed compiler it does not get this far: the store refuses first,
 * so the AST dump for the read is EMPTY and the assertion fails because nothing
 * was printed. That is the right verdict for the wrong reason -- an empty dump
 * is what a rename, a flag change or a missing file also produce.
 *
 * With reads alone the unfixed compiler COMPILES this, and the dump then shows
 * the defect itself: AN_BINOP kind=5 with ival=70 (tkPlus) where there must be
 * AN_DEREF kind=36. So the assertion discriminates between the two lowerings
 * instead of between compiling and not compiling, and its positive control is a
 * real one -- measured against pinned v416, which prints kind=5 here.
 *
 * It also guards the repair that would otherwise pass: special-casing the
 * LVALUE path to make the store compile would turn every compile row green and
 * leave the read still answering an address.
 *
 * No libc call, so it serves the --emit-obj rows on targets that cannot link.
 */

char read_char(char *d) { return *d; }
int  read_int (int *p)  { return *p; }

int main(void)
{
    char c = 65;
    int  n = 7;
    int  rc = 0;
    if (read_char(&c) != 65) rc |= 1;
    if (read_int(&n)  != 7)  rc |= 2;
    return rc;
}
