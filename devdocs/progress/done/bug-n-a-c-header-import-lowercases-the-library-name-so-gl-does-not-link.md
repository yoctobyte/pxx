---
slug: bug-n-a-c-header-import-lowercases-the-library-name-so-gl-does-not-link
track: N
prio: 50
type: bug
status: done
owner: frankB
created: 2026-09-08
found-by: frankuser
tags: [nilpy, ffi, headers, linking, lekkerzeilen]
blocked-by: []
summary: "FIXED. `import \"/usr/include/GL/gl.h\"` compiled green and died at exec with `libgl.so: cannot open shared object file`; the library is `libGL.so.1`. THE TICKET'S OWN DIAGNOSIS WAS WRONG AND THE CORRECTION IS THE FIX: nothing lowercases the library name. `/usr/include/GL/gl.h` has the file stem `gl` -- the capitals live in the DIRECTORY, which GetFileBaseName discards before any lookup runs -- so the exact /etc/ld.so.cache probe asked a question the host could not answer and the caller emitted its guess. Two changes: LdCacheFindSoname gained a CASE-INSENSITIVE second pass (a strict fallback, exact always wins, so no answer that resolved before can move), which reaches 176 of this box's 1417 cache keys and finds zero pairs differing only by case; and RegisterExternal -- the choke point where an external becomes a real DT_NEEDED, and already the home of the sibling guard for a SYMBOL no library can export -- now refuses a soname the compiler INVENTED from a file name that this host cannot resolve. Scoped by PROVENANCE, not by soname: a name the user wrote in an `external 'libfoo.so'` clause is intent, and LD_LIBRARY_PATH makes an absent-from-cache library a legitimate configuration that two in-tree tests and lib/pcl/tk.pas depend on. `import \"GL/gl.h\"` now links libGL.so.1 and runs."
---

# Repro

```
$ printf 'import "/usr/include/GL/gl.h"\nprint(glGetError())\n' > g.py
$ ./compiler/pascal26 g.py out          # compiles; two host-header warnings only
$ ./out
./out: error while loading shared libraries: libgl.so: cannot open shared object file
```

On disk: `/usr/lib/x86_64-linux-gnu/libGL.so`, `libGL.so.1`, `libGL.so.1.7.0`.

Note `import "/usr/include/GL/gl.h"` with only `print("reached")` **runs fine** —
the missing library is only reached when a symbol from it is actually called, so
the trivial probe passes and the real one fails.

# Why this is more than a `tolower` bug

`sqlite3.h` -> `libsqlite3.so.0` works, which is what makes the rule look sound:
the stem happens to be lowercase there, so **the sample that confirms the rule is
the one where case cannot matter.** A header stem is not a soname in general
(`GL/gl.h` -> `libGL.so.1`, `SDL2/SDL.h` -> `libSDL2-2.0.so.0`), so the mapping
wants the real mechanism — `pkg-config`, an explicit table, or a declared name —
rather than a case fix.

**Whatever replaces it, keep the failure at LINK time rather than exec time.**
A green compile that dies on startup is the worst of the three outcomes.


# RESOLVED 2026-09-10 — and the ticket's own cause was wrong

## What it actually was

`LowerCase` is in `CSonameForStem`, and it is not what loses the case. The stem
handed to it is already lowercase, because it is a FILE NAME:

```
/usr/include/GL/gl.h   ->  GetFileBaseName  ->  "gl"
                            ^^                   ^^
                            the capitals are here, and they are dropped here
```

So the ticket's "Why this is more than a tolower bug" section was right for a
better reason than it gave: a header stem is not a soname *and there was never a
case to preserve*. Removing the `LowerCase` would have changed nothing.

The mechanism it names — `pkg-config`, a table, a declared name — turned out to
be already present and simply asked the wrong question. `CSonameForStem` consults
`/etc/ld.so.cache` FIRST and falls back to nine hardcoded entries; the cache is
the real, host-derived, non-tabulated mapping the ticket wanted. It just could
not answer `libgl.so` when what it holds is `libGL.so.1`.

## The case-insensitive pass, and why it is safe

`LdCacheFindSoname` now scans the whole table and returns a case-insensitive hit
only when no exact one was seen. **An exact hit always wins**, which is the
property that makes this an addition rather than a policy change: nothing that
resolves today can move.

Measured on this box, 2026-09-10:

| | |
| --- | --- |
| distinct cache keys | 1417 |
| keys carrying an uppercase letter | 176 |
| pairs of keys differing ONLY by case | **0** |

So the fallback is unambiguous here and serves libGL, libGLU, libEGL, libFLAC,
libICE, libLLVM, libOpenCL and 169 others — not one library. Where a host does
hold two keys differing only in case and neither matches exactly, this takes the
first in cache order; that is a guess, and it is strictly better than the current
answer, which is a name that is in the cache at all.

## The half that outlives this ticket

**"Keep the failure at LINK time rather than exec time"** was the ticket's other
instruction, and it is the one that generalises: no case fix can map every header
to every library, so the residual has to be diagnosed rather than guessed.

The check went into `RegisterExternal`, which already carries its sibling — the
`__pxx_*` guard, for a SYMBOL no library can export — and describes itself as
*"the choke point where an unresolved external becomes a real import."* The
LIBRARY half was simply absent, and the reason is visible in the history: every
instance was fixed on the PRODUCER side, one at a time.

- `bug-c-a-header-reached-by-uses-discards-function-bodies-and-imports-them-instead`
  removed one way to synthesise *"a lib&lt;header&gt;.so that cannot exist, dead at
  load"*.
- `bug-a-a-c-include-path-captures-a-pascal-uses-and-emits-a-dynamic-import`
  removed another: *"the binary carries a DT_NEEDED on libstrings.so and dies at
  load. Nothing in the build says so."*

Two authors wrote that sentence about their own defect and neither added the
check that would say so. That is the ABSENCE shape, not a drift: no path was
wrong, a position was empty, and an empty position collides with nothing.

## PROVENANCE decides membership, and the measurement is why

The obvious guard — check every soname against the cache — is measurably wrong.
Censused 2026-09-10 across every `external '...'` clause in the tree:

| soname | on this host | what it is |
| --- | --- | --- |
| `libspill.so` | no | `test_c_argspill.pas` builds its own .so |
| `liblazycasing.so` | no | `test_c_lazycasing.pas`, likewise |
| `libtcl8.6.so.0` / `libtk8.6.so.0` | no | `lib/pcl/tk.pas`, an optional binding |

`test_c_lazycasing.pas` says it in its own comment: *"soname only — the loader
finds it via LD_LIBRARY_PATH (hermetic, like test_c_argspill)"*. An absent-from-
cache library is a **deliberate, in-tree-tested configuration**, and a whole-
soname check would refuse all four.

What separates them from `libgl.so` is not the name, it is who wrote it. A name
in an `external` clause carries intent the compiler must not second-guess; a name
the compiler derived from a file name is its own guess, and checking your own
guess against the host is not second-guessing anybody. So only synthesised names
are recorded (`CSynthMissingLibs`), and the guard fires on those alone.

**And it is recorded at import but consumed at RegisterExternal**, because an
import whose symbols are never referenced emits no DT_NEEDED and is a working
program — the ticket says so itself (*"`import ...SDL.h` with only
`print("reached")` runs fine"*). Diagnosing at import time would have been a
guard firing on a program that does not have the defect. That is the negative
control, and it is a test row.

## Tests

| row | asserts |
| --- | --- |
| `test_nilpy_a_referenced_symbol_from_a_library_that_cannot_exist` | positive control — rc=1, the diagnostic, **no binary** |
| `test_nilpy_an_unreferenced_header_import_needs_no_library` | negative control — compiles, runs, and **zero DT_NEEDED**, asserted |
| `test_nilpy_a_header_whose_library_is_not_spelled_like_its_file` | the ticket's repro; SKIPS loudly with no GL headers |

The first two are hermetic — `libnolib.so` exists on no machine — so they assert
the guard without depending on what this box has installed. The GL row asserts a
**RELATION** rather than a constant: whatever soname comes out must be one *this*
loader resolves. That carries to a box whose GL is `libGL.so.2`, and it still
fails on the pre-fix answer, because `libgl.so` resolves nowhere — so the row is
its own positive control and cannot pass on a revert.

## Not done, and it is measured rather than deferred by feel

See `feature-n-derive-a-header-s-library-from-its-directory-and-verify-it-against-the-library-s-own-dynsym`.
The one-line version: the DIRECTORY is a far better library key than the file
stem (617 headers versus 76 on this box), and `net/if.h -> libnet.so.9` is why it
cannot be added as written — that answer is a real library, so it passes this
guard and dies later on `undefined symbol`, which is worse than the loud failure
this ticket just fixed.

Gate: `gate.sh quick` RED on one row, `mimic_queue :: unknown type: TPyDeque` —
a pylib builtin no pin carries, unrelated to this change and unchanged by it.
`self-host fixedpoint`, `fpc seed compiles (forward decls)` and
`testmgr --tier quick` all PASS.

## Log
- 2026-09-10 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
