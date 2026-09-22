/* Probe for tools/reloc_resolve_check.py.
 *
 * It has to EXPORT something -- pxx refuses an object that defines no linkable
 * symbol -- and it has to produce relocations of more than one kind, or the
 * harness would resolve a single class while reporting a denominator that
 * reads as coverage.
 *
 * IT ALSO HAS TO WITNESS ITS OWN SECTION BASES, and that is the whole reason
 * for the two %p. Where no linker exists the harness derives each section's
 * base by majority vote over the relocations naming it -- and a vote derived
 * FROM the relocations, then used to CHECK them, matches by construction. A
 * UNIFORM offset error in every reference to one section shifts the derived
 * base by exactly the same amount, all votes agree, and the comparison is
 * byte-for-byte clean. Unanimity is blind to it precisely BECAUSE it is
 * unanimous: the minority is the only channel carrying signal, so zero
 * minority is zero signal rather than maximum confidence (frankuser,
 * 2026-09-22).
 *
 * Printing &g and msg gives the harness those two addresses from the RUNNING
 * program, which no relocation arithmetic of its own produced. Subtracting the
 * object's own symbol values yields a base the vote cannot have influenced,
 * and a uniform shift is then a mismatch rather than a clean run.
 *
 * The printed value is deliberately not 0, 1, or a repeat of an input: where a
 * wrong relocation can resolve to a default, an expected value that COLLIDES
 * with the default is a row that cannot fail. 42 is neither operand. */
int printf(const char *fmt, ...);
int g = 7;
const char msg[] = "reloc";

/* A STRING LITERAL HAS NO SYMBOL, so a .rodata base cannot be witnessed
 * through the symbol table the way &g and msg are. It can be witnessed by
 * CONTENT: this text appears exactly once in the object's .rodata, the harness
 * finds its offset by searching the section bytes, the program prints its
 * address, and the difference is a .rodata base that no relocation arithmetic
 * produced. The string is long and odd so that "exactly once" is true and
 * checkable rather than assumed. */
static const char *rodata_witness(void)
{
    return "pxx-reloc-rodata-witness-do-not-duplicate";
}

int add(int a, int b) { return a + b; }
int main(void)
{
    printf("%d %p %p %p\n", add(g, 35), (void *)&g, (void *)msg,
           (void *)rodata_witness());
    return 0;
}
