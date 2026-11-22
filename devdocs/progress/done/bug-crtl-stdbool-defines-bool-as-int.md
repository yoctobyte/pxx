---
slug: bug-crtl-stdbool-defines-bool-as-int
track: crtl
prio: 55
type: bug
status: done
created: 2026-11-22
found-by: claude-pxx (building micropython v1.24.1's unix port with pxx)
tags: [crtl, cfront, bool, abi]
blocked-by: []
summary: "DONE 2026-11-22: crtl's <stdbool.h> had `#define bool int`, so `(bool)(x & 0x80)` was 128, not 1, and sizeof(bool) was 4 where gcc's is 1, which changed the layout of any struct with a bool in it. micropython's mpz_as_bytes compares `(bool)(most_sig & 0x80) == (bool)z->neg`, so every negative big int whose to_bytes filled the buffer exactly raised OverflowError. bool is now _Bool. That exposed three _Bool conversions the compiler skipped, all fixed: brace-initializer leaves (struct members, local array elements), file-scope constants (`static bool g = 300` stored 44), and ++/-- (`b = 1; b++` read 2). Test c_stdbool26 (x86-64, arm32; checked on all five)."
---

# crtl's stdbool defines bool as int

The header dated from the first crtl substrate (47ff12dbe5). With
`--system-libs`, gcc's own stdbool.h applies, so only crtl builds were affected.

## Compiler fixes it needed

Before this, `_Bool` was rare in crtl builds, so these conversions had gone
unnoticed. C99 6.3.1.2 says converting to _Bool is a comparison with 0:

- **Brace-initializer leaves**: CInitLeaf (struct members, local and static)
  and the local flat-array element store now pass through CNormalizeToBool.
- **File-scope constants**: CBoolConstV at the flat-array, scalar-literal and
  scalar-constant-expression PendingInit sites. These sites are C-only, because
  the shared consumer in symtab.inc also serves Pascal's sized booleans.
- **++ and --** on a _Bool: `++b` is `b = 1`, `--b` is `b = (b - 1) != 0`;
  postfix forms yield the old value (`b ? 1 : (b = 1, 0)`,
  `(b = ...) == 0`). Recorded separately as
  bug-c-increment-of-a-bool-is-not-converted-to-0-or-1, fixed here too.

Not covered: `bool b = 0.5` at FILE scope folds through the integer constant
evaluator and stores 0 (gcc: 1). A local `bool b = 0.5` is right.

## ABI note

sizeof(bool) going from 4 to 1 changes the layout of every crtl-built struct
holding a bool. That is the point: it now matches gcc and glibc. But objects built
by an older pxx against crtl and linked with new ones would disagree.
