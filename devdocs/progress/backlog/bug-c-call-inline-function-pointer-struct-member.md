# C: calling an inline function-pointer struct member mis-lowers

- **Type:** bug (C frontend → indirect-call lowering) — Track C
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]). Split from
  [[bug-c-function-pointer-struct-member]] (layout/registration — fixed).

## Symptom

After inline fn-ptr members are registered (layout fix landed), *calling* one
still produces wrong results — every call form, different wrong value:

```c
struct cfg { int (*fp)(int); };
static int add1(int x){ return x + 1; }
int main(void){ struct cfg c; c.fp = add1; return c.fp(41); }    /* want 42, got 36 */
/* p->fp(41)        -> 36                                                        */
/* (*c.fp)(41)      -> 85                                                        */
```

And sqlite3.c:19490 `0==sqlite3Config.xAltLocaltime((const void*)t,(void*)pTm)`
still fails (`unexpected token`) — the call form in a comparison/cast context.

## Key isolating fact

A **typedef'd** fn-ptr field calls **correctly**:

```c
typedef int (*fn)(int);
struct cfg { fn fp; };
...
int main(void){ struct cfg c; c.fp = add1; return c.fp(41); }    /* 42 — works */
```

A typedef member goes through ParseCStructInto's *normal* declarator path; the
inline member goes through the new fn-ptr branch. Both set `UFldProcSig`, and the
call path (`RecFieldProcSig` -> `AN_CALL_IND`, cparser.inc ~1148) is shared — so
the difference is in how the inline branch sets up the field vs the normal path.
Prime suspect: the field's element-type tag (`bfElemTk` = tyUnknown in the inline
branch vs the typedef's carried element type) or a sig-linkage detail the call
lowering reads. lua's fn-ptr calls worked because they are all typedef-based
(`(*g->frealloc)(...)`).

## Next step

Diff the registered field (and the emitted `AN_CALL_IND` IR) between the typedef
path and the inline path for the identical signature — find what the inline
branch must additionally set (likely `bfElemTk`/elem-rec or the proc-sig wiring)
so the indirect call reads the correct callee. Then handle the call form in a
cast/comparison context for the sqlite line.

## Acceptance

- `c.fp(41)` / `p->fp(41)` / `(*c.fp)(41)` for an inline fn-ptr member all == 42.
- sqlite advances past line 19490.
- Repros added to `test/`; C tests green + self-host byte-identical.

## Log

- 2026-06-27 - Split from the layout ticket once registration landed. Typedef
  path works; inline path mis-lowers (36/85). Diagnosis points at the inline
  branch's field setup vs the normal declarator path.
