---
slug: bug-c-logical-not-is-not-folded-in-a-constant-expression
title: "Unary `!` is not folded in a C constant expression, and a negative array bound is accepted"
track: C
prio: 55
type: bug
blocked-by: []
status: done
owner: opus5-frank1
created: 2026-08-26
commit: 2a5d0e95c
summary: "CEvalConstPrimary's unary chain had -, + , ~ and & and not !, so `char[1 - 2*!!(cond)]` — BUILD_BUG_ON, as busybox and the Linux kernel spell it — died as `Expected: ], but got:` with no mention of !. Folded, the second half appeared: pxx ACCEPTED the -1 bound the macro produces, so every compile-time assertion in a source compiled and never fired. Found by compiling busybox 1.37.0; +5 files."
---

# Unary `!` in a C constant expression, and the bound the idiom exists to produce

Found by pointing pxx at busybox 1.37.0, which is the top pick of
[[idea-c-realworld-test-targets]] and which the user asked for directly:
*"testing and improving our C compiler … busybox is interesting — because it
would allow a very minimal system: linux kernel, busybox, pxx compiler."*

## Repro

```c
sizeof(char[3])              /* 3   ok */
sizeof(char[1 - 2*0])        /* 1   ok */
sizeof(char[!!(0)])          /* Expected: ], but got: (Kind: 136) */
sizeof(char[1 - 2*!!(0)])    /* Expected: ], but got: (Kind: 136) */
```

`CEvalConstPrimary` handled `-`, `+`, `~` (tkNot) and `&`, and not `!`
(tkLogNot). The rest of the chain was already complete — `CEvalConstEquality`
and `CEvalConstRelational` fold the `cond` these wrap — so exactly one unary arm
was missing. The diagnostic never mentioned `!`: the fold stopped, the bracket
met a token the dimension reader could not use, and it reported the bracket.

That expression is `BUILD_BUG_ON`, spelled identically by busybox and the Linux
kernel:

```c
#define BUILD_BUG_ON(condition) ((void)sizeof(char[1 - 2*!!(condition)]))
```

## The second half, which is the one that matters

With `!` folded, `coreutils/cat.c` compiled — and so did a **failing**
assertion:

```c
enum { A = 1, C = 2 };
(void)sizeof(char[1 - 2*!!(A != C)]);   /* bound is -1 */
```

| | |
| --- | --- |
| gcc | `error: size of unnamed array is negative` |
| pxx | accepted, silently |

The bound is 1 when the condition is false and -1 when it holds, so **the
assertion IS the refusal**. Accepting it does not merely differ from gcc — it
inverts the program's intent, turning every compile-time assertion in the source
into a no-op that reports success. busybox has hundreds. This is not the
FPC-parity ceiling ("accepting a form the reference rejects is not a defect"):
there the program still means what it says, here it means the opposite.

## The fix

One arm in `CEvalConstPrimary`:

```pascal
else if CurTok.Kind = tkLogNot then
begin
  Next;
  if CEvalConstPrimary() = 0 then Result := 1 else Result := 0;
end
```

and one shared `CCheckArrayExtent`, called from **all three** extent readers —
the declarator's, `sizeof(type[N])`, and `sizeof(type[N]){...}`. Three, because
I put the check at one of them first and the negative case still compiled: the
declaration parser and `ParseCSizeof` each fold their own extents. One rule, one
message, one place (`normalise-dont-special-case.md`).

Zero stays legal (`char pad[0]` is a GNU extension pxx already accepts, and
sizeof answers 0 for it, matching gcc), and unsized `[]` never reaches the
check — both callers handle `tkRBrack` before folding.

## The c-testsuite caught my first scoping, reasoning did not

The check sat after the declarator's if/else, where it also saw the `-1` that
the `[]` arm sets for an array sized from its initializer. **C conformance went
220/0 → 217/3**, all three `int x[] = { 1, 0 }`:

| | |
| --- | --- |
| `00117.c` | `int x[] = { 1, 0 };` |
| `00216.c` | `struct Wrap local_wrap[] = { … };` |
| `00220.c` | `wchar_t s[] = L"hello…";` |

Moved inside the folded branch, which is the only one that produces a real
extent. Third time today a corpus overturned an assumption a build had already
"passed".

## Measured

busybox 1.37.0, `libbb` + `coreutils` + `editors` + `util-linux`, 307 files,
each compiled `--emit-obj` with its own `KBUILD_*`/`BB_VER` defines:

| | before | after |
| --- | --- | --- |
| compile clean | 181 | **186** |
| fail | 126 | 121 |

`coreutils/cat.c`, `coreutils/cp.c`, `libbb/xfuncs.c`, `util-linux/renice.c`,
`util-linux/umount.c`. Every `Expected: ]` failure in the sweep is gone.

| check | result |
| --- | --- |
| `run_c_conformance.sh` | 220 pass / 0 fail — baseline |
| `run_pascal_conformance.sh` | 346 pass / 0 fail — baseline |
| self-host | converged after 1 round |
| `gate.sh quick` | GREEN |

## Gate

`test/cconst_logical_not_array_bound.c` (positive, gcc -O0 oracle, includes the
zero-length and unsized arrays a naive check refuses) and
`test/cconst_negative_array_bound_fails.c` (must NOT compile; gcc agrees), both
wired into `test-core` and both run green through `testmgr --tier native`.

## What the busybox sweep says to do next

Of the 121 remaining failures, **96 are a missing crtl function, not a compiler
bug** — a library gap, and mostly a shallow one:

`strchrnul` `strcasecmp` `strncasecmp` `strverscmp` `mempcpy` `dprintf`
`getline` `fseeko` `alarm` `setsid` `mkfifo` `mknod` `mkstemp` `vasprintf`
`clearenv` `putenv` `getopt` `lchown` `utimensat` `posix_fallocate` …

plus a whole `*_unlocked` family (`getc_unlocked`, `putchar_unlocked`,
`fputs_unlocked`, `ferror_unlocked`, …) which in a crtl with no FILE locking are
aliases for the locked versions. `typeof` and `_IOR` are the odd ones out —
compiler/header features, not functions.

The remaining ~25 are real frontend gaps and are the interesting residue:
`IR_UNSUPPORTED: frontend could not lower AST node (kind 1)`, and `stray token
at top level` on `ALIGN1` / `FAST_FUNC` / `IP` — busybox's `__attribute__`
wrapper macros, so likely one attribute-parsing gap wearing three names.

Two driver gaps also surfaced and are worth their own tickets: pxx has **no
`-include <file>` and no `-D name=value`** (only boolean `-d<NAME>`), so
busybox's per-file build flags had to be reproduced in a source shim; and
`cat.c` alone raised 21 warnings for headers resolving from `/usr/include`
(`dirent.h`, `endian.h`, `byteswap.h`, `paths.h`, `mntent.h`) — which for the
no-GNU-userland goal is the gap that actually matters, since pxx's own
`lib/crtl/include` has 27 headers and none of those.
