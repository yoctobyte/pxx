---
slug: bug-c-an-undeclared-struct-type-compiles-and-reads-garbage
track: C
type: bug
prio: 45
status: backlog
owner: ""
created: 2026-09-24
found-by: frankS (fixing bug-b-terminalsize-answers-enotty-on-xtensa)
blocked-by: []
summary: "`struct nosuchtype v; v.field = 3;` COMPILES CLEAN on pxx and produces a working binary; gcc refuses it with `storage size of 'v' isn't known`. An undeclared struct tag, an invented member name and an unknown size all pass without a single diagnostic, and the generated code reads a plausible wrong value rather than trapping. FOUND THE EXPENSIVE WAY: <sys/ioctl.h> did not declare `struct winsize` (it does now), so the canonical `#include <sys/ioctl.h>` + `struct winsize ws; ioctl(1, TIOCGWINSZ, &ws)` gave an incomplete type -- and it printed cols=8650792, which is 0x00840028, i.e. the correct 132 and 40 read as ONE 32-bit field. rc was 0 and the syscall genuinely succeeded, so every signal available to the caller said the call worked. THE WRONG VALUE LOOKED LIKE A DIFFERENT BUG ENTIRELY: it appeared on x86-64 and xtensa alike while I was mid-way through an xtensa ioctl fix, so the obvious reading was that my constant was wrong on both -- it took a two-short control struct (which is correct: 132, 40) to separate the incomplete type from the ioctl. THE MISSING HEADER IS FIXED AND THIS IS NOT: any C source naming a struct pxx has not seen has the same shape, and the class is silent-wrong-value rather than refusal. NOT a blanket refusal of incomplete types -- `struct opaque *p;` and forward declarations are legal C and common; what must be refused is DEFINING AN OBJECT of, or taking a member from, a type of unknown size."
---

# An undeclared struct type compiles and reads garbage

## Reproducer

```c
#include <stdio.h>
int main(void) {
  struct nosuchtype v;
  v.field = 3;
  printf("%d\n", v.field);
  return 0;
}
```

- **gcc:** `error: storage size of 'v' isn't known`
- **pxx:** `ok: ... [code=61881B ...]` — compiles, links, runs.

Measured 2026-09-24 at HEAD on x86-64.

## How it surfaced, which is the part worth keeping

`lib/crtl/include/sys/ioctl.h` declared `TIOCGWINSZ` but not `struct winsize`,
while glibc's provides both. So the canonical spelling —

```c
#include <sys/ioctl.h>
struct winsize ws;
ioctl(1, TIOCGWINSZ, &ws);
printf("cols=%d rows=%d\n", ws.ws_col, ws.ws_row);
```

— compiled, the ioctl **succeeded** (`rc=0`), and it printed
`cols=8650792 rows=8650792`. `8650792` is `0x00840028`: `0x0084` is 132 and
`0x0028` is 40, the correct geometry, read as one 32-bit field instead of two
16-bit ones.

**Every signal the caller had said it worked.** The syscall returned 0, the
kernel really did fill the struct, and the only thing wrong was a member access
against a type of unknown layout.

**It also mimicked an unrelated bug.** This appeared while the xtensa
`TIOCGWINSZ` constant was being fixed, and the garbage showed up on **x86-64 and
xtensa alike** — which reads as "the new constant is wrong on both targets". A
control struct of two `unsigned short`s answers `132, 40` correctly, and that
asymmetry is what separated the incomplete type from the ioctl.

## Scope of the fix

**Not** a blanket refusal of incomplete types. `struct opaque *p;`, forward
declarations and pointers to undefined tags are legal C and used widely,
including in this tree's own headers. What must be diagnosed is:

- **defining an object** of a type whose size is unknown (`struct T v;`), and
- **taking a member** from such a type (`v.field`, `p->field`).

Both have an exact gcc wording to match if a differing diagnostic is not wanted.

## What is already done

`struct winsize` is now declared in `<sys/ioctl.h>` as well as `<termios.h>`,
guarded by `__struct_winsize_defined` so either include order works
(`bug-b-terminalsize-answers-enotty-on-xtensa-and-the-probe-cannot-say-why`).
That closes the instance. It does not close the class, and the class is
silent-wrong-value.
