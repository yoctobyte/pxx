/* SPDX-License-Identifier: Zlib */
/*
 * `extern T name[];` in a header, `T name[] = { ... };` in the .c -- the most
 * ordinary way a C program shares a table.
 *
 * The declarator has an INCOMPLETE array type, so the declaration reserved ONE
 * element and fixed the symbol's offset there; the definition found the symbol
 * already present and reused it as is. The initializer then wrote its full
 * length straight over whatever globals followed. No diagnostic, and the
 * damage lands on UNRELATED variables.
 *
 * Measured on busybox: bkm_suffixes, cwbkMG_suffixes and kmg_i_suffixes -- 128
 * bytes each -- were allocated EIGHT bytes apart, and msg_eol, logmode and
 * xfunc_error_retval landed inside them. strlen(msg_eol) walked a pointer
 * assembled half from a suffix-table entry, and the first error message the
 * program tried to print segfaulted.
 *
 * So the rows that matter are not the table contents: they are `after1` and
 * `after2`, the globals declared BETWEEN the declaration and the definition,
 * which are what an undersized reservation runs over. Differential against a
 * glibc-built binary of this same file.
 */
#include <stdio.h>
#include <string.h>

struct S { char s[4]; unsigned m; };

extern const struct S tbl[];       /* incomplete: no size here */
extern const int nums[];
extern char text[];

/* Declared between the declaration and the definition -- the casualties. */
int after1 = 111;
const char *after2 = "second";
double after3 = 2.5;

const struct S tbl[] = {
  { "aa", 1 }, { "bb", 2 }, { "cc", 3 }, { "dd", 4 }, { "", 0 }
};
const int nums[] = { 10, 20, 30, 40, 50, 60, 70, 80 };
char text[] = "a fairly long string that needs more than one slot";

int main(void)
{
  int i;
  printf("after1=%d after2=[%s] after3=%.1f\n", after1, after2, after3);
  for (i = 0; i < 5; i++) printf("tbl[%d]=[%s],%u\n", i, tbl[i].s, tbl[i].m);
  for (i = 0; i < 8; i++) printf("nums[%d]=%d\n", i, nums[i]);
  printf("text=[%s] len=%d\n", text, (int)strlen(text));
  printf("sizeof tbl=%d nums=%d text=%d\n",
         (int)sizeof tbl, (int)sizeof nums, (int)sizeof text);
  printf("after1=%d after2=[%s] after3=%.1f\n", after1, after2, after3);
  return 0;
}
