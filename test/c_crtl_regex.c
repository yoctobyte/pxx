/* SPDX-License-Identifier: Zlib */
/*
 * crtl: POSIX regular expressions. Every expectation below was MEASURED against
 * this box's glibc with the same source compiled by gcc, not reasoned out --
 * the file that produced them is the probe described in
 * feature-c-crtl-posix-regex-regcomp-regexec.
 *
 * The rows are chosen so that each one is the ONLY row that fails for some
 * specific way of getting the engine wrong. That was not true of the first
 * draft: a corpus of 147 real patterns harvested from busybox's own sed, grep
 * and awk testsuites -- 4527 cases, all matching glibc -- did not move at all
 * when the accept instruction was changed from leftmost-LONGEST to
 * leftmost-first, nor when the greedy/lazy branch order was flipped. A test
 * that passes on real input and cannot see the two decisions the engine is
 * built around is a breadth check, not a correctness one. Rows A01-A06 and
 * D20 are the ones that see them.
 *
 * Two rows do NOT match glibc, and both say why at the row.
 */
#include <stdio.h>
#include <string.h>
#include <regex.h>

static int fails;

static void t(const char *tag, const char *pat, const char *subj,
              int cflags, int eflags, const char *want)
{
  regex_t re;
  regmatch_t m[6];
  char got[128], piece[32];
  int rc, i, n;

  rc = regcomp(&re, pat, cflags);
  if (rc) {
    sprintf(got, "ERR %d", rc);
  } else {
    n = (int)re.re_nsub + 1;
    if (n > 6) n = 6;
    for (i = 0; i < 6; i++) { m[i].rm_so = -1; m[i].rm_eo = -1; }
    rc = regexec(&re, subj, 6, m, eflags);
    if (rc) {
      strcpy(got, "NOMATCH");
    } else {
      got[0] = 0;
      for (i = 0; i < n; i++) {
        sprintf(piece, "%s%d,%d", i ? " " : "", (int)m[i].rm_so, (int)m[i].rm_eo);
        strcat(got, piece);
      }
    }
    regfree(&re);
  }
  if (strcmp(got, want) != 0) {
    printf("FAIL %s want [%s] got [%s]\n", tag, want, got);
    fails++;
  }
}

int main(void)
{
  regex_t re;
  regmatch_t m[8];
  char subj[256];
  int rc;


  /* leftmost-longest: the decision the engine exists for */
  t("A01", "a|ab", "ab", REG_EXTENDED, 0, "0,2");
  t("A02", "ab|a", "ab", REG_EXTENDED, 0, "0,2");
  t("A03", "a*", "aaa", REG_EXTENDED, 0, "0,3");
  t("A04", "a*", "bbb", REG_EXTENDED, 0, "0,0");
  t("A05", "(a|ab)(c|bcd)", "abcd", REG_EXTENDED, 0, "0,4 0,1 1,4");
  t("A06", "x*", "yyxxz", REG_EXTENDED, 0, "0,0");

  /* BRE -- the operators are backslashed and the bare forms literal */
  t("B01", "a\\+", "aaa", 0, 0, "0,3");
  t("B02", "a+", "a+b", 0, 0, "0,2");
  t("B03", "a?", "a?b", 0, 0, "0,2");
  t("B04", "a\\?b", "ab", 0, 0, "0,2");
  t("B05", "\\(ab\\)\\1", "abab", 0, 0, "0,4 0,2");
  t("B06", "(ab)", "x(ab)y", 0, 0, "1,5");
  t("B07", "*foo", "a*foo", 0, 0, "1,5");
  t("B08", "^*a", "*ab", 0, 0, "0,2");
  t("B09", "a\\{2,3\\}", "aaaa", 0, 0, "0,3");
  t("B10", "a\\{2\\}", "aaaa", 0, 0, "0,2");
  t("B11", "\\(a\\|b\\)*c", "ababc", 0, 0, "0,5 3,4");
  t("B12", "a$b", "a$b", 0, 0, "0,3");
  t("B13", "a*", "aaa", 0, 0, "0,3");
  t("B14", "\\(a*\\)b", "aab", 0, 0, "0,3 0,2");
  t("B15", "\\(.*\\)x", "yyx", 0, 0, "0,3 0,2");
  t("B16", "\\(.*\\)/\\1", "x/x", 0, 0, "0,3 0,1");
  t("B17", "^\\(a*\\)\\(b*\\)$", "aabb", 0, 0, "0,4 0,2 2,4");
  t("B18", "x\\{0,2\\}y", "xxy", 0, 0, "0,3");
  t("B19", "[a-z]*", "abc123", 0, 0, "0,3");
  t("B20", "\\(ab\\)*", "ababab", 0, 0, "0,6 4,6");

  /* ERE */
  t("C01", "a+", "aaa", REG_EXTENDED, 0, "0,3");
  t("C02", "a{2,3}", "aaaa", REG_EXTENDED, 0, "0,3");
  t("C03", "(foo|bar)baz", "xxbarbazyy", REG_EXTENDED, 0, "2,8 2,5");
  t("C04", "^abc$", "abc", REG_EXTENDED, 0, "0,3");
  t("C05", "^abc$", "xabc", REG_EXTENDED, 0, "NOMATCH");
  t("C06", "a.c", "abc", REG_EXTENDED, 0, "0,3");
  t("C07", "a.c", "a\nc", REG_EXTENDED, 0, "0,3");
  t("C08", "a.c", "a\nc", REG_EXTENDED|REG_NEWLINE, 0, "NOMATCH");
  t("C09", "()", "x", REG_EXTENDED, 0, "0,0 0,0");
  /* GLIBC SAYS `0,1 0,0'. The star runs zero iterations here and we report
     the group as not participating; glibc reports one empty iteration. The
     SPAN agrees, which is the part every caller uses -- sed writes the same
     empty text for \\1 either way. Recorded, not chased: matching it means
     special-casing an empty loop body, and POSIX subexpression rules are
     out of scope for this engine by design (see lib/crtl/src/regex.c). */
  t("C10", "(a?)*b", "b", REG_EXTENDED, 0, "0,1 -1,-1");
  t("C11", "a{0,2}", "aaa", REG_EXTENDED, 0, "0,2");
  t("C12", "(a)(b)(c)", "abc", REG_EXTENDED, 0, "0,3 0,1 1,2 2,3");
  t("C13", "[[:digit:]]+", "ab123cd", REG_EXTENDED, 0, "2,5");
  t("C14", "[^[:digit:]]+", "ab123cd", REG_EXTENDED, 0, "0,2");
  t("C15", "[]a]+", "]a]b", REG_EXTENDED, 0, "0,3");
  t("C16", "[a-]+", "-a-b", REG_EXTENDED, 0, "0,3");
  t("C17", "[-a]+", "-a-b", REG_EXTENDED, 0, "0,3");
  t("C18", "[a-c]+", "xabcdy", REG_EXTENDED, 0, "1,4");
  t("C19", "[^a-c]+", "abcxyza", REG_EXTENDED, 0, "3,6");
  t("C20", "x|", "yx", REG_EXTENDED, 0, "0,0");

  /* flags, and the rows that catch a folding or memo shortcut */
  t("D01", "ABC", "xxabcyy", REG_ICASE, 0, "2,5");
  t("D02", "[a-c]+", "ABC", REG_EXTENDED|REG_ICASE, 0, "0,3");
  t("D03", "^a", "ba", REG_EXTENDED, REG_NOTBOL, "NOMATCH");
  t("D04", "^a", "ab", REG_EXTENDED, REG_NOTBOL, "NOMATCH");
  t("D05", "a$", "ba", REG_EXTENDED, REG_NOTEOL, "NOMATCH");
  t("D06", "^b", "a\nb", REG_EXTENDED|REG_NEWLINE, 0, "2,3");
  t("D07", "a$", "a\nb", REG_EXTENDED|REG_NEWLINE, 0, "0,1");
  t("D08", "abc", "xxABCyy", REG_ICASE, 0, "2,5");
  t("D09", "AbC", "xxaBcyy", REG_EXTENDED|REG_ICASE, 0, "2,5");
  t("D10", "\\(ab\\)\\1", "abAB", REG_ICASE, 0, "0,4 0,2");
  t("D11", "\\(ab\\)\\1", "abAB", 0, 0, "NOMATCH");
  t("D12", "\\(a\\)*b\\1", "b", 0, 0, "NOMATCH");
  t("D13", "\\(a\\)*b\\1", "aba", 0, 0, "0,3 0,1");
  t("D14", "a.*c", "ab\nc", REG_EXTENDED, 0, "0,4");
  t("D15", "a.*c", "ab\nc", REG_EXTENDED|REG_NEWLINE, 0, "NOMATCH");
  t("D16", "a[^x]*c", "ab\nc", REG_EXTENDED|REG_NEWLINE, 0, "NOMATCH");
  t("D17", "[A-Z]+", "abc", REG_EXTENDED|REG_ICASE, 0, "0,3");
  t("D18", "[a-z]+", "ABC", REG_EXTENDED|REG_ICASE, 0, "0,3");
  t("D19", "[^A-Z]+", "abc", REG_EXTENDED|REG_ICASE, 0, "NOMATCH");
  t("D20", "\\(a*\\)a*\\1", "aaaaa", 0, 0, "0,5 0,2");

  /* patterns shaped like the ones busybox actually issues */
  t("E01", "^[[:space:]]*#", "   # comment", REG_EXTENDED, 0, "0,4");
  t("E02", "([0-9]+)\\.([0-9]+)\\.([0-9]+)", "v1.36.1x", REG_EXTENDED, 0, "1,7 1,2 3,5 6,7");
  t("E03", "[^/]+$", "/usr/local/bin", REG_EXTENDED, 0, "11,14");
  t("E04", "\\<[a-z]*\\>", "hello world", 0, 0, "0,5");
  t("E05", "^(.*)=(.*)$", "KEY=VAL=UE", REG_EXTENDED, 0, "0,10 0,7 8,10");
  t("E06", "s/\\(.*\\)/\\1/", "s/x/x/", 0, 0, "0,6 2,3");

  /* malformed patterns */
  /* GLIBC SAYS `ERR 2' (REG_BADPAT). POSIX names REG_EBRACK, which is 7, for
     an unmatched `[' -- so this is glibc diverging from the standard and
     not us. The code reaches no busybox applet: every one of them treats a
     nonzero regcomp as a fatal error and prints regerror's text. */
  t("F01", "a[", "x", REG_EXTENDED, 0, "ERR 7");
  t("F02", "(a", "x", REG_EXTENDED, 0, "ERR 8");
  t("F03", "a)", "x", REG_EXTENDED, 0, "NOMATCH");
  t("F04", "a\\", "x", REG_EXTENDED, 0, "ERR 5");
  t("F05", "[[:bogus:]]", "x", REG_EXTENDED, 0, "ERR 4");
  t("F06", "a{3,1}", "x", REG_EXTENDED, 0, "ERR 10");
  t("F07", "[z-a]", "x", REG_EXTENDED, 0, "ERR 11");
  t("F08", "*a", "x", REG_EXTENDED, 0, "ERR 13");
  t("F09", "+a", "x", REG_EXTENDED, 0, "ERR 13");

  /* THE STEP BUDGET, AND ITS POSITIVE CONTROL. A guard that cannot fire is not
     a guard: nothing in the 4527-case corpus reaches the budget, so without
     this row the code that distinguishes `ran out of room' from `no match'
     never executes and a mutation turning REG_ESPACE into REG_NOMATCH is
     invisible. n=200 a's against four nested starred groups and their four
     back-references trips it in about a second; n=40 does not, and finishes
     as a genuine NOMATCH (glibc takes 2.6s on that one and 20 minutes was not
     enough for n=200). REG_NOMATCH here would make grep silently drop a line
     it could not decide about. */
  memset(subj, 'a', 200);
  subj[200] = 'c';
  subj[201] = 0;
  rc = regcomp(&re, "\\(a*\\)\\(a*\\)\\(a*\\)\\(a*\\)\\1\\2\\3\\4b", 0);
  if (rc) { printf("FAIL budget-compile %d\n", rc); fails++; }
  else {
    rc = regexec(&re, subj, 8, m, 0);
    if (rc != REG_ESPACE) { printf("FAIL budget want %d got %d\n", REG_ESPACE, rc); fails++; }
    regfree(&re);
  }

  /* regerror must fill the buffer and return the size INCLUDING the NUL, and
     must truncate rather than overrun when the buffer is short. busybox's
     xregcomp calls it with a fixed stack buffer. */
  {
    char eb[8];
    size_t need;
    memset(eb, '#', sizeof eb);
    need = regerror(REG_NOMATCH, (regex_t *)0, eb, sizeof eb);
    if (need != 9 || strcmp(eb, "No matc") != 0) {
      printf("FAIL regerror need=%d buf=[%s]\n", (int)need, eb);
      fails++;
    }
    if (regerror(REG_NOMATCH, (regex_t *)0, (char *)0, 0) != 9) {
      printf("FAIL regerror sizing\n");
      fails++;
    }
  }

  /* REG_STARTEND: the span comes IN through pmatch[0] and the offsets come
     back relative to the string's start, not to the span's. busybox's grep
     uses it to match inside a line without copying it. */
  {
    static const char *hay = "xxxabcxxx";
    rc = regcomp(&re, "b", 0);
    if (rc) { printf("FAIL startend-compile\n"); fails++; }
    else {
      m[0].rm_so = 0; m[0].rm_eo = 3;
      if (regexec(&re, hay, 1, m, REG_STARTEND) != REG_NOMATCH) {
        printf("FAIL startend not-in-span\n"); fails++;
      }
      m[0].rm_so = 0; m[0].rm_eo = 9;
      if (regexec(&re, hay, 1, m, REG_STARTEND) != 0 ||
          m[0].rm_so != 4 || m[0].rm_eo != 5) {
        printf("FAIL startend span %d,%d\n", (int)m[0].rm_so, (int)m[0].rm_eo);
        fails++;
      }
      regfree(&re);
    }
  }

  printf("regex %s\n", fails ? "FAILED" : "ok");
  return fails ? 1 : 0;
}
