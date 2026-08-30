---
track: C
prio: 60
type: bug
status: done
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

## Resolution — an ANGLED include was searching the including file's directory

The ticket said to start by printing what the host fallback resolves
`sys/param.h` to. There was already a tool for it — `--debug` prints
`C preprocessor: include <path>` at the resolution site — and one run answered
it:

```
C preprocessor: include /usr/include/sys/param.h
...
C preprocessor: include /usr/include/sys/signal.h
C preprocessor: include /usr/include/sys/signal.h        (x 140)
```

`/usr/include/sys/signal.h` is **one line**: `#include <signal.h>`. glibc ships
these forwarders. `CPSearchInclude` searched `baseDir` — the including file's own
directory — **for every include, quoted or angled**, so `<signal.h>` from inside
`/usr/include/sys/` resolved to `/usr/include/sys/signal.h`: itself. C 6.10.2
gives the including file's directory to `"..."` only; `<...>` gets the
implementation's own places and nothing else.

That is why the depth tracked the cap. Nothing was nesting 129 deep; one file
was including itself until the buffers ran out.

The no-split was **deliberate and documented** — `CPHeaderNameOf`'s own comment
said *"pxx's search is not gcc's (no `<>`-vs-`""` split, a crtl anchor, a
`-nostdinc` rule of its own)"*. The other two divergences stay; this one had to
go, because here the standard's split is load-bearing rather than stylistic.

### The trap inside the fix, which cost a full build to find

Step 1 was unconditional, so its `CPLoadInclude` doubled as **the reset**: every
later loop is `while CPIncludeLength(depth) = 0`. Guarding step 1 with `if not
angled` left the slot holding the *previous* search's file, so all three loops
became no-ops and the new name silently resolved to the old file's text.
Measured: `<endian.h>` re-read `bits/wordsize.h` **32 times**, never reached
`bits/endian.h`, `__BYTE_ORDER` went undefined, and busybox's `platform.h` said
*"Can't determine endianness"* — a plausible wrong answer three files away from
the cause, and green on the pinned binary. The `else` branch clears the slot
explicitly and says why.

## Two claims in the report that this box contradicts

Both are host-layout artifacts, and neither changes the diagnosis:

- **"`/usr/include/sys/` does not exist on this box"** — here it does, and
  `sys/param.h` is a symlink into `x86_64-linux-gnu`. The runaway happens
  anyway, so the missing directory was never the mechanism.
- **"with `-I/usr/include/x86_64-linux-gnu` the identical header compiles
  fine"** — here it **also fails**, because that directory has its own
  `sys/signal.h` forwarder. The control that looked clean was clean only for
  one layout. This is why the regression test is a self-contained fixture
  rather than `<sys/param.h>` itself.

## What is asserted

`test/cinc/` already existed as the include-search fixture, so the third row
went there rather than into a second one — the split belongs beside the search
order:

| row | form | must resolve to |
| --- | --- | --- |
| `cinc_local.h` | quoted | the including file's own directory |
| `cinc_msg.h` | quoted | falls through to a `-I` root |
| `cinc_shadow.h` | quoted, but its BODY is `#include <cinc_shadow.h>` | the `-I` root — **not itself** |

Row 3 is glibc's `sys/signal.h` verbatim. On the pinned binary it reproduces the
bug exactly (`nesting too deep ... level 17`); on the fix it prints
`angled-skips-file-dir-ok`.

Also asserted by hand against gcc: an angled include of a sibling is now
**refused** as gcc refuses it; a genuinely absent header still reports
`C include file not found`; and that diagnostic no longer lists `baseDir` for an
angled include, since we no longer search it.

## The real gate: busybox

```
$ pascal26 -D_GNU_SOURCE -Iinclude bb.c        # autoconf.h + libbb.h
warning: crtl does not define xzalloc, xstrtoull_range_sfx, ... 
ok: ... [code=265896B  data=13772B  bss=68136B  procs=1381]
```

**`libbb.h` compiles**, so all 145 TUs are unblocked and
[[feature-c-corpus-busybox-applet]] moves from an include-resolution wall to
ordinary crtl gaps — a list of undefined symbols, which is the kind of work that
ticket was filed to do. `sys/param.h` was the only header of its kind in that
build.

The A-ticket's correction stands as this ticket predicted: raising the buffer cap
does not unblock busybox, and
[[bug-a-c-preprocessor-include-buffers-are-sixteen-globals-not-an-array]] is
worth landing on its own merits, not as busybox's blocker.

## Paired regression check

No corpus regressed. Built with both the pinned binary and the fix, and diffed
the outcomes rather than eyeballing one arm: zlib (`deflate.c`), sqlite
(`sqlite3.c --threadsafe`), cJSON, and lua all end at the identical point on
both arms — `main function not found` for the library TUs, which is the correct
answer for a file with no `main`. `gate.sh quick` GREEN; self-host fixedpoint
converged.

## Log
- 2026-08-30 — resolved, commit 1672aeaad.
