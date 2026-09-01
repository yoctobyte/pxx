/* fnmatch against the gcc/glibc oracle.
 *
 * crtl had no fnmatch.h at all, which is a HARD ERROR when cross-compiling
 * (there is no host header to fall back to), so busybox's ash could not be
 * built for aarch64 at all. Found by attempting the target, not by triage:
 * feature-c-corpus-busybox-multi-applet.
 *
 * Every row is compared against glibc rather than against an expectation I
 * wrote down, because fnmatch's edge cases are exactly where a from-memory
 * implementation is confidently wrong. The trailing-backslash rows are here
 * for that reason: POSIX leaves it undefined, glibc never matches, and the
 * plausible reading (it stands for itself) is what this implementation did
 * first -- it disagreed on all 18 such combinations.
 *
 * The flags are a MATRIX, not a list. FNM_PATHNAME and FNM_PERIOD interact:
 * PERIOD makes a leading '.' special at the start of each SEGMENT, and what
 * counts as a segment depends on PATHNAME. Testing them singly passes while
 * the combination is broken.
 */
#include <fnmatch.h>
#include <stdio.h>

static const char *pats[] = {
  "", "a", "abc", "*", "**", "a*", "*a", "*a*", "a*c", "?", "a?c", "???",
  "[abc]", "[!abc]", "[^abc]", "[a-c]", "[!a-c]", "[]abc]", "[a-]", "[-a]",
  "[[:digit:]]", "[[:alpha:]]*", "[[:space:]]", "[[:upper:]]", "[[:nope:]]",
  "[", "[abc", "a\\*c", "\\*", "\\?", "\\[abc]",
  "*.c", "*.[ch]", "a/b", "a/*", "*/b", "a*b/c", "*/*", "**/*", "*/*/*",
  ".*", "*.", ".x", "a[b/c]d", "A*", "[A-Z]*", "x*y*z", "*a*a*a*",
  "\\", "a\\", "[a\\-c]", "a[.]c", "[!]]", "*[!/]",
};
static const char *strs[] = {
  "", "a", "abc", "ac", "abbc", ".", ".a", "..", "a.c", "a/b", "a/b/c",
  "/b", "a/", ".hidden", "a/.h", "a.c", "a.h", "a.o", "A", "ABC", "xyz",
  "xayz", "aaa", "\\", "a\\", "a-c", "-", "]", "[", "1", " ", "abcabcabca",
  "a*c", "a?c", "[abc]",
};
struct fs { const char *name; int v; };
static const struct fs flagsets[] = {
  { "0",            0 },
  { "PATH",         FNM_PATHNAME },
  { "PER",          FNM_PERIOD },
  { "NOESC",        FNM_NOESCAPE },
  { "CASE",         FNM_CASEFOLD },
  { "LEAD",         FNM_LEADING_DIR },
  { "PATH|PER",     FNM_PATHNAME | FNM_PERIOD },
  { "PATH|PER|NOE", FNM_PATHNAME | FNM_PERIOD | FNM_NOESCAPE },
  { "PATH|LEAD",    FNM_PATHNAME | FNM_LEADING_DIR },
  { "PER|CASE",     FNM_PERIOD | FNM_CASEFOLD },
  { "ALL",          FNM_PATHNAME | FNM_PERIOD | FNM_CASEFOLD | FNM_LEADING_DIR },
};

int main(void) {
  int np = (int)(sizeof(pats) / sizeof(pats[0]));
  int ns = (int)(sizeof(strs) / sizeof(strs[0]));
  int nf = (int)(sizeof(flagsets) / sizeof(flagsets[0]));
  int i, j, k, matches = 0, total = 0;

  for (i = 0; i < np; i++)
    for (j = 0; j < ns; j++)
      for (k = 0; k < nf; k++) {
        int r = fnmatch(pats[i], strs[j], flagsets[k].v);
        total++;
        if (r == 0) matches++;
        /* Only the MATCHES are printed, so the transcript stays legible while
           every non-match still contributes to the counts below. A regression
           that turns a match into a non-match moves both. */
        if (r == 0)
          printf("match pat=%-12s str=%-12s flags=%s\n",
                 pats[i], strs[j], flagsets[k].name);
        else if (r != FNM_NOMATCH)
          printf("BAD   pat=%-12s str=%-12s flags=%s rc=%d\n",
                 pats[i], strs[j], flagsets[k].name, r);
      }

  printf("total=%d matches=%d\n", total, matches);
  return 42;
}
