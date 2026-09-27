---
track: C
prio: 30
type: bug
status: open
found: 2026-09-27
found-by: frankD
owner:
summary: "pxx's va_list is a plain 24-byte struct on every target (lib/crtl/include/stdarg.h). On x86-64 gcc's is `__va_list_tag[1]`, so a va_list PARAMETER is a pointer: `sizeof ap` in a callee is 8 (pxx 24), and a callee's va_arg advances the CALLER's list (pxx: a copy, so the caller does not see it). Portable C may not rely on either -- after passing ap on, the caller's ap is indeterminate until va_end -- and on aarch64 gcc's own va_list is a struct with pxx's semantics. Recorded, not urgent: the header said `va_list[1]` until 2026-09-27, but pxx never modelled that `[1]`."
---

# va_list is a struct, not an array of one

```c
static int take(va_list ap) { return va_arg(ap, int); }
static int sz(va_list ap) { return (int)sizeof ap; }
/* f(0, 10, 20): take(ap) then va_arg(ap, int) */
/* gcc x86-64: take=10 next=20 param sizeof 8 */
/* pxx:        take=10 next=10 param sizeof 24 */
```

Measured 2026-09-27 on v445 and after
bug-c-an-array-typedef-of-structs-is-not-modelled, which made array typedefs of
structs real and, to keep va_list exactly as it was, changed stdarg.h's
`typedef struct __pxx_va_elem va_list[1];` (whose `[1]` pxx had always ignored)
to the plain struct its own comment describes.

Making it an array would change how every target passes one: abi.inc passes the
24-byte class by value in memory on SysV and indirectly on AAPCS64, and
CVaListAddr, va_copy and the crtl v*printf family all assume a record. Do it
only with every target's variadic tests (test-core's c_va_arg_every_target and
the qemu jobs) and a caller-visible-consumption row per target, since the right
answer differs by target (aarch64 gcc: a struct).
