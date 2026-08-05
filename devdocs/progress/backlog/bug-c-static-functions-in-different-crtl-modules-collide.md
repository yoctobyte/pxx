---
track: C
prio: 50
type: bug
summary: "`static` functions with the same name in two crtl .c files (or a static in a header) share one unit identity, so the duplicate-definition warning false-fires — legal C flagged as a redefinition. Blocks promoting that warning to an error"
---

# `static` functions in different crtl modules are treated as one unit

- **Type:** bug — Track C (C frontend, translation-unit identity)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** Track A, scanning the tree before promoting
  `bug-a-duplicate-definition-silently-accepted`'s warning to an error.

## What

`static` at file scope means **internal linkage**: the same name in two
translation units is two distinct functions, and C requires it to work. gcc,
measured:

```c
/* a.c */ static int helper(int x) { return x + 1;  }  int fa(void){ return helper(1); }
/* b.c */ static int helper(int x) { return x + 10; }  int fb(void){ return helper(1); }
```
    gcc a.c b.c m.c  ->  "2 11"     — each calls ITS OWN helper
    
pxx pulls crtl's modules into one proc table with one `CurrentUnitIdx`, so the
second definition looks like a redefinition of the first and the
duplicate-definition warning fires on legal code.

## Where it fires today

Five files in the tree, all false positives:

| file | name | why it is legal |
| --- | --- | --- |
| `test/cisatty.c`, `test/cposix_io.c`, `crtl_lfs64_aliases_b234.c`, `crtl_posix_io_leaf_b238.c` | `sysret` | `static` in BOTH `lib/crtl/src/fcntl.c` and `lib/crtl/src/unistd.c` |
| `test/cvariadic_struct_b208.c` (6x) | `__pxx_va_start_impl`, `__pxx_va_arg_gp/fp/cross`, `...32` | `static` in the HEADER `lib/crtl/include/stdarg.h` |

## Not currently a miscompile — checked

The two `sysret` bodies are **byte-identical**, so merging them changes nothing,
and `dup`/`open`/`close` behave exactly as gcc does when tested individually.
(An earlier reading of `printf("%d %d", dup(fd) >= 0, close(fd))` looked like a
failure; that was the TEST's bug — C leaves argument evaluation order
unspecified, so `close` ran first.)

It becomes a miscompile the moment two crtl modules define a same-named `static`
with **different** bodies, which nothing currently prevents. That is the real
risk, and it is silent.

## Blocks

`bug-a-duplicate-definition-silently-accepted` — its own "suggested gate" is to
promote the warning to a hard error in both frontends, matching gcc and FPC.
The Pascal side is clean tree-wide; the C side cannot be promoted while these
five files warn on legal code.

## Fix direction

Give each C source module its own unit identity so `ProcUnitIdx` distinguishes
them (the warning's third term already tests it), and make a `static` definition
private to its module rather than entered in a shared namespace. A `static`
declared in a HEADER is per-including-TU by the same rule.
