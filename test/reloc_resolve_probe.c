/* Probe for tools/reloc_resolve_check.py.
 *
 * It has to EXPORT something -- pxx refuses an object that defines no linkable
 * symbol -- and it has to produce relocations of more than one kind, or the
 * harness would resolve a single class while reporting a denominator that
 * reads as coverage. `g` gives a .bss reference, the format string a .data
 * one, and `add` an internal direct call.
 *
 * The printed value is deliberately not 0, 1, or a repeat of an input: where a
 * wrong relocation can resolve to a default, an expected value that COLLIDES
 * with the default is a row that cannot fail. 42 is neither operand. */
int printf(const char *fmt, ...);
int g = 7;
int add(int a, int b) { return a + b; }
int main(void) { printf("%d\n", add(g, 35)); return 0; }
