/* pxx zlib test runner (used by `make test-zlib`, NOT the base gate).
 * Unity build: amalgamates crtl + the zlib v1.3.1 core from
 * library_candidates/zlib (gitignored 3rd-party scratch) + zlib's own
 * test/example.c, which self-checks compress/inflate/gzio round-trips and
 * exit(1)s on any mismatch. Oracle = the SAME file built with gcc; the
 * Makefile diffs stdout + exit code. Stays out of `make test` so the base
 * gate carries no 3rd-party dependency; skips gracefully when the tree is
 * absent.
 *
 * crtl units first (so the zlib sources see our libc-free headers/impls),
 * then the zlib translation units, then the harness. */
#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "math.c"
#include "fcntl.c"
#include "unistd.c"

#include "adler32.c"
#include "crc32.c"
#include "zutil.c"
#include "inftrees.c"
#include "inffast.c"
#include "inflate.c"
#include "infback.c"
#include "trees.c"
#include "deflate.c"
#include "compress.c"
#include "uncompr.c"
#include "gzlib.c"
#include "gzread.c"
#include "gzwrite.c"
#include "gzclose.c"

#include "example.c"
