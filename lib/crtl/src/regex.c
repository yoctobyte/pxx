/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: POSIX regular expressions -- regcomp/regexec/regfree/regerror.
 *
 * WHAT THIS IS: a backtracking VM over a compiled instruction list, run so
 * that match[0] is LEFTMOST-LONGEST. That is not the same engine a Perl-style
 * matcher would be, and the difference is the whole reason the choice is
 * written down here: POSIX says `a|ab' against "ab" matches TWO characters,
 * and a matcher that returns the first alternative that succeeds returns one.
 * Every sed `s/a|ab/X/' then replaces the wrong span and writes a plausible
 * wrong file. So the accept instruction does NOT stop the search -- it records
 * the end if it beats the best so far and then RETURNS FAILURE, which forces
 * the remaining alternatives to be explored.
 *
 * WHAT IT IS NOT, said plainly because the gap is real: POSIX also specifies
 * leftmost-longest recursively for each SUBEXPRESSION, and this engine does
 * not do that. match[0] is the longest; the captures reported are those of one
 * path that achieves that length, preferring the earlier alternative. glibc
 * itself is not consistent here and no busybox applet depends on it. If a case
 * ever turns up that does, it wants a different engine, not a patch.
 *
 * COST, AND HOW IT IS BOUNDED. Exploring every path is exponential in the bad
 * cases. Two brakes, and they do different jobs:
 *   - A MEMO of (instruction, position) pairs already explored to exhaustion.
 *     Sound only because captures cannot change what matches -- which stops
 *     being true the moment a BACK-REFERENCE appears, so the memo is switched
 *     off for those patterns and only for those. With it, a pattern without
 *     back-references costs O(ninst * len) per start position instead of
 *     exponential, and `(a*)*' terminates instead of spinning.
 *   - A STEP BUDGET, which is the honest failure. Exceeded, regexec returns
 *     REG_ESPACE. It does NOT return REG_NOMATCH: "I ran out of room" and
 *     "this does not match" are different answers, and a matcher that reports
 *     the second when it means the first makes grep silently skip lines.
 *
 * BRE AND ERE ARE DIFFERENT LANGUAGES AND THE DEFAULT IS BRE. Without
 * REG_EXTENDED, `(' `)' `|' `{' `}' `+' `?' are LITERAL and the operators are
 * spelled `\(' `\)' `\|' `\{' `\}' `\+' `\?'; with it, exactly the other way
 * round. sed and grep are BRE by default, awk is always ERE. Getting this
 * backwards does not fail loudly -- it treats a pattern's parentheses as text
 * and quietly matches nothing, or matches everything.
 *
 * BRE also makes `*' LITERAL where there is nothing to repeat (at the start of
 * the pattern, or just after `\(' or `\|'), and `^' and `$' anchors only at
 * the ends. Those are not quirks to tidy away: `grep '*foo'` searches for a
 * literal asterisk, and a matcher that calls it "repetition with nothing to
 * repeat" rejects a pattern that works everywhere else.
 *
 * Found attempting busybox on i386: seven translation units stopped at
 * `regex.h' -- awk, sed, grep, expr, test, mdev, and the libbb/xregcomp.c
 * wrapper the rest go through.
 * feature-c-crtl-posix-regex-regcomp-regexec
 */

#include <regex.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* ---- the instruction set -------------------------------------------------- */

#define RXI_CHAR     1   /* x = byte (already case-folded when REG_ICASE) */
#define RXI_ANY      2   /* `.' */
#define RXI_CLASS    3   /* x = index of a 256-bit set */
#define RXI_BOL      4
#define RXI_EOL      5
#define RXI_JMP      6   /* x */
#define RXI_SPLIT    7   /* try x, then y */
#define RXI_SAVE     8   /* x = capture slot */
#define RXI_BACKREF  9   /* x = group number */
#define RXI_MATCH   10
#define RXI_BOW     11  /* \< */
#define RXI_EOW     12  /* \> */
#define RXI_WB      13  /* x=1: \b   x=0: \B */

struct rx_inst { int op; int x; int y; };

struct rx_prog {
  struct rx_inst *inst;
  int   ninst;
  int   cap_inst;
  unsigned char *cls;    /* nclass * 32 bytes */
  int   nclass;
  int   cap_class;
  int   ngroup;          /* parenthesised subexpressions */
  int   cflags;
  int   hasback;         /* a back-reference appears: the memo is unsound */
  int   err;             /* first REG_* error seen while compiling */
};

/* ---- compile-time buffer growth ------------------------------------------- */

static int rx_grow_inst(struct rx_prog *p)
{
  int ncap;
  struct rx_inst *ni;
  if (p->ninst < p->cap_inst) return 1;
  ncap = p->cap_inst ? p->cap_inst * 2 : 64;
  ni = (struct rx_inst *)realloc(p->inst, (size_t)ncap * sizeof(struct rx_inst));
  if (!ni) { p->err = REG_ESPACE; return 0; }
  p->inst = ni;
  p->cap_inst = ncap;
  return 1;
}

static int rx_emit(struct rx_prog *p, int op, int x, int y)
{
  int at;
  if (!rx_grow_inst(p)) return -1;
  at = p->ninst;
  p->inst[at].op = op;
  p->inst[at].x  = x;
  p->inst[at].y  = y;
  p->ninst = at + 1;
  return at;
}

static int rx_new_class(struct rx_prog *p)
{
  int ncap, idx;
  unsigned char *nc;
  if (p->nclass >= p->cap_class) {
    ncap = p->cap_class ? p->cap_class * 2 : 8;
    nc = (unsigned char *)realloc(p->cls, (size_t)ncap * 32);
    if (!nc) { p->err = REG_ESPACE; return -1; }
    p->cls = nc;
    p->cap_class = ncap;
  }
  idx = p->nclass++;
  memset(p->cls + (size_t)idx * 32, 0, 32);
  return idx;
}

#define RX_SET(bm, c)  ((bm)[((unsigned char)(c)) >> 3] |= (unsigned char)(1 << (((unsigned char)(c)) & 7)))
#define RX_TST(bm, c)  ((bm)[((unsigned char)(c)) >> 3] &  (unsigned char)(1 << (((unsigned char)(c)) & 7)))

/* ---- the parser ----------------------------------------------------------- */

struct rx_parse {
  const char *pat;
  int   len;
  int   pos;
  int   ere;
  int   icase;
  int   group;        /* next group number to allocate */
  int   depth;        /* open groups: a `)' outside one is LITERAL */
  struct rx_prog *p;
};

static int rx_alt(struct rx_parse *ps);

static int rx_at_end(struct rx_parse *ps) { return ps->pos >= ps->len; }
static int rx_peek(struct rx_parse *ps)
{ return ps->pos < ps->len ? (unsigned char)ps->pat[ps->pos] : -1; }
static int rx_peek2(struct rx_parse *ps)
{ return ps->pos + 1 < ps->len ? (unsigned char)ps->pat[ps->pos + 1] : -1; }

/* Is the cursor on this operator? In BRE the operators are backslashed and the
   bare characters are literal; in ERE the reverse. One predicate for both, so
   the two languages cannot drift apart in the places that ask. */
static int rx_is_op(struct rx_parse *ps, int ch)
{
  if (ps->ere) return rx_peek(ps) == ch;
  return rx_peek(ps) == '\\' && rx_peek2(ps) == ch;
}

static void rx_eat_op(struct rx_parse *ps) { ps->pos += ps->ere ? 1 : 2; }

/* The named classes. Kept as a table rather than a chain of strcmp so adding
   one cannot forget a branch. */
static int rx_class_named(const char *name, int n, unsigned char *bm)
{
  int c, hit;
  for (c = 0; c < 256; c++) {
    hit = 0;
    if      (n == 5 && !memcmp(name, "alpha", 5)) hit = isalpha(c);
    else if (n == 5 && !memcmp(name, "digit", 5)) hit = isdigit(c);
    else if (n == 5 && !memcmp(name, "alnum", 5)) hit = isalnum(c);
    else if (n == 5 && !memcmp(name, "upper", 5)) hit = isupper(c);
    else if (n == 5 && !memcmp(name, "lower", 5)) hit = islower(c);
    else if (n == 5 && !memcmp(name, "space", 5)) hit = isspace(c);
    else if (n == 5 && !memcmp(name, "blank", 5)) hit = (c == ' ' || c == '\t');
    else if (n == 5 && !memcmp(name, "punct", 5)) hit = ispunct(c);
    else if (n == 5 && !memcmp(name, "print", 5)) hit = isprint(c);
    else if (n == 5 && !memcmp(name, "graph", 5)) hit = isgraph(c);
    else if (n == 5 && !memcmp(name, "cntrl", 5)) hit = iscntrl(c);
    else if (n == 6 && !memcmp(name, "xdigit", 6)) hit = isxdigit(c);
    else return 0;   /* unknown class name */
    if (hit) RX_SET(bm, c);
  }
  return 1;
}

/* A bracket expression. `]' first is literal, `-' first or last is literal,
   `[:name:]' is a named class -- all three are POSIX rules that a naive
   scanner gets wrong in the direction of accepting nonsense. */
static int rx_bracket(struct rx_parse *ps)
{
  int idx, neg, first, c, lo, hi, i, n;
  unsigned char *bm;
  const char *nm;

  idx = rx_new_class(ps->p);
  if (idx < 0) return -1;
  bm = ps->p->cls + (size_t)idx * 32;

  ps->pos++;                      /* the '[' */
  neg = 0;
  if (rx_peek(ps) == '^') { neg = 1; ps->pos++; }
  first = 1;

  for (;;) {
    if (rx_at_end(ps)) { ps->p->err = REG_EBRACK; return -1; }
    c = rx_peek(ps);
    if (c == ']' && !first) { ps->pos++; break; }
    first = 0;

    if (c == '[' && rx_peek2(ps) == ':') {
      ps->pos += 2;
      nm = ps->pat + ps->pos;
      n = 0;
      while (ps->pos + n < ps->len && ps->pat[ps->pos + n] != ':') n++;
      if (ps->pos + n + 1 >= ps->len || ps->pat[ps->pos + n + 1] != ']') {
        ps->p->err = REG_EBRACK; return -1;
      }
      if (!rx_class_named(nm, n, bm)) { ps->p->err = REG_ECTYPE; return -1; }
      ps->pos += n + 2;
      continue;
    }

    ps->pos++;
    lo = c;
    /* A range, but only when the '-' is not the last character before ']'. */
    if (rx_peek(ps) == '-' && rx_peek2(ps) != ']' && rx_peek2(ps) != -1) {
      ps->pos++;
      hi = rx_peek(ps);
      ps->pos++;
      if (hi < lo) { ps->p->err = REG_ERANGE; return -1; }
      for (i = lo; i <= hi; i++) RX_SET(bm, i);
      continue;
    }
    RX_SET(bm, lo);
  }

  if (ps->icase) {
    for (i = 0; i < 256; i++)
      if (RX_TST(bm, i)) {
        if (isupper(i)) RX_SET(bm, tolower(i));
        if (islower(i)) RX_SET(bm, toupper(i));
      }
  }
  if (neg) {
    for (i = 0; i < 32; i++) bm[i] = (unsigned char)~bm[i];
    /* REG_NEWLINE: a negated class does not match a newline. Without this,
       grep's `[^x]*' swallows the line terminator and the match spans lines. */
    if (ps->p->cflags & REG_NEWLINE) bm['\n' >> 3] &= (unsigned char)~(1 << ('\n' & 7));
  }
  return idx;
}

/* Make room for one instruction at `at' by shifting everything after it up,
   then fix every absolute jump that pointed past the hole. `*' and `?' need
   this because the SPLIT belongs BEFORE code that is already emitted. */
static int rx_insert(struct rx_prog *p, int at, int op, int x, int y)
{
  int i;
  if (rx_emit(p, RXI_MATCH, 0, 0) < 0) return 0;   /* grow by one */
  for (i = p->ninst - 1; i > at; i--) p->inst[i] = p->inst[i - 1];
  /* RELOCATE FIRST, WRITE SECOND, and the order is the whole fix. The caller
     computes the new instruction's targets in POST-shift coordinates, so a
     relocation pass that can still see them adds one to each and puts a `*'
     loop's exit two instructions past its own end. Writing after the pass
     means the pass cannot reach it; the stale bytes it walks over at index
     `at' are overwritten on the next line. */
  for (i = 0; i < p->ninst; i++) {
    if (p->inst[i].op == RXI_JMP || p->inst[i].op == RXI_SPLIT) {
      if (p->inst[i].x > at) p->inst[i].x++;
      if (p->inst[i].op == RXI_SPLIT && p->inst[i].y > at) p->inst[i].y++;
    }
  }
  p->inst[at].op = op; p->inst[at].x = x; p->inst[at].y = y;
  return 1;
}

/* An interval `{n,m}'.
   The body is LIFTED OUT of the program before anything is built, because the
   first version copied it in place: `{0,m}' rewound the cursor to the body's
   own start and then read the instructions it was overwriting, and every
   later copy read a body that the preceding insert had already shifted. A
   saved copy, rebased to zero, has no such coupling -- rx_iv_append is then
   the only thing that knows where a copy lands. Returns 0 with p->err set. */

struct rx_saved { struct rx_inst *inst; int n; };

static int rx_iv_save(struct rx_prog *p, int from, int to, struct rx_saved *sv)
{
  int i;
  sv->n = to - from;
  sv->inst = (struct rx_inst *)malloc((size_t)(sv->n ? sv->n : 1) * sizeof(struct rx_inst));
  if (!sv->inst) { p->err = REG_ESPACE; return 0; }
  for (i = 0; i < sv->n; i++) {
    sv->inst[i] = p->inst[from + i];
    if (sv->inst[i].op == RXI_JMP || sv->inst[i].op == RXI_SPLIT) {
      sv->inst[i].x -= from;
      if (sv->inst[i].op == RXI_SPLIT) sv->inst[i].y -= from;
    }
  }
  return 1;
}

static int rx_iv_append(struct rx_prog *p, struct rx_saved *sv)
{
  int i, base, at;
  base = p->ninst;
  for (i = 0; i < sv->n; i++) {
    at = rx_emit(p, sv->inst[i].op, sv->inst[i].x, sv->inst[i].y);
    if (at < 0) return 0;
    if (sv->inst[i].op == RXI_JMP || sv->inst[i].op == RXI_SPLIT) {
      p->inst[at].x += base;
      if (sv->inst[i].op == RXI_SPLIT) p->inst[at].y += base;
    }
  }
  return 1;
}

static int rx_interval(struct rx_parse *ps, int start)
{
  int lo, hi, i, digits, sp;
  struct rx_saved sv;
  struct rx_prog *p = ps->p;

  rx_eat_op(ps);                 /* the `{' or `\{' */
  lo = 0; digits = 0;
  while (rx_peek(ps) >= '0' && rx_peek(ps) <= '9') { lo = lo * 10 + (rx_peek(ps) - '0'); ps->pos++; digits++; }
  if (!digits) { p->err = REG_BADBR; return 0; }
  hi = lo;
  if (rx_peek(ps) == ',') {
    ps->pos++;
    if ((ps->ere && rx_peek(ps) == '}') || (!ps->ere && rx_peek(ps) == '\\')) hi = -1;
    else {
      hi = 0; digits = 0;
      while (rx_peek(ps) >= '0' && rx_peek(ps) <= '9') { hi = hi * 10 + (rx_peek(ps) - '0'); ps->pos++; digits++; }
      if (!digits) { p->err = REG_BADBR; return 0; }
    }
  }
  if (!rx_is_op(ps, '}')) { p->err = REG_EBRACE; return 0; }
  rx_eat_op(ps);
  if (hi != -1 && hi < lo) { p->err = REG_BADBR; return 0; }
  if (lo > 255 || (hi != -1 && hi > 255)) { p->err = REG_BADBR; return 0; }

  if (!rx_iv_save(p, start, p->ninst, &sv)) return 0;
  p->ninst = start;              /* the body now lives only in sv */

  for (i = 0; i < lo; i++)
    if (!rx_iv_append(p, &sv)) goto oom;

  if (hi == -1) {                /* {n,}: one more body, starred */
    sp = rx_emit(p, RXI_SPLIT, 0, 0);
    if (sp < 0) goto oom;
    p->inst[sp].x = sp + 1;
    if (!rx_iv_append(p, &sv)) goto oom;
    if (rx_emit(p, RXI_JMP, sp, 0) < 0) goto oom;
    p->inst[sp].y = p->ninst;
  } else {
    for (i = lo; i < hi; i++) {  /* {n,m}: m-n optional bodies */
      sp = rx_emit(p, RXI_SPLIT, 0, 0);
      if (sp < 0) goto oom;
      p->inst[sp].x = sp + 1;
      if (!rx_iv_append(p, &sv)) goto oom;
      p->inst[sp].y = p->ninst;
    }
  }
  free(sv.inst);
  return 1;
oom:
  free(sv.inst);
  return 0;
}

/* One concatenation element: an atom plus any repetition operators on it. */
static int rx_piece(struct rx_parse *ps, int branch_start)
{
  struct rx_prog *p = ps->p;
  int start, c, grp, idx, sub;

  start = p->ninst;

  if (rx_is_op(ps, '(')) {
    rx_eat_op(ps);
    grp = ps->group++;
    if (rx_emit(p, RXI_SAVE, grp * 2, 0) < 0) return 0;
    ps->depth++;
    if (!rx_alt(ps)) return 0;
    if (!rx_is_op(ps, ')')) { p->err = REG_EPAREN; return 0; }
    rx_eat_op(ps);
    ps->depth--;
    if (rx_emit(p, RXI_SAVE, grp * 2 + 1, 0) < 0) return 0;
  } else if (rx_peek(ps) == '[') {
    idx = rx_bracket(ps);
    if (idx < 0) return 0;
    if (rx_emit(p, RXI_CLASS, idx, 0) < 0) return 0;
  } else if (rx_peek(ps) == '.') {
    ps->pos++;
    if (rx_emit(p, RXI_ANY, 0, 0) < 0) return 0;
  } else if (rx_peek(ps) == '^' &&
             (ps->ere || p->ninst == branch_start)) {
    ps->pos++;
    if (rx_emit(p, RXI_BOL, 0, 0) < 0) return 0;
    return 1;                       /* an anchor takes no repetition */
  } else if (rx_peek(ps) == '$' &&
             (ps->ere || ps->pos == ps->len - 1 ||
              (rx_peek2(ps) == '\\' && ps->pos + 2 < ps->len &&
               (ps->pat[ps->pos + 2] == ')' || ps->pat[ps->pos + 2] == '|')))) {
    ps->pos++;
    if (rx_emit(p, RXI_EOL, 0, 0) < 0) return 0;
    return 1;
  } else if (rx_peek(ps) == '\\') {
    c = rx_peek2(ps);
    if (c == -1) { p->err = REG_EESCAPE; return 0; }
    if (c >= '1' && c <= '9') {
      sub = c - '0';
      if (sub >= ps->group) { p->err = REG_ESUBREG; return 0; }
      ps->pos += 2;
      p->hasback = 1;
      if (rx_emit(p, RXI_BACKREF, sub, 0) < 0) return 0;
    } else if (c == '<' || c == '>' || c == 'b' || c == 'B') {
      /* GNU word operators. Not POSIX, and carried because real patterns use
         them: busybox's own applets are built against a libc that has them,
         so a pattern like `\<word\>' arrives already written that way and a
         matcher without them treats the escapes as the letters `<' and `>'
         -- which does not fail, it silently matches nothing. */
      ps->pos += 2;
      if (rx_emit(p, c == '<' ? RXI_BOW : c == '>' ? RXI_EOW : RXI_WB,
                  c == 'b' ? 1 : 0, 0) < 0) return 0;
      return 1;                     /* zero-width: no repetition on it */
    } else if (c == 'w' || c == 'W' || c == 's' || c == 'S') {
      int k, ci;
      unsigned char *bm;
      ci = rx_new_class(p);
      if (ci < 0) return 0;
      bm = p->cls + (size_t)ci * 32;
      for (k = 0; k < 256; k++) {
        int hit = (c == 'w' || c == 'W') ? (isalnum(k) || k == '_') : isspace(k);
        if (c == 'W' || c == 'S') hit = !hit;
        if (hit) RX_SET(bm, k);
      }
      ps->pos += 2;
      if (rx_emit(p, RXI_CLASS, ci, 0) < 0) return 0;
    } else {
      /* Any other backslashed byte is that byte, literally. In BRE the
         operator spellings were taken by rx_is_op above, so anything left
         here really is an escape. */
      ps->pos += 2;
      if (rx_emit(p, RXI_CHAR, ps->icase ? tolower(c) : c, 0) < 0) return 0;
    }
  } else if (ps->ere && (rx_peek(ps) == '*' || rx_peek(ps) == '+' ||
                         rx_peek(ps) == '?')) {
    /* BRE makes these literal here; ERE does not, and calling it a literal
       would accept a pattern every other matcher rejects. */
    p->err = REG_BADRPT;
    return 0;
  } else {
    c = rx_peek(ps);
    if (c == -1) return 1;
    ps->pos++;
    if (rx_emit(p, RXI_CHAR, ps->icase ? tolower(c) : c, 0) < 0) return 0;
  }

  /* Repetition operators, and more than one may stack: `a**' is legal. */
  for (;;) {
    if (rx_peek(ps) == '*') {
      /* No `is a repetition allowed here' test: BRE's rule is that a `*' with
         nothing before it is LITERAL, and that case never reaches this loop --
         it is consumed as an atom by the literal arm above. The test that used
         to be here compared the atom's start against the BRANCH start and so
         also refused the star on the FIRST piece of a branch, where the atom
         is present: `\(a*\)b' quietly became the four literals a, *, then b.
         Nothing in the probe caught it because every star row was ERE. */
      ps->pos++;
      if (!rx_insert(p, start, RXI_SPLIT, start + 1, p->ninst + 2)) return 0;
      if (rx_emit(p, RXI_JMP, start, 0) < 0) return 0;
    } else if (rx_is_op(ps, '+')) {
      rx_eat_op(ps);
      if (rx_emit(p, RXI_SPLIT, start, p->ninst + 1) < 0) return 0;
    } else if (rx_is_op(ps, '?')) {
      rx_eat_op(ps);
      if (!rx_insert(p, start, RXI_SPLIT, start + 1, p->ninst + 1)) return 0;
    } else if (rx_is_op(ps, '{') && rx_peek2(ps) != -1) {
      if (!rx_interval(ps, start)) return 0;
    } else break;
  }
  return 1;
}

static int rx_cat(struct rx_parse *ps)
{
  int branch_start = ps->p->ninst;
  for (;;) {
    if (rx_at_end(ps)) break;
    if (rx_is_op(ps, '|')) break;
    if (rx_is_op(ps, ')') && ps->depth > 0) break;
    if (!rx_piece(ps, branch_start)) return 0;
  }
  return 1;
}

static int rx_alt(struct rx_parse *ps)
{
  struct rx_prog *p = ps->p;
  int split_at, jmp_at;

  split_at = p->ninst;
  if (!rx_cat(ps)) return 0;
  while (rx_is_op(ps, '|')) {
    rx_eat_op(ps);
    jmp_at = p->ninst;
    if (rx_emit(p, RXI_JMP, 0, 0) < 0) return 0;
    /* +1 because the insert about to happen shifts the next free slot, which
       is where the second branch will be emitted. */
    if (!rx_insert(p, split_at, RXI_SPLIT, split_at + 1, p->ninst + 1)) return 0;
    /* rx_insert moved jmp_at up by one. */
    jmp_at++;
    if (!rx_cat(ps)) return 0;
    p->inst[jmp_at].x = p->ninst;
    /* A further `|' must split against everything built so far. */
  }
  return 1;
}

/* ---- the matcher ---------------------------------------------------------- */

#define RX_STEP_BUDGET  20000000L

struct rx_ctx {
  struct rx_prog *p;
  const char *s;
  int   len;
  int   eflags;
  int  *cap;
  int  *best;
  int   nslot;
  int   bestend;
  long  steps;
  unsigned char *memo;   /* ninst * (len+1) bits, or 0 */
};

static int rx_isw(int ch) { return isalnum((unsigned char)ch) || ch == '_'; }

static int rx_fold(struct rx_ctx *c, int ch)
{
  if (c->p->cflags & REG_ICASE) return tolower((unsigned char)ch);
  return (unsigned char)ch;
}

static int rx_at_bol(struct rx_ctx *c, int pos)
{
  if (pos == 0) return !(c->eflags & REG_NOTBOL);
  if ((c->p->cflags & REG_NEWLINE) && c->s[pos - 1] == '\n') return 1;
  return 0;
}

static int rx_at_eol(struct rx_ctx *c, int pos)
{
  if (pos == c->len) return !(c->eflags & REG_NOTEOL);
  if ((c->p->cflags & REG_NEWLINE) && c->s[pos] == '\n') return 1;
  return 0;
}

/* 0 = explored, 1 = budget exhausted (the caller must unwind and report
   REG_ESPACE, never REG_NOMATCH). */
static int rx_run(struct rx_ctx *c, int pc, int pos)
{
  struct rx_inst *in;
  int old, r, i, gs, ge, n;
  long bit;

  for (;;) {
    if (++c->steps > RX_STEP_BUDGET) return 1;
    if (c->memo) {
      bit = (long)pc * (long)(c->len + 1) + (long)pos;
      if (c->memo[bit >> 3] & (1 << (bit & 7))) return 0;
      c->memo[bit >> 3] |= (unsigned char)(1 << (bit & 7));
    }
    in = &c->p->inst[pc];
    switch (in->op) {
    case RXI_CHAR:
      if (pos >= c->len || rx_fold(c, c->s[pos]) != in->x) return 0;
      pos++; pc++; break;
    case RXI_ANY:
      if (pos >= c->len) return 0;
      if ((c->p->cflags & REG_NEWLINE) && c->s[pos] == '\n') return 0;
      pos++; pc++; break;
    case RXI_CLASS:
      if (pos >= c->len) return 0;
      /* No case fold here: rx_bracket folds the SET when it builds it, which
         is the only order that works for a range -- folding the subject
         instead asks whether `a' is in [A-Z]. Two mechanisms for one concept
         is how the second one stays wrong, so there is one. */
      if (!RX_TST(c->p->cls + (size_t)in->x * 32, (unsigned char)c->s[pos]))
        return 0;
      pos++; pc++; break;
    case RXI_BOL:
      if (!rx_at_bol(c, pos)) return 0;
      pc++; break;
    case RXI_EOL:
      if (!rx_at_eol(c, pos)) return 0;
      pc++; break;
    case RXI_JMP:
      pc = in->x; break;
    case RXI_SPLIT:
      r = rx_run(c, in->x, pos);
      if (r) return r;
      pc = in->y; break;
    case RXI_SAVE:
      old = c->cap[in->x];
      c->cap[in->x] = pos;
      r = rx_run(c, pc + 1, pos);
      c->cap[in->x] = old;
      return r;
    case RXI_BACKREF:
      gs = c->cap[in->x * 2];
      ge = c->cap[in->x * 2 + 1];
      if (gs < 0 || ge < 0) return 0;      /* the group never matched */
      n = ge - gs;
      if (pos + n > c->len) return 0;
      for (i = 0; i < n; i++)
        if (rx_fold(c, c->s[pos + i]) != rx_fold(c, c->s[gs + i])) return 0;
      pos += n; pc++; break;
    case RXI_BOW:
      if (pos >= c->len || !rx_isw(c->s[pos])) return 0;
      if (pos > 0 && rx_isw(c->s[pos - 1])) return 0;
      pc++; break;
    case RXI_EOW:
      if (pos == 0 || !rx_isw(c->s[pos - 1])) return 0;
      if (pos < c->len && rx_isw(c->s[pos])) return 0;
      pc++; break;
    case RXI_WB: {
      int before = (pos > 0) && rx_isw(c->s[pos - 1]);
      int after  = (pos < c->len) && rx_isw(c->s[pos]);
      if ((before != after) != (in->x != 0)) return 0;
      pc++; break;
    }
    case RXI_MATCH:
      /* THE ACCEPT THAT DOES NOT ACCEPT. Record and return failure, so the
         alternatives still to be tried are actually tried -- this is what
         makes the result leftmost-LONGEST rather than leftmost-first. */
      if (pos > c->bestend) {
        c->bestend = pos;
        for (i = 0; i < c->nslot; i++) c->best[i] = c->cap[i];
      }
      return 0;
    default:
      return 0;
    }
  }
}

/* ---- the public entry points ---------------------------------------------- */

int regcomp(regex_t *preg, const char *pattern, int cflags)
{
  struct rx_prog *p;
  struct rx_parse ps;
  int err;

  if (!preg || !pattern) return REG_BADPAT;
  p = (struct rx_prog *)calloc(1, sizeof(struct rx_prog));
  if (!p) return REG_ESPACE;
  p->cflags = cflags;
  p->err = 0;

  ps.pat = pattern;
  ps.len = (int)strlen(pattern);
  ps.pos = 0;
  ps.ere = (cflags & REG_EXTENDED) ? 1 : 0;
  ps.icase = (cflags & REG_ICASE) ? 1 : 0;
  ps.group = 1;                 /* group 0 is the whole match */
  ps.depth = 0;
  ps.p = p;

  if (rx_emit(p, RXI_SAVE, 0, 0) < 0) { err = REG_ESPACE; goto fail; }
  if (!rx_alt(&ps)) { err = p->err ? p->err : REG_BADPAT; goto fail; }
  if (!rx_at_end(&ps)) { err = REG_EPAREN; goto fail; }  /* unreachable today */
  if (rx_emit(p, RXI_SAVE, 1, 0) < 0) { err = REG_ESPACE; goto fail; }
  if (rx_emit(p, RXI_MATCH, 0, 0) < 0) { err = REG_ESPACE; goto fail; }

  p->ngroup = ps.group - 1;
  preg->re_nsub = (size_t)p->ngroup;
  preg->__prog = (void *)p;
  preg->__cflags = cflags;
  preg->__nnodes = p->ninst;
  return 0;

fail:
  free(p->inst);
  free(p->cls);
  free(p);
  preg->re_nsub = 0;
  preg->__prog = 0;
  preg->__cflags = 0;
  preg->__nnodes = 0;
  return err;
}

void regfree(regex_t *preg)
{
  struct rx_prog *p;
  if (!preg) return;
  p = (struct rx_prog *)preg->__prog;
  if (p) { free(p->inst); free(p->cls); free(p); }
  preg->__prog = 0;
  preg->re_nsub = 0;
  preg->__nnodes = 0;
}

int regexec(const regex_t *preg, const char *string, size_t nmatch,
            regmatch_t pmatch[], int eflags)
{
  struct rx_prog *p;
  struct rx_ctx c;
  int nslot, start, i, first, last, rc, budget;
  long memobits;

  if (!preg || !string) return REG_NOMATCH;
  p = (struct rx_prog *)preg->__prog;
  if (!p) return REG_NOMATCH;

  first = 0;
  last  = (int)strlen(string);
  if (eflags & REG_STARTEND) {
    if (nmatch < 1 || !pmatch) return REG_NOMATCH;
    first = (int)pmatch[0].rm_so;
    last  = (int)pmatch[0].rm_eo;
    if (first < 0 || last < first) return REG_NOMATCH;
  }

  nslot = (p->ngroup + 1) * 2;
  c.p = p;
  c.s = string;
  c.len = last;
  c.eflags = eflags;
  c.nslot = nslot;
  c.bestend = -1;
  c.steps = 0;
  c.memo = 0;
  c.cap  = (int *)malloc((size_t)nslot * sizeof(int));
  c.best = (int *)malloc((size_t)nslot * sizeof(int));
  if (!c.cap || !c.best) { free(c.cap); free(c.best); return REG_ESPACE; }

  /* The memo is what keeps a back-reference-free pattern polynomial, and it is
     UNSOUND with back-references because a capture can change what matches --
     so it is allocated only when there are none. Skipped, too, when the table
     would be larger than the win: the budget still bounds the run. */
  memobits = (long)p->ninst * (long)(c.len + 1);
  if (!p->hasback && memobits > 0 && memobits < 64L * 1024L * 1024L)
    c.memo = (unsigned char *)calloc((size_t)((memobits + 7) / 8), 1);

  rc = REG_NOMATCH;
  budget = 0;
  /* The memo is zeroed by calloc above and never cleared again -- once for
     the whole regexec, not once per start position, and both halves of that
     are deliberate.
       NOT PER START, because the cautious version is quadratic for nothing:
     `(pc,pos) explored with no match' is a claim about the PROGRAM and the
     SUBJECT, and no instruction can see where the attempt began. A start that
     DID match returns immediately, so an entry can never suppress a match a
     later start would have found -- there is no later start.
       AND BY calloc, because a memset is a step that can be removed. It was:
     the mutation that deleted it was invisible to 4900 differential cases,
     since a fresh malloc on this box hands back zeroed pages and the engine
     read stale-but-zero memory. An allocation that cannot come back dirty has
     no such failure to test for. */
  for (start = first; start <= last; start++) {
    for (i = 0; i < nslot; i++) { c.cap[i] = -1; c.best[i] = -1; }
    c.bestend = -1;
    if (rx_run(&c, 0, start)) { budget = 1; break; }
    if (c.bestend >= 0) { rc = 0; break; }
  }

  if (budget) rc = REG_ESPACE;

  if (rc == 0 && nmatch > 0 && pmatch && !(p->cflags & REG_NOSUB)) {
    for (i = 0; i < (int)nmatch; i++) {
      if (i <= p->ngroup) {
        pmatch[i].rm_so = (regoff_t)c.best[i * 2];
        pmatch[i].rm_eo = (regoff_t)c.best[i * 2 + 1];
      } else {
        pmatch[i].rm_so = -1;
        pmatch[i].rm_eo = -1;
      }
    }
  }

  free(c.cap);
  free(c.best);
  free(c.memo);
  return rc;
}

size_t regerror(int errcode, const regex_t *preg, char *errbuf, size_t errbuf_size)
{
  const char *m;
  size_t n;
  (void)preg;
  switch (errcode) {
  case REG_NOERROR:  m = "Success"; break;
  case REG_NOMATCH:  m = "No match"; break;
  case REG_BADPAT:   m = "Invalid regular expression"; break;
  case REG_ECOLLATE: m = "Invalid collation character"; break;
  case REG_ECTYPE:   m = "Invalid character class name"; break;
  case REG_EESCAPE:  m = "Trailing backslash"; break;
  case REG_ESUBREG:  m = "Invalid back reference"; break;
  case REG_EBRACK:   m = "Unmatched [, [^, [:, [., or [="; break;
  case REG_EPAREN:   m = "Unmatched ( or \\("; break;
  case REG_EBRACE:   m = "Unmatched \\{"; break;
  case REG_BADBR:    m = "Invalid content of \\{\\}"; break;
  case REG_ERANGE:   m = "Invalid range end"; break;
  case REG_ESPACE:   m = "Memory exhausted"; break;
  case REG_BADRPT:   m = "Invalid preceding regular expression"; break;
  default:           m = "Unknown error"; break;
  }
  n = strlen(m) + 1;
  if (errbuf && errbuf_size > 0) {
    size_t k = n > errbuf_size ? errbuf_size - 1 : n - 1;
    memcpy(errbuf, m, k);
    errbuf[k] = 0;
  }
  return n;
}
