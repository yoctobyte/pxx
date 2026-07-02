# crtl: `strtok` not implemented (undeclared function)

- **Type:** feature (crtl coverage gap)
- **Track:** B — `lib/crtl/src/string.c` (crtl function-body impl is Track B
  per [[feedback_crtl_impl_is_track_b]] file-ownership convention)
- **Status:** backlog
- **Opened:** 2026-07-02
- **Found while:** Track B probing `string.h` crtl coverage.

## Problem

```c
#include <string.h>
char src[] = "hello,world,foo";
char *tok = strtok(src, ",");
```

fails with `call to undeclared function: strtok`. `lib/crtl/src/string.c` has
`strcat/strchr/strcpy/strerror/strncat/strncpy/strpbrk/strrchr/strstr/memcmp/
strcmp/strcoll/strncmp/strcspn/strlen/strspn/strxfrm/memchr/memcpy/memmove/
memset` — `strtok` (and `strtok_r`) are the only common `string.h` functions
missing from that set.

## Why it matters

`strtok` is one of the most commonly reached-for `string.h` functions for
tokenizing (config parsing, CSV-ish splitting, simple protocol lines). Its
absence will silently wall off any C program that uses it, with no earlier
warning since everything else in `string.h` works.

## Scope

- Implement `strtok` (classic non-reentrant version, static internal
  save-pointer) and ideally `strtok_r` (explicit save-pointer, reentrant —
  needed for any threadsafe caller) in `lib/crtl/src/string.c`, matching
  standard semantics (delimiter set as second arg, `NULL` first-arg to
  continue from the saved position, consecutive delimiters collapsed, returns
  `NULL` when exhausted).

## Acceptance

```c
char src[] = "hello,world,foo";
char *tok = strtok(src, ",");
while (tok) { printf("[%s]", tok); tok = strtok(NULL, ","); }
```
prints `[hello][world][foo]`.

## Log
- 2026-07-02 — Filed by Track B while probing `string.h` coverage; rest of
  `string.h` (strcpy/strcmp/strstr/etc.) and `qsort`/`snprintf` all verified
  correct in the same session. No code touched — test/repro only.
