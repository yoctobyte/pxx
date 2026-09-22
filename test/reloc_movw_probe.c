/* A probe that REACHES THE EXTERNAL-CALL ARM, which the main reloc probe does
 * not. Measured 2026-09-22: test/reloc_resolve_probe.c produces 1355
 * relocations on aarch64 and ZERO of them are movz/movk, because pxx resolves
 * printf from its own crtl and emits no undefined symbol at all. A headline
 * count over that object says nothing about the arm that reaches an extern,
 * which is the newest and most error-prone part of the aarch64 writer.
 *
 * WHY dlopen AND NOT SOMETHING FAMILIAR. It has to be a function pxx does NOT
 * implement, or the reference never becomes an undefined symbol and the arm is
 * not reached. Measured across getpid, nanosleep, sysconf and getpriority: all
 * four are provided by pxx's own crtl (or refused), and produce zero movz/movk.
 * dlopen and dlclose each produce one R_AARCH64_MOVW_UABS_G0_NC and one G1_NC
 * over their own UND symbol.
 *
 * TWO EXTERNS AND NOT ONE, DELIBERATELY. With a single extern every call site
 * necessarily names the only GOT slot there is, so a writer that pointed every
 * site at slot zero would pass. Two make "each site names ITS OWN slot" a
 * claim that can fail, and the coherence check in the harness asserts exactly
 * that -- with its own control that an addend moved by one slot is rejected.
 *
 * IT IS NEVER CALLED, AND THE GUARD IS NOT CONSTANT-FOLDABLE. `argc > 99` is
 * false in every run and unknown at compile time, so the call site survives
 * DCE while the program never enters it. That matters because pxx's executable
 * for this source is DYNAMICALLY LINKED and this box has no
 * /lib/ld-linux-aarch64.so.1, so the binary cannot run under qemu -- the
 * executable is read for its BYTES, never executed. Nothing here may depend on
 * the call actually happening.
 *
 * The printf line is kept identical to the main probe's so the same witness
 * parsing applies if a loader ever appears here.
 */
int printf(const char *fmt, ...);
extern void *dlopen(const char *path, int flag);
extern int dlclose(void *handle);

int g = 7;
const char msg[] = "reloc";
void *sink;

static const char *rodata_witness(void)
{
    return "pxx-reloc-rodata-witness-do-not-duplicate";
}

int add(int a, int b) { return a + b; }

int main(int argc, char **argv)
{
    (void)argv;
    if (argc > 99) { sink = dlopen("never", 0); if (dlclose(sink)) return 2; }
    printf("%d %p %p %p\n", add(g, 35), (void *)&g, (void *)msg,
           (void *)rodata_witness());
    return 0;
}
