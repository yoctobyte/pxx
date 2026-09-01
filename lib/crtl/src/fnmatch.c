/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: fnmatch — POSIX filename pattern matching.
 *
 * Written for busybox's ash, which reaches it two ways: `case' patterns and
 * pathname globbing. It is a pure algorithm — no syscalls, no PAL — so unlike
 * most of crtl it behaves identically on every target.
 *
 * The matcher backtracks recursively on '*'. That is the readable version and
 * the depth is bounded by the number of '*' in the PATTERN, not by the length
 * of the string, because consecutive stars are collapsed before recursing.
 */
#include <fnmatch.h>
#include <ctype.h>
#include <stddef.h>

static int fold(int c, int flags) {
  if ((flags & FNM_CASEFOLD) && c >= 'A' && c <= 'Z') return c - 'A' + 'a';
  return c;
}

/* [:alpha:] and friends. Anything unrecognised matches nothing rather than
   being treated as literal text: a misspelt class is a bug in the pattern and
   silently matching the letters of its name would hide it.

   WORKAROUND, revert when the current fix is PINNED. The natural shape here is
   a table of { name, ctype-function } pairs, which is what this was:

       struct { const char *n; int (*f)(int); } tbl[] = { { "alpha", isalpha }, ... };

   A LOCAL whose type is an anonymous struct with a function-pointer member did
   not parse -- the struct body's member declarator left CTypeFnPtrName set and
   ParseCLocalDeclAST had no `baseTk = tyPointer' guard. That is fixed at HEAD
   (test/c_struct_fnptr_member_local.c), but crtl is compiled by whatever
   compiler the USER has, including $(PXX_STABLE), so the table shape cannot
   come back until the fix is pinned. Registered in
   devdocs/dev/track-b-workarounds.md. */
static int cls_eq(const char *name, size_t len, const char *lit) {
  size_t i;
  for (i = 0; i < len; i++)
    if (lit[i] == '\0' || lit[i] != name[i]) return 0;
  return lit[len] == '\0';
}

static int class_match(const char *name, size_t len, int c) {
  if (cls_eq(name, len, "alpha"))  return isalpha(c)  ? 1 : 0;
  if (cls_eq(name, len, "digit"))  return isdigit(c)  ? 1 : 0;
  if (cls_eq(name, len, "alnum"))  return isalnum(c)  ? 1 : 0;
  if (cls_eq(name, len, "upper"))  return isupper(c)  ? 1 : 0;
  if (cls_eq(name, len, "lower"))  return islower(c)  ? 1 : 0;
  if (cls_eq(name, len, "space"))  return isspace(c)  ? 1 : 0;
  if (cls_eq(name, len, "print"))  return isprint(c)  ? 1 : 0;
  if (cls_eq(name, len, "punct"))  return ispunct(c)  ? 1 : 0;
  if (cls_eq(name, len, "graph"))  return isgraph(c)  ? 1 : 0;
  if (cls_eq(name, len, "cntrl"))  return iscntrl(c)  ? 1 : 0;
  if (cls_eq(name, len, "xdigit")) return isxdigit(c) ? 1 : 0;
  if (cls_eq(name, len, "blank"))  return (c == ' ' || c == '\t') ? 1 : 0;
  return 0;
}

/* One bracket expression. `p' points just past '['.
   Returns 1 match, 0 no match, -1 malformed (caller treats '[' as literal).
   On 0 or 1, *endp is set just past the closing ']'. */
static int bracket_match(const char *p, int c, int flags, const char **endp) {
  int neg = 0, matched = 0, first = 1;
  /* FNM_CASEFOLD folds LITERALS and RANGES but NOT character classes: glibc
     matches [[:upper:]] against "A" and not against "a" even with CASEFOLD set,
     while [A-Z] and [Ab] match both cases. So the original character is kept
     for [:class:] and the folded one is used everywhere else. Measured -- this
     code folded once at the top and got all three [[:upper:]] rows wrong. */
  int craw = c;
  c = fold(c, flags);
  if (*p == '!' || *p == '^') { neg = 1; p++; }
  for (;;) {
    unsigned char lo, hi;
    if (*p == '\0') return -1;                 /* unterminated */
    if (*p == ']' && !first) break;
    first = 0;

    if (*p == '[' && p[1] == ':') {
      const char *cl = p + 2, *e = cl;
      while (*e && !(*e == ':' && e[1] == ']')) e++;
      if (*e == '\0') return -1;
      if (class_match(cl, (size_t)(e - cl), craw)) matched = 1;
      p = e + 2;
      continue;
    }

    lo = (unsigned char)*p;
    if (lo == '\\' && !(flags & FNM_NOESCAPE)) {
      p++;
      if (*p == '\0') return -1;
      lo = (unsigned char)*p;
    }
    p++;

    /* A '-' before the closing ']' is a literal '-', not a range. */
    if (*p == '-' && p[1] != ']' && p[1] != '\0') {
      p++;
      hi = (unsigned char)*p;
      if (hi == '\\' && !(flags & FNM_NOESCAPE)) {
        p++;
        if (*p == '\0') return -1;
        hi = (unsigned char)*p;
      }
      p++;
      if (fold(lo, flags) <= c && c <= fold(hi, flags)) matched = 1;
    } else {
      if (fold(lo, flags) == c) matched = 1;
    }
  }
  *endp = p + 1;
  return neg ? !matched : matched;
}

/* `seg' is 1 when the next character of `s' begins a segment, which is where
   FNM_PERIOD makes a leading '.' special: the start of the string, and (under
   FNM_PATHNAME) just after a '/'. */
static int do_match(const char *p, const char *s, int flags, int seg) {
  for (;;) {
    unsigned char pc = (unsigned char)*p;

    switch (pc) {
    case '\0':
      if (*s == '\0') return 0;
      if ((flags & FNM_LEADING_DIR) && *s == '/') return 0;
      return FNM_NOMATCH;

    case '?':
      if (*s == '\0') return FNM_NOMATCH;
      if ((flags & FNM_PATHNAME) && *s == '/') return FNM_NOMATCH;
      if ((flags & FNM_PERIOD) && seg && *s == '.') return FNM_NOMATCH;
      seg = (flags & FNM_PATHNAME) && *s == '/';
      p++; s++;
      break;

    case '*': {
      const char *ss;
      while (*p == '*') p++;
      if ((flags & FNM_PERIOD) && seg && *s == '.') return FNM_NOMATCH;
      if (*p == '\0') {
        /* A trailing '*' takes the rest of the string, but under FNM_PATHNAME
           it may not cross a '/' — that is the whole point of the flag. */
        if (flags & FNM_PATHNAME) {
          for (ss = s; *ss; ss++)
            if (*ss == '/')
              return (flags & FNM_LEADING_DIR) ? 0 : FNM_NOMATCH;
        }
        return 0;
      }
      for (ss = s; ; ss++) {
        /* seg only still applies where the star consumed nothing. */
        if (do_match(p, ss, flags, ss == s ? seg : 0) == 0) return 0;
        if (*ss == '\0') break;
        if ((flags & FNM_PATHNAME) && *ss == '/') break;
      }
      return FNM_NOMATCH;
    }

    case '[': {
      const char *end;
      int r;
      if (*s == '\0') return FNM_NOMATCH;
      if ((flags & FNM_PATHNAME) && *s == '/') return FNM_NOMATCH;
      if ((flags & FNM_PERIOD) && seg && *s == '.') return FNM_NOMATCH;
      r = bracket_match(p + 1, (unsigned char)*s, flags, &end);
      if (r < 0) {
        /* An unterminated '[' is an ordinary character, which is what every
           shell does with `echo [' rather than reporting a pattern error. */
        if (fold('[', flags) != fold((unsigned char)*s, flags))
          return FNM_NOMATCH;
        seg = 0; p++; s++;
        break;
      }
      if (!r) return FNM_NOMATCH;
      seg = (flags & FNM_PATHNAME) && *s == '/';
      p = end; s++;
      break;
    }

    default:
      if (pc == '\\' && !(flags & FNM_NOESCAPE)) {
        /* A pattern ending in a backslash is undefined in POSIX. glibc treats
           it as malformed and never matches; measured, because the plausible
           reading -- that it stands for itself -- is what this code did first
           and it disagreed with the oracle on all 18 such cases. */
        if (p[1] == '\0') return FNM_NOMATCH;
        p++;
        pc = (unsigned char)*p;
      }
      if (*s == '\0') return FNM_NOMATCH;
      if (fold(pc, flags) != fold((unsigned char)*s, flags)) return FNM_NOMATCH;
      seg = (flags & FNM_PATHNAME) && *s == '/';
      p++; s++;
      break;
    }
  }
}

int fnmatch(const char *pattern, const char *string, int flags) {
  if (!pattern || !string) return FNM_NOMATCH;
  return do_match(pattern, string, flags, 1);
}
