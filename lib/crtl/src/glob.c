/* SPDX-License-Identifier: Zlib */
/*
 * glob(3) / globfree(3) / glob_pattern_p(3).
 *
 * Matching is PER COMPONENT, over fnmatch(), which is why FNM_PATHNAME is
 * never passed: a component by construction contains no '/', so the flag
 * would only be describing something already true. FNM_PERIOD is passed
 * unless GLOB_PERIOD, and that one IS load-bearing -- it is the entire
 * "a wildcard does not match a leading dot" rule, and without it `rm *'
 * expands to include the dotfiles.
 *
 * d_type IS NOT TRUSTED FOR THE DIRECTORY DECISION. It is DT_UNKNOWN on
 * filesystems that do not carry the type in the directory entry (older
 * ext-family mounts, some network filesystems), and DT_LNK for a symlink to
 * a directory, which glob must descend through. Both would be a wrong answer
 * that reads as "no match" rather than as an error, so every directory-ness
 * question goes through stat(). d_type is not used as a fast path either:
 * doing so would make the common case take a path the uncommon case does
 * not, and the uncommon case is the one nobody would test.
 *
 * DANGLING SYMLINKS MATCH, which is why the existence check is lstat() and
 * not stat(). glibc does the same, and `ls -l broken*' depending on it is
 * ordinary. GLOB_MARK's directory test uses stat() instead, because there the
 * question really is "does this resolve to a directory".
 */

#include <glob.h>
#include <fnmatch.h>
#include <dirent.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/stat.h>

/* A growable vector of owned strings. Kept local to one glob() call so that
   a failure part-way frees exactly what it allocated and never touches the
   caller's glob_t -- which, under GLOB_APPEND, still holds a previous
   result the caller is entitled to. */
typedef struct {
  char **v;
  size_t n, cap;
} gvec;

static int gv_push(gvec *g, const char *s)
{
  char *d;
  if (g->n + 2 > g->cap) {
    size_t nc = g->cap ? g->cap * 2 : 16;
    char **nv = (char **)realloc(g->v, nc * sizeof(char *));
    if (!nv) return -1;
    g->v = nv;
    g->cap = nc;
  }
  d = strdup(s);
  if (!d) return -1;
  g->v[g->n++] = d;
  return 0;
}

static void gv_free(gvec *g)
{
  size_t i;
  for (i = 0; i < g->n; i++) free(g->v[i]);
  free(g->v);
  g->v = 0; g->n = g->cap = 0;
}

static int gv_cmp(const void *a, const void *b)
{
  return strcmp(*(char * const *)a, *(char * const *)b);
}

/* Does anything here need expanding? An escaped wildcard does not. */
static int has_magic(const char *p, size_t len, int noescape)
{
  size_t i;
  for (i = 0; i < len; i++) {
    if (!noescape && p[i] == '\\' && i + 1 < len) { i++; continue; }
    if (p[i] == '*' || p[i] == '?' || p[i] == '[') return 1;
  }
  return 0;
}

int glob_pattern_p(const char *pattern, int quote)
{
  return has_magic(pattern, strlen(pattern), !quote);
}

/* Remove one level of backslash escaping, in place. Only called on a
   component that has_magic() said carries no wildcard, so the result is a
   literal filename. */
static void unescape(char *s, int noescape)
{
  char *w;
  const char *r;
  if (noescape) return;
  w = s;
  for (r = s; *r; r++) {
    if (*r == '\\' && r[1]) r++;
    *w++ = *r;
  }
  *w = '\0';
}

/* One matched path, ready to record. GLOB_MARK's trailing '/' is added here
   rather than at the call sites so that the three ways a path can be
   completed (a literal last component, a wildcard last component, and a
   pattern ending in '/') cannot disagree about it. */
static int record(gvec *out, const char *path, int flags)
{
  char buf[PATH_MAX + 1];
  size_t n;

  if (!(flags & GLOB_MARK)) return gv_push(out, path);

  n = strlen(path);
  if (n && path[n - 1] == '/') return gv_push(out, path);   /* already marked */
  if (n + 2 > sizeof buf) { errno = ENAMETOOLONG; return -1; }
  {
    struct stat st;
    if (stat(path, &st) != 0 || !S_ISDIR(st.st_mode)) return gv_push(out, path);
  }
  memcpy(buf, path, n);
  buf[n] = '/';
  buf[n + 1] = '\0';
  return gv_push(out, buf);
}

/* Return codes below are glob()'s own: 0, GLOB_NOSPACE, GLOB_ABORTED. */
static int walk(char *pre, size_t plen, const char *pat, int flags,
                int (*errfunc)(const char *, int), gvec *out)
{
  const char *rest;
  size_t seglen;
  char comp[PATH_MAX + 1];
  int fnmflags = 0;
  int rc;

  /* Absolute paths and runs of '/' both land here. Copying them into the
     prefix rather than normalising them away is deliberate: "a//b" is a
     valid path that names the same file, and a caller who wrote it gets it
     back, which is what glibc does. */
  while (*pat == '/') {
    if (plen + 2 > PATH_MAX) return GLOB_NOSPACE;
    pre[plen++] = '/';
    pat++;
  }
  pre[plen] = '\0';

  /* The pattern ended in '/'. That constrains the match to directories and
     keeps the slash in the result. */
  if (*pat == '\0') {
    struct stat st;
    if (plen == 0) return 0;
    if (stat(pre, &st) != 0 || !S_ISDIR(st.st_mode)) return 0;
    return record(out, pre, flags) ? GLOB_NOSPACE : 0;
  }

  rest = strchr(pat, '/');
  seglen = rest ? (size_t)(rest - pat) : strlen(pat);
  if (!rest) rest = pat + seglen;
  if (seglen + 1 > sizeof comp) return GLOB_NOSPACE;
  memcpy(comp, pat, seglen);
  comp[seglen] = '\0';

  if (!has_magic(comp, seglen, flags & GLOB_NOESCAPE)) {
    struct stat st;
    size_t clen;
    unescape(comp, flags & GLOB_NOESCAPE);
    clen = strlen(comp);
    if (plen + clen + 1 > PATH_MAX) return GLOB_NOSPACE;
    memcpy(pre + plen, comp, clen + 1);

    if (*rest == '\0') {
      /* lstat, not stat: a dangling symlink is a real directory entry and
         matches, here and in glibc. */
      if (lstat(pre, &st) != 0) return 0;
      return record(out, pre, flags) ? GLOB_NOSPACE : 0;
    }
    return walk(pre, plen + clen, rest, flags, errfunc, out);
  }

  fnmflags = (flags & GLOB_NOESCAPE) ? FNM_NOESCAPE : 0;
  if (!(flags & GLOB_PERIOD)) fnmflags |= FNM_PERIOD;

  {
    DIR *d = opendir(plen ? pre : ".");
    struct dirent *e;
    if (!d) {
      /* THE ERROR PATH IS TWO DECISIONS, NOT ONE. errfunc runs first and its
         non-zero return stops the glob whatever GLOB_ERR says; GLOB_ERR
         stops it when there is no errfunc. Collapsing them would make a
         caller who passes an errfunc that returns 0 -- "log it and carry
         on", the usual shape -- get an abort it explicitly declined. */
      if (errfunc && errfunc(pre, errno)) return GLOB_ABORTED;
      if (flags & GLOB_ERR) return GLOB_ABORTED;
      return 0;
    }
    rc = 0;
    while ((e = readdir(d)) != 0) {
      size_t nlen;
      /* "." AND ".." ARE NOT FILTERED, and the first draft of this file
         filtered them. glibc does not: `glob(".*")' returns "." and ".."
         among its matches, and so does `glob("*", GLOB_PERIOD)'. FNM_PERIOD
         is what keeps them out of a plain `*', and it is the only thing that
         should -- a filter here would ALSO remove them from `.*', where the
         caller asked for them by writing the dot. Measured against glibc
         rather than reasoned: the `.*' row returns 4 entries, not 2. */
      if (fnmatch(comp, e->d_name, fnmflags) != 0) continue;
      nlen = strlen(e->d_name);
      if (plen + nlen + 1 > PATH_MAX) continue;
      memcpy(pre + plen, e->d_name, nlen + 1);
      if (*rest == '\0') {
        if (record(out, pre, flags)) { rc = GLOB_NOSPACE; break; }
      } else {
        rc = walk(pre, plen + nlen, rest, flags, errfunc, out);
        if (rc) break;
      }
    }
    closedir(d);
    pre[plen] = '\0';
    return rc;
  }
}

int glob(const char *pattern, int flags,
         int (*errfunc)(const char *, int), glob_t *pglob)
{
  gvec out;
  char pre[PATH_MAX + 1];
  size_t offs, old, total, i;
  char **nv;
  int rc, magic;

  if (!pattern || !pglob) { errno = EINVAL; return GLOB_NOSPACE; }

  out.v = 0; out.n = 0; out.cap = 0;
  pre[0] = '\0';
  magic = has_magic(pattern, strlen(pattern), flags & GLOB_NOESCAPE);

  rc = walk(pre, 0, pattern, flags, errfunc, &out);
  if (rc) { gv_free(&out); return rc; }

  if (out.n == 0) {
    /* GLOB_NOCHECK AND GLOB_NOMAGIC BOTH RETURN THE PATTERN UNCHANGED --
       escapes included. That is not an oversight to fix: hush.c:3529 says
       "Can't use GLOB_NOCHECK: it does not unescape the string" and works
       around it, so unescaping here would break a caller written against
       the documented behaviour. */
    if ((flags & GLOB_NOCHECK) || ((flags & GLOB_NOMAGIC) && !magic)) {
      if (gv_push(&out, pattern)) { gv_free(&out); return GLOB_NOSPACE; }
    } else {
      gv_free(&out);
      return GLOB_NOMATCH;
    }
  } else if (!(flags & GLOB_NOSORT)) {
    /* One sort over the whole result, not one per directory as glibc does.
       They agree: a full strcmp sort orders by the parent prefix first, so
       the blocks come out in the same order the per-level sort produces. */
    qsort(out.v, out.n, sizeof(char *), gv_cmp);
  }

  offs = (flags & GLOB_DOOFFS) ? pglob->gl_offs : 0;
  old  = (flags & GLOB_APPEND) ? pglob->gl_pathc : 0;
  total = offs + old + out.n;

  nv = (char **)malloc((total + 1) * sizeof(char *));
  if (!nv) { gv_free(&out); return GLOB_NOSPACE; }
  for (i = 0; i < offs; i++) nv[i] = 0;
  for (i = 0; i < old; i++) nv[offs + i] = pglob->gl_pathv[offs + i];
  for (i = 0; i < out.n; i++) nv[offs + old + i] = out.v[i];
  nv[total] = 0;

  /* The strings were transferred, not copied, so free the vector alone. */
  free(out.v);
  if (flags & GLOB_APPEND) free(pglob->gl_pathv);

  pglob->gl_pathv = nv;
  pglob->gl_pathc = old + out.n;
  if (!(flags & GLOB_DOOFFS)) pglob->gl_offs = 0;
  pglob->gl_flags = flags | (magic ? GLOB_MAGCHAR : 0);
  return 0;
}

void globfree(glob_t *pglob)
{
  size_t i;
  if (!pglob || !pglob->gl_pathv) return;
  for (i = 0; i < pglob->gl_pathc; i++) free(pglob->gl_pathv[pglob->gl_offs + i]);
  free(pglob->gl_pathv);
  pglob->gl_pathv = 0;
  pglob->gl_pathc = 0;
}
