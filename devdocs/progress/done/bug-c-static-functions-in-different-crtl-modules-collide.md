---
track: C
prio: 50
type: bug
summary: "`static` functions with the same name in two crtl .c files (or a static in a header) share one unit identity, so the duplicate-definition warning false-fires — legal C flagged as a redefinition. Blocks promoting that warning to an error"

owner: agent-an-night
---

# `static` functions in different crtl modules are treated as one unit

- **Type:** bug — Track C (C frontend, translation-unit identity)
- **Status:** done
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

## Investigated 2026-08-05 — the concrete reason, and why it is not a one-liner

`CPullCrtlForPrototypes`' own header says it: the pulled crtl module is appended
as `#include` lines to the MAIN token stream and *"then goes through the same
pass 1 / pass 2 as the main program."* So `fcntl.c` and `unistd.c` are not two
translation units that happen to share a unit index — in pxx's model they **are**
one translation unit. `CurrentUnitIdx` is correct; the model is what differs
from C.

That rules out the cheap fixes:

- **No per-proc source-file provenance exists.** There is no `ProcSrcFile` /
  `ProcDeclFile` field, so the duplicate check cannot compare originating files
  instead of unit indices without new state.
- **No internal-linkage flag exists.** `static` is not recorded per proc
  (`CProcHasLocalDef` means "a body was seen in this TU", not "file-local"), so
  the warning cannot simply skip statics.
- **Skipping statics wholesale would be wrong anyway.** Within ONE genuine TU,
  two same-named statics IS an error in C and gcc rejects it. Suppressing them
  trades a false positive for a lost true positive.

So the fix really is the structural one below: give each pulled `.c` its own
unit identity. Recording this so the next attempt does not re-derive it.

## Fix direction

Give each C source module its own unit identity so `ProcUnitIdx` distinguishes
them (the warning's third term already tests it), and make a `static` definition
private to its module rather than entered in a shared namespace. A `static`
declared in a HEADER is per-including-TU by the same rule.

## Measured 2026-08-10 — no body wins; the warning is a pure false positive

Re-checked because last session's crtl work (the C-owns-its-math split,
`task-c-stop-the-compiler-authoring-crtls-contents`) makes hand-prototyped C
pull more crtl modules into one program, so co-pulled collisions are more
reachable than when this was filed. The question was whether the symptom is
still only a spurious warning.

**It is.** The section above says this "becomes a miscompile the moment two crtl
modules define a same-named `static` with **different** bodies". Measured
directly, that is **not** what happens.

Method: the two `sysret` bodies are byte-identical, which makes the question
unobservable — so each copy was temporarily marked with a distinct return offset
(in the working tree only, reverted; nothing committed) and a program was built
that reaches both, `open()` through `fcntl.c` and `dup()` through `unistd.c`.
Run in **both** directions so the answer could not be an artifact of pull order:

| marked module | `open()` (fcntl's `sysret`) | `dup()` (unistd's `sysret`) | reading |
| --- | --- | --- | --- |
| `unistd.c` (+1000) | `3` — plain fd, unmarked | `1004` — marked | each used ITS OWN body |
| `fcntl.c` (+2000) | `2003` — marked | fails on the bogus fd | each used ITS OWN body |

The marker follows its own module in both directions. **Each caller binds to the
static defined in its own `.c`**; the second body does not win, so there is no
silent miscompile to escalate — this stays prio 50 rather than becoming an
urgent bug.

**But the warning's TEXT is wrong**, and that is worth fixing on its own:

    warning: duplicate definition of 'sysret' in the same translation unit
             — the later body wins

"the later body wins" is a false statement about what the compiler then does,
printed on legal C. Anyone who trusts it will go looking for a miscompile that
is not there — or, worse, "fix" correct code to avoid it. Whoever takes this
ticket should either scope the message to what is actually true or suppress it
for this case; the structural fix in "Fix direction" above remains the real
answer.

(`ldd` on the built binary still reports "not a dynamic executable", so the
co-pulled modules are not leaking to glibc.)

## 2026-08-12 — the message is now TRUE; the structural fix stays open

The section above asked whoever took this to "scope the message to what is
actually true or suppress it for this case". The message is fixed; the
translation-unit-identity work in "Fix direction" is untouched and this ticket
stays open for it.

What the old text claimed — "the later body wins" — is false even inside ONE
genuine translation unit. Measured on a single .c file with two same-named
statics (gcc rejects it outright, pxx warns and compiles):

```c
static int helper(int x) { return x + 1;  }
int fa(void){ return helper(1); }
static int helper(int x) { return x + 10; }
int fb(void){ return helper(1); }
main -> printf("%d %d", fa(), fb())      /* pxx prints: 2 11 */
```

`fa` binds the FIRST body and `fb` the second, i.e. a call binds whichever body
was current when the CALL was compiled — exactly what the Pascal-side warning
(`parser.inc` ~28659) already says and the C copy had dropped. The C text now
mirrors it, and adds the crtl caveat so a reader hitting the known false
positive is not sent hunting for a miscompile:

    duplicate definition of 'X' in the same translation unit; the later body
    wins for calls written after it, calls written between the two bind to the
    earlier one (a file-scope 'static' defined in two separate crtl modules is
    legal C and warns here spuriously)

Deliberately NOT suppressed for statics: no internal-linkage flag exists (see
the 2026-08-05 investigation), and suppressing wholesale would trade a false
positive for the lost true positive of two same-named statics in one real file
— the case reproduced above.

## Fixed 2026-08-15 — the structural fix the 2026-08-05 investigation called for

That investigation ruled out the cheap fixes and named the answer: *"give each C
source module its own unit identity"*. Done, minimally — not a new unit index
per module (which would ripple through resolution), but the one fact the
duplicate check was missing: **which `.c` MODULE a body's text came from**.

`CModRange*` (defs.inc) records, per token index, the innermost enclosing `.c`
on the include stack; `CMarkTokModule` / `CModuleOfTok` (parser.inc) fill and
read it; `ProcCModule[procIdx]` stamps it at body-compile time; the warning
grows a fourth term, `ProcCModule[procIdx] = CModuleOfTok(...)`.

Attributing a header's static to the module that INCLUDED it is the point —
that is the translation unit it would belong to in a real build, so
`lib/crtl/src/fcntl.c` and `unistd.c` each own their own `sysret`.

Two supporting changes the measurement forced:

- **The `# <line> "<path>"` markers are now emitted without `-g`.** They are the
  only record of file provenance, and everything DWARF does with them stays
  gated at the consuming end. One short line per file transition.
- **The crtl prototype pull is its own module.** `CPullCrtlForPrototypes`
  preprocesses its synthetic `#include` block SEPARATELY, so a guarded header
  the main file already expanded is expanded again there — which is why
  stdarg.h's six `__pxx_va_*_impl` statics still collided after the first cut,
  with both copies attributed to the main module. In C those are two
  translation units. Real `.c` markers inside the block refine it further.

### Verified — both halves, because the ticket was right to insist on both

| | before | after |
| --- | --- | --- |
| `test/cisatty.c`, `cposix_io.c`, `crtl_lfs64_aliases_b234.c`, `crtl_posix_io_leaf_b238.c` (`sysret`) | warned | **0 warnings**, run unchanged |
| `test/cvariadic_struct_b208.c` (six `__pxx_va_*`) | warned 6× | **0 warnings**, runs, exit 42 |
| two same-named statics in ONE `.c` (gcc: *"redefinition of 'helper'"*) | warned | **still warns exactly once**, still prints `2 11` |

The true positive surviving is the whole reason this is not "skip statics":
that would have traded a false positive for a lost real diagnostic, exactly as
the 2026-08-05 note warned.

New `test/cstatic_two_modules.c` (must warn 0× and run) and
`test/cstatic_same_module_dup.c` (must warn exactly 1× and print `2 11`),
wired into `test-core` as a pair so neither half can be lost.

The warning text also drops its "warns here spuriously" caveat, which was only
ever describing this bug.

`gate.sh quick` + self-host fixedpoint GREEN, **FPC seed canary included** —
which caught the one real slip: `InternStr` lives in `emit.inc`, included AFTER
`clexer.inc`, so the interning moved inside `CMarkTokModule`
(bug-a-fpc-seed-drift-emitasmx64-forward again).

### Unblocks

[[bug-a-duplicate-definition-silently-accepted]] — its suggested gate is to
promote this warning to a hard error in both frontends. The C side was blocked
on these five files warning on legal code; the tree is now clean, so that
promotion is a decision rather than a blocked one.

## Log
- 2026-08-15 — resolved, commit 298f2e5fe.
