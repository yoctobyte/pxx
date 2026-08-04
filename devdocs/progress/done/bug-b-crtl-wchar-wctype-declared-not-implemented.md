---
summary: "wcslen, the twelve isw* predicates and towlower/towupper were declared by <wchar.h>/<wctype.h> and implemented nowhere, so calling one imported it from glibc"
type: bug
track: B
prio: 50
---

# `<wchar.h>` / `<wctype.h>` were declarations with no implementation

- **Type:** bug — Track B (library / crtl), tag `compat` (gcc/glibc parity)
- **Status:** done
- **Opened:** 2026-08-05
- **Found by:** sweeping all 317 buildable `test/c*.c` for a spurious
  `DT_NEEDED` while fixing
  [[bug-cfront-spurious-dt-needed-libc-with-no-imports]] —
  `test/cwide_string_literal` was importing `wcslen`.

## Symptom

`lib/crtl/include/wchar.h` and `wctype.h` declared `wcslen`, `towlower`,
`towupper` and the twelve `isw*` predicates. There was no `src/wchar.c` and no
`src/wctype.c`, so nothing was ever pulled, every prototype stayed external, and
each call became a glibc dynamic import.

Same shape as the socket bug found alongside it, and it hides the same way: on a
glibc host the program *works*, so the only visible symptom is that the binary
is dynamically linked — which nothing was checking.

## The interesting part is what happens above 127

crtl is C-locale-only, and it would be easy to treat that as a limitation to
apologise for. It is not: **glibc's C locale answers FALSE for every one of
these predicates on every value above 127**, and `towlower`/`towupper` are the
identity there. Read off a gcc build over the whole range before writing a line:

| input | glibc C locale |
| --- | --- |
| `-1` (WEOF) | all false, passes through both case functions |
| `0..127` | ASCII rules |
| `128..255` | uniformly `000000000000`, identity |
| U+0100, U+0391, U+4E00, U+1F600 | all false, identity |

So the ASCII range is not a subset being settled for — it is the answer. An
implementation that tried to be locale-aware above 127 would be *wrong* here.

## Fix

- `lib/crtl/src/wchar.c` — `wcslen` (a plain scan; `wchar_t` is 32-bit, so no
  encoding is involved), `towlower`, `towupper`.
- `lib/crtl/src/wctype.c` — the twelve predicates, plus `wctype()`/`iswctype()`.
  The `wctype_t` tags are private: C promises only that a `wctype()` result is
  meaningful to `iswctype()`, so they need not match glibc's and the test
  compares behaviour rather than the number.

No header changes were needed: `<wctype.h>` already includes `<wchar.h>` first,
so `src/wchar.c` is pulled before `src/wctype.c` and there is none of the guard
cycle that the socket veneer ran into.

## Test

`test/cwctype.c`, in `lib-test`, with **no recorded expectations** — the whole
output is diffed against a gcc build of the same file. It covers WEOF through
255 against all twelve predicates plus both case functions, and four wide values
a locale-aware libc *would* classify. Identical to gcc on all 262 lines, and on
i386, arm32, aarch64 and riscv32 as well.

`lib-test` also asserts the **linkage**, because the output diff passes either
way on a glibc host — exactly the blind spot that let this sit.

## Sweep result

All 318 buildable `test/c*.c` now build statically except two, and neither is a
defect: `crtl_libc_oracle` links libc **by design** (it is the oracle this
surface is measured against) and `cquickjs_prereq` needs `--threadsafe`
([[bug-c-pthread-without-threadsafe-builds-then-dies-at-load]]).

## Gate

`tools/gate.sh lib` GREEN; c-conformance i386 219 pass / 0 fail (1 known VLA
skip) — the cross re-run any crtl change owes, since crtl compiles for every
target while `lib-test` is x86-64 only.
