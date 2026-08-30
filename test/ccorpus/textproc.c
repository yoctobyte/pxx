/* String and memory work through crtl, plus qsort/bsearch through function
   pointers and a small hand-rolled allocator. This is the program most likely
   to notice a crtl or preprocessor change; it deliberately leans on the
   library rather than on arithmetic. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAXW 64

static char pool[4096];
static int  pool_used = 0;

static char *palloc(int n) {
  char *p;
  if (pool_used + n > (int)sizeof pool) return NULL;
  p = pool + pool_used;
  pool_used += n;
  return p;
}

static int cmp_str(const void *a, const void *b) {
  return strcmp(*(const char *const *)a, *(const char *const *)b);
}

static int cmp_len_then_str(const void *a, const void *b) {
  const char *x = *(const char *const *)a, *y = *(const char *const *)b;
  size_t lx = strlen(x), ly = strlen(y);
  if (lx != ly) return lx < ly ? -1 : 1;
  return strcmp(x, y);
}

int main(void) {
  static const char text[] =
    "the rain in spain falls mainly on the plain but the plain in "
    "ukraine is not spain and rain is rain wherever it falls";
  char *words[MAXW];
  char scratch[256];
  int nw = 0, i;
  char *tok;
  unsigned long acc = 0;

  strcpy(scratch, text);
  for (tok = strtok(scratch, " "); tok && nw < MAXW; tok = strtok(NULL, " ")) {
    char *c = palloc((int)strlen(tok) + 1);
    if (!c) break;
    strcpy(c, tok);
    words[nw++] = c;
  }
  printf("words %d used %d\n", nw, pool_used);

  qsort(words, (size_t)nw, sizeof words[0], cmp_str);
  printf("first %s last %s\n", words[0], words[nw - 1]);

  qsort(words, (size_t)nw, sizeof words[0], cmp_len_then_str);
  printf("shortest %s longest %s\n", words[0], words[nw - 1]);

  for (i = 0; i < nw; i++) {
    acc = acc * 131u + (unsigned char)words[i][0];
    acc ^= strlen(words[i]);
  }
  printf("acc %lu\n", acc & 0xffffffful);

  /* the library calls a crtl change would move */
  printf("cmp %d %d %d\n",
         strcmp("abc", "abd") < 0, strncmp("abcdef", "abcxxx", 3), strcmp("", ""));
  printf("find %ld %ld\n",
         (long)(strchr(text, 'z') == NULL), (long)(strstr(text, "ukraine") - text));
  memset(scratch, 'x', 10); scratch[10] = '\0';
  memmove(scratch + 2, scratch, 5); scratch[10] = '\0';
  printf("mem %s %d\n", scratch, (int)strspn(text, "the "));
  snprintf(scratch, sizeof scratch, "%s|%d|%c|%05d|%-4s|", "s", -42, 'q', 7, "ab");
  printf("fmt %s\n", scratch);
  return 0;
}
