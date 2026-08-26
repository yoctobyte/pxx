---
track: U
prio: 35
type: decide
blocked-by: []
summary: "FPC ships two incompatible StrAllocs — `strings` allocates prefix-free, `sysutils` allocates with a 4-byte size prefix — and `uses SysUtils, Strings` silently pairs the first with the second's StrBufSize/StrDispose, which is a measured heap error. We shipped ONE implementation (the prefixed one, shared by both units). Confirm, or ask for FPC's two-implementation split reproduced warts and all."
status: backlog
owner: unassigned
---

# One StrAlloc, or FPC's two?

Filed 2026-08-25 by Track B while landing the PChar family
(`feature-b-rtl-gap-inventory-22-sysutils-strutils-symbols`). **A direction was
already taken and the code is green** — this ticket exists so the owner can
overrule it, not to block anything.

## The fork

FPC 3.2.2 has two different `StrAlloc`/`StrNew`/`StrDispose` implementations,
and which one a program gets depends on the ORDER of its `uses` clause:

| | `rtl/inc/strings.pp` | `rtl/objpas/sysutils/syspch.inc` |
| --- | --- | --- |
| `StrAlloc(L)` | plain `GetMem(L)`, **no prefix** | `GetMem(L+4)`, stores the size in a 4-byte Cardinal prefix, returns `p+4` |
| `StrDispose(p)` | plain `FreeMem(p)` | `FreeMem(p-4)` |
| `StrBufSize` | **does not exist** | reads the prefix |
| `StrNew(p)` | `GetMem(len)` + move | `StrAlloc(len)` + move |

Both are reachable, they are not interchangeable, and nothing warns you.
Measured, `fpc -O- -Mobjfpc -Sh`:

```pascal
uses sysutils, strings;      { strings is LAST, so its StrAlloc wins }
...
  p := StrAlloc(20);
  Writeln(StrBufSize(p));    { prints 4294967292 — reads 4 bytes BEFORE the block }
  StrDispose(p);             { frees p-4 }
```

Swap the two unit names and the same program prints `20`. The failing order is
the one that reads more naturally, and `StrDispose` there is a genuine
heap error that merely happens not to abort.

## What we did (the direction to confirm)

**One implementation, in `lib/rtl/strings.pas` — the prefixed one — with
`sysutils` forwarding to it.** Consequences:

- A program that uses only `strings`, or only `sysutils`, behaves exactly as
  under FPC. That is every real program we know of.
- A program that uses BOTH gets a correct `StrBufSize` and a correct
  `StrDispose` instead of FPC's garbage value and mis-freed pointer.
- `StrBufSize` becomes reachable from `strings`, where FPC does not export it.
  An added symbol, never a changed behaviour.
- One observable regression against FPC, and it is narrow: code that calls
  `strings.StrAlloc` and then frees with a bare `FreeMem` (legal under FPC's
  prefix-free `strings`, though `StrDispose` is the documented pairing) frees
  the wrong pointer here. We know of no such code.

## The alternative

Reproduce FPC exactly: give `strings` a prefix-free StrAlloc/StrNew/StrDispose
and no StrBufSize, and give `sysutils` its own prefixed set. Buys bit-exact
parity including the footgun; costs a second implementation of the same four
routines, which is the arm that stays broken
(`devdocs/dev/normalise-dont-special-case.md`).

## Recommendation

Keep the single implementation. It is upward-compatible with every
single-unit program, it removes a heap error rather than adding one, and it
matches the project's "pragmatic tool, not utopia" stance.

If confirmed, this earns a row in `devdocs/dev/pascal-dialect-divergences.md`
(that page's rule is that a row needs a RESOLVED `decide-*`, which is what this
ticket becomes). The code comment in `lib/rtl/strings.pas` already cites this
slug.
