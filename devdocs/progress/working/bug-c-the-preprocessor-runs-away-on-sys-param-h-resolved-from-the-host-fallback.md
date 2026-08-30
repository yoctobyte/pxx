---
track: C
prio: 60
type: bug
status: working
owner: frankC
blocked-by: []
summary: "`#include <sys/param.h>` with no `-I` recurses until it hits the include-nesting cap, whatever that cap is — it reported level 17 with sixteen buffers and level 129 with 128. With `-I/usr/include/x86_64-linux-gnu` the same header compiles fine, gcc compiles it fine, and every one of its own includes compiles fine both alone and all together. So it is the host-fallback RESOLUTION of `sys/param.h`, not the header's content or the depth limit. This is what actually blocks busybox — raising the include-buffer cap does NOT unblock it."
---

# `<sys/param.h>` recurses to the include cap when resolved from the host fallback

- **Type:** bug — **Track C** (the C preprocessor's include resolution,
  `cpreproc.inc`). Found by frankS 2026-08-30 while verifying
  [[bug-a-c-preprocessor-include-buffers-are-sixteen-globals-not-an-array]].
- **Why it is filed separately:** it is a different defect in a different
  mechanism, and it is the one that actually blocks the busybox corpus.

## The finding that matters: raising the cap does not unblock busybox

[[bug-a-c-preprocessor-include-buffers-are-sixteen-globals-not-an-array]] was
re-scoped by frankC to *"blocks all 145 busybox translation units"*, with
`libbb.h` reported as reaching level 17 — one past the sixteen buffers. That
reads as "the cap is one too low for real code."

**It is not.** Built with the cap raised to 128, the same busybox repro fails
again — at **level 129**. The failure depth tracks the cap, which is the
signature of runaway recursion rather than genuine nesting.

| cap | busybox repro fails at |
| --- | --- |
| 16 buffers | level 17 |
| 128 buffers | level 129 |

## It is ONE header, and the sweep that concluded otherwise was incomplete

The A-ticket records *"cumulative depth, not one pathological header"*, having
checked `stdio.h dirent.h endian.h byteswap.h paths.h libgen.h sys/stat.h`
individually. **`sys/param.h` was not in that list**, and on its own it is the
whole problem:

```c
#include <sys/param.h>
int main(void){ return 0; }
```

```
pascal26:1: error: C include nesting too deep
              (the preprocessor has 128 include buffers; this include is at level 129)
```

It is reached from `libbb.h:55`.

## What it is NOT — five controls, all clean

- **Not the header's content.** With `-I/usr/include/x86_64-linux-gnu` (where the
  file actually lives) **the identical header compiles fine.**
- **Not any of its includes.** `<stddef.h>` (with and without the
  `#define __need_NULL` protocol it uses), `<sys/types.h>`, `<limits.h>`,
  `<endian.h>`, `<signal.h>`, `<bits/param.h>` — each compiles alone.
- **Not their combination.** All of them in one file, in `sys/param.h`'s own
  order, `__need_NULL` included: compiles clean.
- **Not broken include guards.** A header that `#include`s itself inside a
  standard `#ifndef/#define/#endif` guard terminates correctly and matches gcc.
- **Not the missing-header path.** A plainly absent header gives the correct
  `C include file not found` diagnostic with its search list.

gcc compiles all of it.

## The remaining suspect

`/usr/include/sys/` **does not exist on this box** — the only `sys/param.h` is
`/usr/include/x86_64-linux-gnu/sys/param.h`, which is what gcc resolves
(`gcc -E -H` confirms). So `<sys/param.h>` is a header the host fallback cannot
find at `/usr/include/sys/param.h`, yet it does not take the not-found path
either. Whatever it resolves to instead recurses.

The trace before the error shows the chain reaching `endian.h` then `features.h`
twice, so it is getting somewhere real before it loops.

**Whoever takes this should start by printing what the host fallback resolves
`sys/param.h` to** — the answer is one instrumented line at the resolution site
and every hypothesis above is downstream of it. Do not start from the header.

## What a fix must assert

- `#include <sys/param.h>` with no `-I` compiles, and matches gcc.
- The busybox repro (`autoconf.h` + `libbb.h`) compiles — that is the real gate,
  and it is the one that shows whether `sys/param.h` was the only such header.
- A genuinely absent header still gives `C include file not found`, not a
  nesting error. That distinction is the whole shape of this bug.
- A multiarch-only header more generally: `sys/param.h` is unlikely to be the
  only one that lives solely under `/usr/include/<triple>/`.

## Note for the A ticket

The include-buffer array is still right and still worth landing — the sixteen
globals, three ladders and the dead `CPPathAtDepth` clamp are real. What must be
corrected is its **justification**: it does not unblock busybox, and
[[feature-c-corpus-busybox-applet]] should be `blocked-by` THIS ticket rather
than by the storage change.
