---
track: C
tags: [c, types, typeof, typedef, rump, netbsd, silent-miscompile]
prio: 10
type: bug
blocked-by: []
summary: "`dtp *q` (dtp a pointer typedef), `__typeof__(P) *q`, `__typeof__(T *) *q` and `__typeof__(*(&s->f))` lost the struct two levels down: sizeof(**q) was 8, typeof(*q) was a pointer to nothing, and `->member` through it read the wrong place. NetBSD's atomic_load_consume(&fdp->fd_dt)->dt_ff[0] is that shape, and rump's fd_free KASSERT failed at boot."
status: done
owner: claude-dupwt
---

# A pointer to a pointer typedef loses the pointee two levels down

`ParseCDeclType`'s pointer suffix counted only the declarator's own stars. A
star over a pointer typedef therefore gave depth 1, with the typedef's
`Pointer` as the base kind and no record. `dt_t **q` was right (depth 2 over
the record), but `dtp *q` meant the same type and was not. Three `typeof`
paths led into the same hole:
- `typeof(expr)` never set `baseRec`, so the depth-2 element record was empty;
- `typeof(T *)` (the type-name form) never recorded the pointee at all;
- `typeof(*(&s->f))` was read through the AN_DEREF/AN_ADDR pair, where the
  pointee readers know only the plain field.

NetBSD's `atomic_load_consume(p)` is
`({ const volatile __typeof__(*(p)) *__al_ptr = (p); const
__typeof_unqual__(*(__al_ptr)) __al_val = *(__al_ptr); __al_val; })`. In
`fd_free`, `atomic_load_consume(&fdp->fd_dt)->dt_ff[0]` read the wrong
member, so `KASSERT(... == fdp->fd_dfdfile[0])` failed in `rump_init`.

## Fix

- A star over a non-function pointer typedef or `typeof` with a known pointee
  starts at depth 1, with the pointee as base kind and record.
- The depth >= 2 element record falls back to the pointer's base record.
- `typeof(T *)` records its pointee.
- `typeof(*(&x))` reads `x`.

## Proof

`test/c_pointer_to_pointer_typedef_pointee.c` (row c_pptd26) matches gcc:
sizes `176 176 176 176 176`, a member through `(*q)->`, and both
`atomic_load_consume` shapes. latest-7deee32b0f printed `8 8 8 8 8` and
`0 0`.
