---
slug: bug-c-volatile-is-dropped-by-the-lexer
track: C
prio: 40
type: bug
status: open
created: 2026-11-23
found-by: claude-pxx (C store->reload at -O2)
tags: [c-frontend, optimiser, volatile]
blocked-by: []
summary: "The C lexer drops `volatile` before it becomes a token, so no symbol or type records it. Today every pass that could reuse a load either excludes C globals or declines a whole function whose tokens mention volatile (CAttrFlags $8000, CBodyMentionsVolatile). Gap: a volatile scalar local declared through a typedef (`typedef volatile int vint; vint x;`) is not seen, and any future pass that caches loads must remember the rule. Fix: record volatile on the symbol (and pointee) like const."
---

# C `volatile` is not recorded anywhere

Found 2026-11-23. clexer.inc CSkipSpace consumes `volatile`, `__volatile`
and `__volatile__` together with `inline` and `restrict`. pxx has kept
volatile code correct so far only because nothing at -O2 reused a load.

Where it matters now:

- The C store->reload pass (IRMarkRedundantReloads, -O2 for C since
  fc7bbfef34) excludes C globals in ReloadElimSym, and since be321968e9
  declines every symbol in a C definition whose tokens had a `volatile`
  dropped before them (CVolatileInRange, ParseCSubroutine).
- Reads and writes through a volatile pointer, and a spin on a volatile
  global, keep their memory accesses at -O2 and -O3 (checked by hand
  2026-11-23); nothing caches those today.

Not covered: a typedef'd volatile scalar local. The typedef's own tokens
carry the mark, not the function's.

## Fix

Record the qualifier: a per-symbol flag for the object itself (`volatile
int x`, `int *volatile p`) and a pointee flag for `volatile int *p`, set
by the declarator parser and copied through typedefs. ReloadElimSym (and
any later load-caching pass) asks the symbol, and the whole-body rule can
go.
