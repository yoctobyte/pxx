/* crtl's getopt, against the shapes that separate a POSIX getopt from glibc's.
   Every expected line here was taken from a glibc-built binary of this same
   file, so the file is its own oracle record.

   Rows 4 and 7 are the ones that matter and the reason PERMUTATION is
   implemented rather than skipped: POSIX stops at the first non-option, so
   `f -a` would leave `-a` as an operand. Every oracle this project diffs
   against is glibc-built, so a POSIX-conformant getopt would have produced a
   difference in exactly the shape the C corpora exist to detect -- and called
   it conformance.

   Row 7 (`f1 -a f2 -o X f3`) is the one a naive implementation gets wrong in a
   way rows 1-6 cannot see: rotating each option to `optind` as it is found
   makes an option's separate ARGUMENT come from the permuted vector, so
   optarg reads "f1" instead of "X". glibc defers the exchange to the next
   option boundary for precisely this reason, and so do we.

   Rows 9-11 are the "--" cases. glibc does not delete the marker; it rotates
   it ahead of the skipped operands and leaves optind past it.

   NOT covered, because not implemented: getopt_long, and the leading `+`/`-`
   optstring modes. A leading ':' IS supported and is row 12. */

#include <unistd.h>
#include <stdio.h>
#include <string.h>

static void scan(const char *label, int argc, char **argv, const char *spec)
{
    int c;
    optind = 0;              /* glibc-style reset, which busybox's GETOPT_RESET uses */
    opterr = 0;              /* the diagnostics go to stderr; this test asserts stdout */
    printf("%s:", label);
    while ((c = getopt(argc, argv, spec)) != -1) {
        if (c == 'o') printf(" o=%s", optarg);
        else if (c == '?') printf(" ?%c", (char)optopt);
        else if (c == ':') printf(" :%c", (char)optopt);
        else printf(" -%c", (char)c);
    }
    printf(" | optind=%d rest:", optind);
    for (; optind < argc; optind++) printf(" %s", argv[optind]);
    printf("\n");
}

#define RUN(label, spec, ...) do { \
    char *av[] = { "prog", __VA_ARGS__, 0 }; \
    scan(label, (int)(sizeof(av)/sizeof(av[0])) - 1, av, spec); \
} while (0)

int main(void)
{
    RUN("1", "abo:", "-a", "-b", "-o", "X", "f1", "f2");
    RUN("2", "abo:", "-abo", "Y", "f");
    RUN("3", "abo:", "-oX", "f", "-a");
    RUN("4", "abo:", "f", "-a");
    RUN("5", "abo:", "-z");
    RUN("6", "abo:", "-o");
    RUN("7", "abo:", "f1", "-a", "f2", "-o", "X", "f3");
    RUN("8", "abo:", "f1", "f2", "f3");
    RUN("9", "abo:", "-a", "--", "-b");
    RUN("10", "abo:", "--", "-a");
    RUN("11", "abo:", "f", "--", "-a");
    RUN("12", ":abo:", "-o");
    RUN("13", "abo:", "-");
    RUN("14", "abo:", "-a-b");
    return 0;
}
