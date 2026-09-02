/* SPDX-License-Identifier: Zlib */
/*
 * crtl: the STREAM scanf family -- fscanf/vfscanf/scanf/vscanf.
 *
 * Every row is asserted against glibc's output, produced by compiling this
 * same file with gcc. The point of the test is not that fscanf reads a number;
 * it is WHERE THE STREAM IS LEFT AFTERWARDS, which is the half an
 * implementation built on "read a line, then sscanf it" gets wrong while
 * passing every value check.
 *
 * The rows that would pass a wrong implementation are marked below; the ones
 * that matter are:
 *
 *   2   the stream sits on the newline after "12345", not past the next line.
 *   10  a matching failure on "-x" leaves "x", NOT "-x": only the offending
 *       character goes back (C99 7.19.6.2p9), the sign stays consumed. The
 *       tempting alternative -- restore the whole lookahead -- is a different
 *       library and every subsequent directive sees a different stream.
 *   11  "0x" with no hex digit is a matching FAILURE, not a conversion of the
 *       leading 0, and it consumes both characters.
 *   13  ftell accounts for the pushback: the position reported is the one the
 *       next read will come from, not the descriptor's.
 *   14  ungetc followed by fgets -- fgets used to read the fd directly and
 *       silently dropped the pushed-back character.
 *   15  "1e+" is a valid PREFIX of a float and not a float, so it is a
 *       matching failure with all three characters consumed. A collector that
 *       accepted the longest strtod-convertible prefix instead returns 1.0.
 *   16/17  field widths and '*' suppression: each directive stops exactly
 *       where it was told and the next character is 'e'.
 *   26  the boundary in the other direction: "1.2.3" must convert 1.2 and
 *       leave ".3". A collector loose enough to swallow the second dot turns
 *       a good number into a matching failure.
 *   22/23  EOF (-1), not 0, when input ran out before any conversion --
 *       including a whitespace-only file, where characters WERE consumed.
 *   24  a matching failure with input still available returns 0, not EOF.
 *   25  fscanf and fgets interleaved on one stream.
 *
 * SEQUENCED ON PURPOSE: every row that reads two or more characters puts each
 * fgetc in its own statement. Two fgetc calls in one printf argument list have
 * unspecified evaluation order, and both compilers agreeing about it proves
 * nothing.
 *
 * feature-c-crtl-fscanf-for-the-busybox-userland
 */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <stdlib.h>

int main(void) {
  FILE *f;
  char path[256];
  unsigned u; int a, b, n; char s1[64], s2[64]; double d; char ch;
  int r;

  /* Own file, so two runs cannot collide -- pid AND the run's own directory. */
  /* Directory from the environment, never a bare /tmp literal: a path written
     at RUNTIME is one no Makefile sweep reaches, so testmgr cannot privatize
     it and two concurrent runs share the file. TESTMGR_TMP first (testmgr's
     env allowlist is what $TESTTMP does not survive), TESTTMP second, /tmp
     last so a bare run stays byte-identical.
     Guard: tools/testmgr_hardcoded_tmp_devtest.py. */
  {
    const char *dir = getenv("TESTMGR_TMP");
    if (!dir) dir = getenv("TESTTMP");
    if (!dir) dir = "/tmp";
    snprintf(path, sizeof path, "%s/pxx_fscanf_%d.txt", dir, (int)getpid());
  }

  f = fopen(path, "w");
  fputs("12345\nhello world\n  42 -7 0x1f 0755\n3.5e2 rest\nabc,def\nXY\n", f);
  fclose(f);

  f = fopen(path, "r");
  r = fscanf(f, "%u", &u);
  printf("1 %d %u\n", r, u);
  /* the stream must be positioned at the newline, not past the next line */
  printf("2 %d\n", fgetc(f));
  r = fscanf(f, "%s %s", s1, s2);
  printf("3 %d %s|%s\n", r, s1, s2);
  r = fscanf(f, "%d %d %x %o", &a, &b, &n, &u);
  printf("4 %d %d %d %d %u\n", r, a, b, n, u);
  r = fscanf(f, "%lf", &d);
  printf("5 %d %.1f\n", r, d);
  r = fscanf(f, "%s", s1);
  printf("6 %d %s\n", r, s1);
  r = fscanf(f, " %[^,],%s", s1, s2);
  printf("7 %d %s|%s\n", r, s1, s2);
  r = fscanf(f, " %c%c", &ch, &s1[0]);
  printf("8 %d %c%c\n", r, ch, s1[0]);
  r = fscanf(f, "%d", &a);
  printf("9 %d\n", r);
  fclose(f);

  /* a lone '-' must not be consumed */
  f = fopen(path, "w"); fputs("-x", f); fclose(f);
  f = fopen(path, "r");
  r = fscanf(f, "%d", &a);
  { int c1 = fgetc(f); int c2 = fgetc(f);   /* SEQUENCED: two fgetc in one
       printf argument list have unspecified evaluation order and would make
       this row a coin flip rather than an oracle. */
    printf("10 %d %d %d\n", r, c1, c2); }
  fclose(f);

  /* 0x with no hex digit: value 0, and 'x' stays in the stream */
  f = fopen(path, "w"); fputs("0xz", f); fclose(f);
  f = fopen(path, "r");
  u = 7;                              /* sentinel: the row asserts u is UNTOUCHED */
  r = fscanf(f, "%x", &u);
  { int c1 = fgetc(f); int c2 = fgetc(f);
    printf("11 %d %u %d %d\n", r, u, c1, c2); }
  fclose(f);

  /* %n counts what was consumed */
  f = fopen(path, "w"); fputs("  4567tail", f); fclose(f);
  f = fopen(path, "r");
  r = fscanf(f, "%d%n", &a, &n);
  printf("12 %d %d %d\n", r, a, n);
  fclose(f);

  /* ftell must account for the pushback */
  f = fopen(path, "r");
  r = fscanf(f, "%d", &a);
  printf("13 %d %ld\n", r, ftell(f));
  fclose(f);

  /* ungetc then fgets */
  f = fopen(path, "r");
  a = fgetc(f); ungetc(a, f);
  { char line[32]; if (fgets(line, sizeof line, f)) printf("14 %s\n", line); }
  fclose(f);


  /* --- more edge cases, all against glibc ------------------------------- */
  /* a float whose exponent never arrived */
  f = fopen(path, "w"); fputs("1e+q", f); fclose(f);
  f = fopen(path, "r");
  d = -1.0;                           /* sentinel: d must be UNTOUCHED */
  r = fscanf(f, "%lf", &d);
  { int c1 = fgetc(f); int c2 = fgetc(f); int c3 = fgetc(f);
    printf("15 %d %.1f %d %d %d\n", r, d, c1, c2, c3); }
  fclose(f);

  /* assignment suppression and field width */
  f = fopen(path, "w"); fputs("123456789 abcdefgh", f); fclose(f);
  f = fopen(path, "r");
  r = fscanf(f, "%3d%*3d%3d %4s", &a, &b, s1);
  printf("16 %d %d %d %s\n", r, a, b, s1);
  { int c1 = fgetc(f); printf("17 %d\n", c1); }
  fclose(f);

  /* %i picks its base from the prefix */
  f = fopen(path, "w"); fputs("0x2a 011 42", f); fclose(f);
  f = fopen(path, "r");
  r = fscanf(f, "%i %i %i", &a, &b, &n);
  printf("18 %d %d %d %d\n", r, a, b, n);
  fclose(f);

  /* a literal that does not match */
  f = fopen(path, "w"); fputs("abZ", f); fclose(f);
  f = fopen(path, "r");
  r = fscanf(f, "abc");
  { int c1 = fgetc(f); printf("19 %d %d\n", r, c1); }
  fclose(f);

  /* a scanset with a range, and %c right after it */
  f = fopen(path, "w"); fputs("abc123-", f); fclose(f);
  f = fopen(path, "r");
  r = fscanf(f, "%[a-c]%[0-9]%c", s1, s2, &ch);
  printf("20 %d %s|%s|%c\n", r, s1, s2, ch);
  fclose(f);

  /* long and short lengths */
  f = fopen(path, "w"); fputs("9999999999 70000", f); fclose(f);
  f = fopen(path, "r");
  { long long ll; short sh;
    r = fscanf(f, "%lld %hd", &ll, &sh);
    printf("21 %d %lld %d\n", r, ll, (int)sh); }
  fclose(f);

  /* empty file */
  f = fopen(path, "w"); fclose(f);
  f = fopen(path, "r");
  r = fscanf(f, "%d", &a);
  printf("22 %d\n", r);
  fclose(f);

  /* whitespace-only file */
  f = fopen(path, "w"); fputs("   \n\t", f); fclose(f);
  f = fopen(path, "r");
  r = fscanf(f, "%d", &a);
  printf("23 %d\n", r);
  fclose(f);

  /* a matching failure that is NOT at end of file */
  f = fopen(path, "w"); fputs("zzz", f); fclose(f);
  f = fopen(path, "r");
  r = fscanf(f, "%d", &a);
  { int c1 = fgetc(f); printf("24 %d %d\n", r, c1); }
  fclose(f);

  /* interleaving fscanf with fgets */
  f = fopen(path, "w"); fputs("42 the rest of it\n", f); fclose(f);
  f = fopen(path, "r");
  r = fscanf(f, "%d", &a);
  { char line[64]; char *g = fgets(line, sizeof line, f);
    printf("25 %d %d [%s]\n", r, a, g ? g : "(null)"); }
  fclose(f);

  /* "1.2.3": the collector must stop at the SECOND dot and convert 1.2,
     rather than swallowing it and calling the whole thing a matching failure.
     This is the row that separates "collect a valid prefix" from "collect
     anything number-shaped". */
  f = fopen(path, "w"); fputs("1.2.3", f); fclose(f);
  f = fopen(path, "r");
  d = -1.0;
  r = fscanf(f, "%lf", &d);
  { int c1 = fgetc(f); int c2 = fgetc(f);
    printf("26 %d %.2f %d %d\n", r, d, c1, c2); }
  fclose(f);

  remove(path);
  return 0;
}
