---
summary: "a C program using <pthread.h> without --threadsafe builds clean and then dies at load with `undefined symbol: __pxx_pmutex_init` — a pxx-internal symbol imported from glibc, which cannot possibly have it"
type: bug
track: C
prio: 55
---

# `<pthread.h>` without `--threadsafe` builds clean, then dies at load

- **Type:** bug — Track C (C frontend / external resolution). Diagnostics, not
  codegen: the code is fine once the flag is passed.
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** Track B, sweeping all 317 buildable `test/c*.c` for a spurious
  `DT_NEEDED` while fixing
  [[bug-cfront-spurious-dt-needed-libc-with-no-imports]].

## Symptom

```c
#include <pthread.h>
#include <stdio.h>
static pthread_mutex_t m;
int main(void){ pthread_mutex_init(&m, 0); pthread_mutex_lock(&m);
                pthread_mutex_unlock(&m); printf("ok\n"); return 0; }
```

```
$ pinned pt.c pt_bin        # compiles with no diagnostic at all
$ ./pt_bin
symbol lookup error: ./pt_bin: undefined symbol: __pxx_pmutex_init
$ echo $?
127
```

The binary carries `NEEDED libc.so.6` and imports **fourteen `__pxx_p*`
symbols** — `__pxx_pmutex_init`, `__pxx_pcond_wait`, `__pxx_pthread_create`
and so on. Those are **pxx's own PAL helpers**. glibc has never heard of them,
so the import can never resolve; it is not a dependency, it is a guess.

## The fix is a flag, which is the point

    pinned --threadsafe pt.c pt_bin     ->  0 NEEDED, 0 imports, prints "ok"

`--threadsafe` is what brings the Pascal thread PAL in. The `-I` flags that
`test/cquickjs_prereq`'s Makefile line also passes are irrelevant — measured
separately.

So nothing is broken except the diagnosis. The compiler should say

    pthread_mutex_init requires --threadsafe

at compile time, instead of emitting an import of a private symbol from a
library that cannot supply it and letting the dynamic loader deliver the news.

## Why it matters more than a missing flag usually would

1. **The failure is at load, not at link**, so it survives every build check.
2. **The message names `__pxx_pmutex_init`** — an internal symbol that appears
   nowhere in the user's source. There is no path from that message to
   "pass `--threadsafe`" without reading crtl.
3. **The gate hides it.** `test/cquickjs_prereq` passes because its Makefile
   line already carries `--threadsafe`; the default invocation of the very same
   file is broken. Nothing in the tree exercises `<pthread.h>` without the flag.

## Related

Same family as [[bug-a-libcfree-unresolved-extern-silent-zero]] (an unresolved
external patched to 0 rather than raising a link error): in both, an external
that cannot be satisfied is quietly turned into something that fails later and
elsewhere.

Distinct from the socket bug it was found next to — there the impl existed and
was merely unreachable by the auto-pull convention; here the impl is reachable
and genuinely needs a runtime the flag selects.

## Gate

`#include <pthread.h>` + a pthread call, with no flags, either compiles to a
working static binary or fails at COMPILE time naming `--threadsafe`. Never a
binary that imports `__pxx_*` from libc.
