---
track: C
prio: 85
type: bug
status: working
owner: claude-C@opus5
---

# `sizeof(p->arr)` returns the POINTER size, not the array size — silent buffer overflow

- **Type:** bug (C frontend, silent memory corruption) — **Track C** (cfront)
- **Found:** 2026-08-02 by the Track B agent, via vendored pdfgen writing a
  truncated PDF `/CreationDate`. Filed, not fixed: `compiler/**` is not Track B's
  to edit.
- **Severity:** this one writes past the end of an array. Filed to `urgent/`.

## Minimal repro

```c
#include <stdio.h>
struct info { char title[64]; char date[64]; };
struct doc  { struct info *info; };
int main(void) {
  struct info i; struct doc d; d.info = &i;
  printf("%d\n", (int)sizeof(i.date));        /* 64  correct */
  printf("%d\n", (int)sizeof(d.info->date));  /* 8   WRONG, want 64 */
  return 0;
}
```

| expression | pxx | gcc |
| --- | --- | --- |
| `sizeof(struct info)` | 128 | 128 |
| `sizeof(i.date)` (direct member) | 64 | 64 |
| `sizeof(d.info->date)` (**through a pointer**) | **8** | 64 |
| `sizeof(pd->info->date)` | **8** | 64 |

So the array member is decaying to a pointer before `sizeof` is applied, but
only when reached through `->`. Direct `.` access is correct, which is why this
survived: the obvious test passes.

## It overflows, it does not merely truncate

`sizeof(p->buf)` is one of C's most common idioms — `snprintf(p->name,
sizeof(p->name), ...)`, `memset`, `strncpy`, `read`, `fgets`. When the real
array is SMALLER than a pointer, the bogus 8 is larger than the buffer and the
bound becomes an overflow:

```c
struct small  { char buf[4]; int guard; };
struct holder { struct small *s; };
...
sm.guard = 0x41414141;
memset(h.s->buf, 'X', sizeof(h.s->buf));   /* writes 8 bytes into 4 */
```

| | pxx | gcc |
| --- | --- | --- |
| `sizeof(h.s->buf)` | 8 | 4 |
| `guard` after the memset | **0x58585858** (clobbered) | 0x41414141 |

The adjacent field is overwritten with `'XXXX'`. Nothing warns, nothing crashes.
For arrays larger than 8 the same bug truncates instead — both directions are
silently wrong.

## How it surfaced (the plausible-wrong-value shape)

Vendored pdfgen (`lib/vendor/pdfgen/pdfgen.c:1049`):

```c
strftime(obj->info->date, sizeof(obj->info->date), "%Y%m%d%H%M%SZ", &tm);
```

`date` is `char[64]`; `sizeof` gave 8, so `strftime` got a buffer bound of 8 and
the PDF came out with a truncated date. Against a **gcc-built pdfgen oracle**
on the same input:

| | `/CreationDate` |
| --- | --- |
| gcc-built pdfgen | `(D:20260802102817Z)` — 15 chars |
| pxx-built pdfgen | `(D:2026080)` — **7 chars** |

The PDF stayed structurally valid and opened fine, which is exactly the failure
mode this repo's debugging note describes: not a crash, a plausible wrong value
far from the cause.

## Confirmed by one-token substitution

Not inferred — isolated. pdfgen compiled as a **pure C** translation unit
(`#include "pdfgen.c"`, no Pascal anywhere, **zero warnings**), then rebuilt
with the single expression `sizeof(obj->info->date)` replaced by the literal
`64` and nothing else changed:

| build | `/CreationDate` |
| --- | --- |
| pxx, unmodified | `(D:2026080)` |
| pxx, `sizeof(...)` → `64` | `(D:20260802083149Z)` |
| gcc oracle | `(D:20260802102817Z)` |

One token, and the bug goes away. The pure-C build also settles attribution:
the `time`/`bcmp` Pascal-binding warnings do not appear there at all, and the
date is truncated identically with and without them.

## Ruled out while narrowing

Both of these were the initial suspects and both are **innocent** — recorded so
the next reader does not re-walk them:

- `time(&now)` in a pure C compile writes its out-parameter correctly and
  matches gcc, despite the arity warning that appears in mixed Pascal+C builds
  (that warning is real but separate —
  [[bug-b-crtl-host-header-and-arity-mismatches-building-pdfgen]]).
- `strftime` / `localtime_r` produce the correct 15-character string in a pure C
  compile. (One unrelated nit noticed: pxx's `localtime_r` returns UTC where
  gcc's applies the local timezone — separate, minor, not this bug.)

The cause is `sizeof`, and only through `->`.

## Gate

`sizeof(p->arr)` equals the declared array size for arrays both larger and
smaller than a pointer, through one and several levels of `->`, matching gcc;
plus the overflow probe above showing the adjacent field intact. A gcc-built
pdfgen oracle comparison on `/CreationDate` is the end-to-end check.
