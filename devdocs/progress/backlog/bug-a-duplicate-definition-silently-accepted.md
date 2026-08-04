---
summary: "two definitions of the same function (or global) are silently accepted in BOTH frontends — last one wins, except calls placed between them bind to the earlier, so identical source text calls different functions depending on position"
type: bug
track: A
prio: 55
---

# A duplicate definition is silently accepted, and binding is positional

- **Type:** bug — Track A (shared declaration handling / symbol table).
  **Not** a frontend bug: C and Pascal behave identically, so it is below both.
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** Track B, while consolidating `read`/`write`/`close`/`lseek` into
  one file ([[bug-b-crtl-printf-hexfloat-and-float-sign-flags]]). I had briefly
  defined `write` in **both** `lib/crtl/src/unistd.c` and `lib/crtl/src/stdio.c`
  — the program built, ran, and printed the right answer, so nothing indicated
  the mistake.
- **User note (2026-08-05):** plausibly historical — the function started
  hardcoded, then moved to a builtin, and the old definition was never rejected
  because nothing rejects duplicates.

## Repro — one file, no headers, no auto-pull

```c
#include <stdio.h>
int f(void) { return 1; }
int f(void) { return 2; }
int main(void) { printf("f=%d\n", f()); return 0; }
```

    gcc : error: redefinition of 'f'
    pxx : builds silently, prints f=2

Pascal is the same:

```pascal
program dp;
function F: Integer; begin F := 1; end;
function F: Integer; begin F := 2; end;
begin writeln(F); end.
```

    FPC : 4 errors
    pxx : builds silently, prints 2

## Measured behaviour

| case | gcc | pxx |
| --- | --- | --- |
| same signature, different body | error | accepted, **last wins** (2) |
| **different return type** (`int` then `double`) | error | accepted, caller prints **0** |
| **different parameters** (`f(void)` then `f(int)`) | 2 errors | accepted; `f()` with no argument returns 11 |
| three definitions | 2 errors | accepted, third wins |
| duplicate **global variable** | error | accepted, last wins |
| `static` (internal linkage) duplicate | error | accepted, last wins |
| duplicate **procedure** (Pascal, no result) | FPC error | accepted, second runs |

## The part that is worse than "last one wins"

Binding is **positional**, so the same source text means different things
depending on where it appears:

```c
int f(void) { return 1; }
int mid(void) { return f(); }     /* binds to the FIRST  */
int f(void) { return 2; }
int main(void) { printf("mid=%d f=%d\n", mid(), f()); }   /* binds to the SECOND */
```

    pxx: mid=1 f=2

So there is no single answer to "what does `f` mean in this program" — two
identical call sites call two different functions. Whatever the eventual rule
is (reject, or first-wins, or last-wins), this is not it.

The differing-return-type row is the other bad one: the second definition
returns `double`, the caller is compiled for `int`, and it reads **0** — a type
confusion accepted without a word.

## Severity — why backlog and not urgent

It does not miscompile *valid* code: a program with no duplicates is unaffected,
which is why this sat undisturbed. What it does is **silently accept invalid
code**, so a genuine mistake — a stale definition left behind after a move,
exactly the crtl case above — produces a working binary and no signal. It is a
bug-hider rather than a bug, and it hid one for me tonight in under a minute.

Worth pairing with the C-side observation that pxx also accepts a call whose
arity does not match the visible definition; that may be the same missing check.

## Suggested gate

A second definition of the same name at the same scope is a compile error, in
both frontends, matching gcc and FPC. If some part of the bootstrap currently
relies on redefinition (the builtin-migration history above makes that
plausible), find it first — the error will say exactly where.
