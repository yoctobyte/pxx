---
prio: 55
---

# bug: a GLOBAL multidim array of pointers ignores its brace initializer

- **Track:** C (cfront)
- **Found:** 2026-07-13, csmith fuzzer (seed 711), while fixing the LOCAL half (b309, committed)

## Repro

```c
static int gv = 5;
static int *g[2][3] = {{&gv,&gv,&gv},{&gv,&gv,&gv}};
int main(void){ return g[1][2] == &gv; }   /* gcc: 1.  pxx: 0 -- every element is nil */
```

The LOCAL form (`int *a[2][3] = {...}` inside a function) is FIXED (b309,
`test/cmultidim_ptr_array_init_b309.c`). The global form is not. Silent: no error, the
elements simply read back nil.

## Why the local fix does not carry over

Two different code paths in `cparser.inc`:

- **Local** (~line 3580, `CDeclStatement`): the multi-dim brace pre-scan was gated on
  `(declTk <> tyPointer) and (TypeIsOrdinal or TypeIsFloat)`. Deleting the pointer
  exclusion was the whole fix.
- **Global** (~line 6000): there IS a `dimCount >= 2` branch that routes to the
  deferred brace-elision walker (`CEmitDeferredCAggInits` / `CInitWalkArray`) — but it
  is unreachable for pointers, because an EARLIER flat pointer/fn-pointer pre-scan
  (~line 5528, the one that fills `arrKind`/`arrSym` and emits `PendingInit*` entries,
  `arrKind = 2` meaning "address of a named global") consumes the whole `{...}` first.
  That pre-scan is flat — it has no notion of nested braces or of the array's shape.

Simply loosening the `dimCount >= 2` guard at ~6000 is INERT (I tried it): by the time
control reaches there, `CurTok` is already past the braces. The earlier pre-scan has to
decline multi-dim pointer arrays (leaving the tokens for the walker), or learn the shape
itself.

Note globals need real data relocations for `&namedGlobal` (that is what `PendingInitFOff
= -4` is for), so whichever path wins must keep emitting those, not runtime stores —
unless it defers to `main` the way `CEmitDeferredCAggInits` already does, which would
also be acceptable.

## Guard

Extend `test/cmultidim_ptr_array_init_b309.c` with the global forms once it lands.
