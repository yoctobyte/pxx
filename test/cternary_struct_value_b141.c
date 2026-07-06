/* Ternary with struct-valued arms: `c = cond ? a : b` must copy the selected
 * struct, not treat its first 8 bytes as the source address. Regression for the
 * sqlite CREATE TRIGGER "out of memory" bug: the parser stack's Token copy
 * `yymsp[-10].minor.yy0 = (cond ? tokA : tokB)` copied 16 bytes from *(tok.z)
 * (the SQL text!) into the Token, so sqlite3DbStrNDup(db, z, n) later got the
 * text bytes AS the pointer and a garbage ~3.2GB length. Root cause: AN_TERNARY
 * lowering yielded IR_LOAD_SYM for the record temp (EmitLoadVar scalar path =
 * load first 8 bytes) where the record value model requires IR_LEA (address). */
typedef struct { const char *z; unsigned n; } Token;

static Token pick(int which, Token a, Token b) {
  Token r;
  r = (which ? a : b);          /* by-value params through ternary */
  return r;
}

int main(void) {
  Token a, b, c;
  a.z = "t1 AFTER INSERT ON a"; a.n = 2;
  b.z = "otherother";           b.n = 7;

  c = (b.n == 0 ? a : b);       /* else arm */
  if (c.z != b.z || c.n != 7) return 1;

  c = (b.n != 0 ? a : b);       /* then arm */
  if (c.z != a.z || c.n != 2) return 2;

  c = pick(1, a, b);
  if (c.z != a.z || c.n != 2) return 3;

  /* nested ternary of structs */
  c = (a.n == 2 ? (b.n == 7 ? b : a) : a);
  if (c.z != b.z || c.n != 7) return 4;

  return 42;
}
