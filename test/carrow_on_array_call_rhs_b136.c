/* `arr->field = call()` where `arr` is an array (not a pointer var). C lets
   `->` apply to an array via array-to-pointer decay, so `a->q` on `S a[1]`
   means the same as `a[0].q` / `(*a).q`. cparser.inc's `.`/`->` disambiguation
   (CNodeIsPointer) explicitly excludes arrays, so this built a plain AN_FIELD
   directly over the array AN_IDENT rather than an AN_DEREF-then-field like the
   pointer case gets. ResolveNodeRec's AN_IDENT branch then read the symbol's
   RecName -- but an array symbol stores its ELEMENT record in ElemRecName, not
   RecName (RecName is unset/wrong for an array symbol) -- so recId resolved to
   REC_NONE, which made the field's type tag default to tyInteger (4 bytes)
   instead of the real field type. A call-valued RHS (any call, not malloc
   specifically) then got truncated/miswritten through that wrong-width field,
   and because the store landed via the wrong offset/width it also corrupted an
   unrelated field set earlier in the same array (bug-c-arrow-on-array-store-of-
   call-result-clobbered). Fixed in symtab.inc's ResolveNodeRec: an array-typed
   AN_IDENT now resolves its ElemRecName. No malloc/crtl dependency needed --
   any call-valued RHS reproduces it, so this uses a deterministic call
   returning the address of a static local instead. */

extern long __pxx_write(int, const void *, unsigned long);

typedef struct { void *p; long q; } S;

static int backing;

void *give(void) {
  return &backing;
}

int main(void) {
  S a[1];
  a->q = 7;
  a->p = give();
  if (a->q != 7) return 1;                 /* unrelated field must survive */
  if (a->p != &backing) return 2;           /* full pointer, not truncated */

  S c[1];
  (*c).p = give();
  if ((*c).p != &backing) return 3;         /* already-working control form */

  S e[2];
  e[0].p = give();
  if (e[0].p != &backing) return 4;         /* already-working control form */

  S d;
  d.p = give();
  if (d.p != &backing) return 5;            /* already-working control form */

  if (a->p != (*c).p) return 6;             /* arrow-on-array form must match */

  return 42;
}
