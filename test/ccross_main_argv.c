/* A C `main` actually receives argc and argv, on every target that can run one.

   THE DEFECT THIS EXISTS FOR IS INVISIBLE TO EVERY OTHER C TEST IN THE TREE,
   and that is a property of the failure rather than an oversight: on i386 the
   entry stub handed main its two arguments in the wrong order, so `argc` read
   as a pointer's low bits -- a NEGATIVE number -- and `argv` held the integer 3.
   `if (argc > 1)` is then silently false, so the ordinary shape takes the
   no-arguments path and looks perfectly healthy. ccross_args.c, which is the
   test named after argument passing, exercises calls BETWEEN C functions and
   never reads main's own; it stayed green throughout.
   Measured pre-fix on i386: `argc=-4991340`, and the argv[0] print was skipped
   because the loop never ran. bug-a-i386-c-main-gets-argc-and-argv-swapped.

   So this test READS them, and reads them in the two ways that fail
   differently: argc as a count (a swap makes it negative or absurd) and argv[i]
   as a string (a swap makes the deref segfault, which is the shape a program
   that ignores argc hits). argv[argc] == NULL is checked too, because that is
   the kernel's contract and a stub that synthesised argv rather than pointing
   into the initial stack would satisfy everything above and still break
   iteration that stops on the terminator.

   argv[0] is NOT compared as a string: it is the invocation path, which differs
   between a native run and one under a target runner. It is checked for being
   non-empty, which is what distinguishes a real pointer from a small integer. */
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    int bad = 0;
    int i;

    if (argc != 3) { printf("FAIL argc=%d want 3\n", argc); bad++; }
    if (argv == 0) { printf("FAIL argv is null\n"); printf("ARGV FAIL\n"); return 1; }
    if (argv[0] == 0 || argv[0][0] == 0) { printf("FAIL argv[0] empty\n"); bad++; }
    if (argc > 1 && strcmp(argv[1], "one") != 0) {
        printf("FAIL argv[1]=%s want one\n", argv[1]); bad++;
    }
    if (argc > 2 && strcmp(argv[2], "two") != 0) {
        printf("FAIL argv[2]=%s want two\n", argv[2]); bad++;
    }
    if (argc == 3 && argv[3] != 0) { printf("FAIL argv[argc] not NULL\n"); bad++; }

    /* The loop is the part a swapped argc silently skips, so count the trips
       and assert the count rather than trusting that the prints appeared. */
    i = 0;
    while (i < argc) i++;
    if (i != 3) { printf("FAIL walked %d want 3\n", i); bad++; }

    if (bad == 0) printf("ARGV OK\n"); else printf("ARGV FAIL\n");
    return bad == 0 ? 0 : 1;
}
