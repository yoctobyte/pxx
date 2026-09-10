# The pxx crash course — design and goals

**Read this before you touch a library, a frontend, or an import.** 15.7KB / ~3.9k tokens, measured 2026-09-10.
It exists because a seat with full access to this repo spent an evening in
2026-09-10 rediscovering settled design from first principles, proposed a
mechanism that already existed under another name, and told a peer two wrong
things on the way. The owner's diagnosis was that this is a documentation
failure, and he was right: **none of what follows was secret, and none of it was
anywhere a new agent would look.**

Every numbered item below is something that seat got wrong, with the measurement
that corrected it. That is deliberate — a crash course written from what people
actually trip on beats one written from what the architecture looks like from
inside.

---

## 0. The goal, in one line

**`devdocs/dev/the-goal-cross-cross.md`** (read it; it is short). Languages ×
platforms, the product of both axes. Two proofs, both real programs: DOSBox
compiles and runs; pxx hosts itself somewhere that is not Linux/x86-64.

**We do not chase FPC parity.** Real code compiling or running wrong is a bug.
A differing intermediate type, a differing diagnostic, a differing answer on
code nobody meant to write — not defects. CLAUDE.md's "The goal" section is the
authority and is already in your context.

---

## 1. ONE LIBRARY, TWO SURFACES — this is the thing most often missed

A `lib/rtl` unit is **implemented in Pascal** and carries a **Python-shaped face
beside its Pascal one, in the same unit.** Not a wrapper, not a separate shim,
not a second implementation. The owner's words, 2026-09-10:

> *"our (pxx) choice is to implement libraries in pascal by default, and have
> them importable to nilpy, transparently."*

`lib/rtl/base64.pas` is the smallest example:

```pascal
function Base64Encode(const data: TByteArray): AnsiString;   { Pascal callers }
function b64encode(const data: Variant): AnsiString;         { Python callers }
```

`import base64` from Nil Python reaches that unit and works today — measured,
round-tripping against CPython.

**It is the pattern, not a one-off.** A heuristic scan of `lib/rtl/*.pas`
(2026-09-10, crude — it keys on lowercase names and `TPy*`/`Variant` in the
interface, so treat the counts as indicative): **nine units carry both
surfaces** — `re.pas` with **42** Python-shaped entry points, plus `json`,
`pathlib`, `sockets`, `base64`, `markdown`, `mimic_array`, `mimic_string` — and
**fifteen more carry a Python surface only.**

### The marshalling types, which are the whole trick

`TPyBytes`, `TPyList`, `TPyDict`, `Variant`. A Pascal declaration using these is
callable from Nil Python with no glue. A `TPyBytes` **return** is proven —
`mimic_urllib_error.pas` has `function HTTPError.read(n: Integer): TPyBytes`.

**Corollary, and it is where the 2026-09-10 seat went wrong:** a Pascal unit
whose interface uses only Pascal types is **not** reachable from Nil Python, and
the failure is not obvious. `lib/rtl/zlib.pas` takes `hashing.pas`'s
`TByteArray = array of Byte`, and NilPy has **no spelling that constructs one** —
`bytes`, `bytearray`, `list(...)` and the return-lifted form all answer
`no overload of InflateZlib matches these arguments`. The fix is to add the
Python surface to the unit. **It is never a new `mimic_` wrapper for a library
we already have.**

**So: before proposing a mechanism, grep for it.** One `grep -l TPyBytes
lib/rtl/*.pas` would have saved that evening.

---

## 2. Import resolution: OURS FIRST, and predictability is why

The owner's rule, 2026-09-10:

> *"our import rules are like. native language first. built-in and rtl libraries
> first. so zlib.pas has prio over /usr/include/zlib.h in case we specify 'zlib'
> in pascal or python.."*

and, immediately after, the reason — **which outranks the rule, because he said
the rule is not absolute and the reason is not:**

> *"well, my ruling is not absolute. it's because mixing languages creates a big
> mess where no-one can predict the outcome."*

**So the test for any resolution question is "can a reader of the import site
predict what it binds?", not "is this the right precedence."**

### What is true today (measured 2026-09-10, and partly broken)

| spelling | resolves to | |
| --- | --- | --- |
| Pascal `uses zlib` | `lib/rtl/zlib.pas` | **correct** |
| NilPy `import zlib` | `/usr/include/zlib.h` | **bug — and it now LINKS** |
| NilPy `import base64` | `lib/rtl/base64.pas` | correct |
| NilPy `import 'zlib.pas' as z` | the unit, explicitly | correct — the escape hatch |

There are **three doors ahead of the `mimic_` fallback** for a bare NilPy
import: a system C header, a Pascal unit, a sibling/relative `.py`. The `mimic_`
mapping is consulted **only after every ordinary lookup fails**
(`pasparser_proc.inc:6500`, in its own comment), so a shim named after a module
we already have a unit or a header for is **never reached.**

**A fix landed mid-writing and made this WORSE, not better — re-measured at
`49489e5ca437`.** frankH's `15f293d4a` added the missing `zlib -> libz.so.1`
soname row, so `import zlib` now builds, links and runs. The door did not move:

```
zlib.uncompress          OK            <- the C header still wins
zlib.InflateZlib         no member     <- our own unit still unreachable
zlib.crc32(b"hello")     no overload   <- C arity, not CPython's
```

So a Python `import zlib` now **silently succeeds into a host C library**. The
loud failure that used to mark the wrong door is gone, and what a Python caller
gets instead is a *signature* complaint — `no overload of crc32 matches these
arguments` — which says nothing about having reached C. **A fix that removes the
symptom without moving the door makes a predictability bug quieter.** That is
not a criticism of the fix, which is correct for an explicit header import; it is
the reason §2's rule is about the door and not about whether the build succeeds.

**And the behaviour still depends on the build machine, not just the
languages present:** `import zlib` binds the host's `/usr/include/zlib.h`
natively, under `--target=i386`, and under **`--target=wasm32`** — still true at
`49489e5ca437`, and now resolving to a real host soname rather than a missing
one, for a target that has no shared libraries at all. On a box with no `zlib.h`
the same source falls through to our unit. A wasm32 build binding a
host glibc header is wrong under *any* precedence, so the fix is "a bare Python
import must not reach host C headers", not a reorder. Open at p85:
`bug-n-a-same-named-rtl-unit-shadows-both-a-relative-import-and-a-mimic-shim`.

**A relative import is not a bare name.** `from . import platform` has a leading
dot: the program is scoping the name to itself, so its own module wins
regardless of the above. Today `lib/rtl/platform.pas` takes it, which is a live
wall on lekkerzeilen's portability seam.

**Sonames are derived from the header's stem, and there are FOUR shapes, not
one** — frankH measured this at `39441c6fe` after declining to assume they were
one mechanism:

| | |
| --- | --- |
| `sqlite3.h` → `libsqlite3.so` | binds — the stem **is** the library, by luck |
| `zlib.h` → `libzlib.so` | refused — the stem is not (fixed by a table row, `15f293d4a`) |
| `SDL2/…h` → `libsdl_version.so` | binds via the **directory** rule |
| a resolution that succeeded and was then overwritten | built a silent bad binary that died at exec (`967f9cc93`) |

The general answer is measured too: asking which library on this box **exports**
the symbol, over all 1439 `ld.so.cache` entries, gives **one** library for
`crc32`, `compress`, `deflate`, `inflate`, `sqlite3_open`, `png_read_png`; two
for `curl_easy_init` (one library, two TLS backends); three for `SDL_Init` (one
library, three major versions). **Ambiguity is real but structured** — never
unrelated libraries competing for a name. Open as
`decide-c-should-a-libc-symbol-from-an-unresolvable-header-bind-to-libc` (p55),
restated as: **does an import name a library, or a place to look for one?**

---

## 3. Shims are NOT a last resort

`devdocs/dev/python-libraries.md` §2 used to rank re-implementation last. **The
owner overruled that**, 2026-09-10:

> *"mimicing is not last resort. it's actually.. it proven to be cheaper to just
> re-implement than trying to jump hoops in a lot of cases. PNG was implemented
> in a 20 minute session."*

The record is stronger than the anecdote: `lib/rtl/png.pas` landed in one
evening (20:40 → 21:46, 2026-06-20) and has had **no functional change in the 82
days since.** Read §2's table as available strategies, **not** a cost ranking;
§2b covers why the stdlib sits differently (most of it is a CPython C extension,
so there is no pure-Python upstream to compile).

**Why library work is cheap, in the form that matters:** a library written over
stdlib primitives **comes with its own oracle** — run it on CPython, run it on
pxx, diff (`tools/pydiff.py`). Compiler work has no such cheap oracle. This is
not a slogan: the first run that tested the dual-surface pattern found a bug in
it inside ten minutes (`base64.b64encode` returns a string where CPython returns
bytes — values identical, type wrong, so every value assertion passed).

**THE FREE ORACLE HAS ONE TRAP AND IT IS FLOATS.** Measured 2026-09-10, on the
owner's suggestion, by sweeping `math.sin` over 0..1 in 0.001 steps and diffing
`repr()` against CPython: **70 of 1001 rows differ**, max |delta| 1.11e-16 —
one ULP. `sin` is *correct* and *not bit-identical*. So a conformance fixture
that diffs the printed form of a float against CPython will redden on ~7% of
rows for no defect at all, and whoever writes it will spend an evening on it.
Diff floats against a **tolerance**; byte-exact diffs are for bytes, strings and
integers, where they are unanswerable. (There is no blessed ULP threshold. A
seat wrote one into CLAUDE.md the same evening, attributed to the owner, from a
remark that was a joke — see the F-lane bullet there for what the joke was
actually about, which is that a last-ulp ticket is cheap to write and a missing
module is not.)

**And NilPy compiles.** A plain-Python shim is native code. Pick a shim's
implementation language by **which one can express the job**, never by speed —
`mimic_struct.pas` is Pascal because reinterpreting bytes needs a pointer cast;
`mimic_bisect.py` and `mimic_copy.py` are Python because they can be.

**Three rules from §2 are untouched by the overrule** and they are about
correctness, not preference: never load a prebuilt `.so`; implement only the
surface the caller touches; look, don't copy — keep the real library installed
and **diff against it**, because its behaviour is the spec.

---

## 4. pxx writes its own ELF. There is no external linker.

No shell-out to `ld`, `gcc` or `cc` anywhere in `compiler/**`. `lib/crtl` is
**our own C library** (~60 `.c` files, our own `syscall()`), so a C
`#include <stdio.h>` resolves to *our* header. Output is **statically linked, not
a dynamic executable** — our own compiler binary included.

**What pxx cannot do is CONSUME an object.** `pascal26 a.o b.o out` answers
`pascal26:1: error: unexpected character` — it parses the `.o` as source. So a
program past one translation unit needs a foreign linker today, which is why
busybox's 521-object build borrows `gcc -o out obj/*.o` while its unity build is
fully freestanding. Open at p70:
`feature-a-pxx-cannot-link-its-own-objects-so-a-freestanding-multi-object-program-needs-gcc`.

**Do not read a `gcc` in a harness as a pxx limitation.** In
`tools/busybox_diff.sh` the gcc build is the **oracle** — the same program built
two ways so the outputs can be diffed. Mistaking that for a capability gap is
exactly the error this document exists to prevent.

---

## 4b. A LIBRARY IS CONFIGURED BY A RECIPE — synapse is the worked example

The owner, 2026-09-10: *"that's why we invented a configuration per library or
application, in case of such. for compiler defines, import paths, etc."*

**The pattern is real and in use; the declarative file format for it is designed
and NOT built.** Both halves matter, and the first version of this document
recorded the whole thing as "could not find it", which was wrong — I had
`python-libraries.md` open and stopped one section short of §3.

### What exists: a per-library recipe, held in shell + Makefile

`tools/install_externals.sh` and the `lib-test` rules are the live example.
Synapse — the third-party Pascal TCP/IP library — carries all four parts:

| part | where | synapse's value |
| --- | --- | --- |
| **pinned source identity** | `install_externals.sh:27` | `SYNAPSE_REPO` + `SYNAPSE_COMMIT = b3224c3d…` (a commit, not a branch), both env-overridable |
| **location convention** | `:23` | `external/`, gitignored, fetched on demand |
| **the build line** | `Makefile:33388` | `--mimic-fpc -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix` |
| **graceful absence** | `Makefile:33385` | prints `SKIP … external/synapse absent` and records it, rather than failing |

That last row is the part to copy rather than the part to skim: a library nobody
fetched must **SKIP, never fail and never silently pass** — the repo already paid
for getting that wrong once
(`bug-b-lib-test-unrunnable-in-a-fresh-clone-no-synapse-fetch`).

### The knobs a recipe sets

- `-Fu<dir>` — add a Pascal unit search root. `PXX_LIBPATH=a:b` for extra roots
  (after `-Fu`, before the defaults).
- `-d<NAME>` / `-u<NAME>` — define / undefine a conditional symbol.
- `--mimic-fpc` — adopt FPC's define set for identity-probing headers. This is
  what lets a library written for FPC compile unchanged.
- `--strict-fpc` — the FPC-parity umbrella (`--strict-case`, `--strict-overload`,
  `--strict-operator`, `--strict-python`, `--strict-visibility`). Note the
  direction: **Synapse IS what `--strict-fpc` is for** (`Makefile:19252`), so a
  third-party FPC library is the subject of the flag, not an exception to it.

### What is NOT built

`python-libraries.md` §3 specifies a declarative per-library recipe —
`lib/pyrecipes/<name>.ini`, with `[library]` class/strategy/status,
`[source]`, `[oracle]` (how to run the real library under CPython for
differential testing) and `[surface]` (what a mimic actually implements, *"so
incompleteness is declared rather than discovered at run time"*).

It says **"Proposed shape"**, and `lib/pyrecipes/` does not exist. Measured
2026-09-10: no `.ini` under the repo but `songformatter_settings.ini`, which is
an application's own settings and unrelated.

**So do not cite §3 as a thing to put a file in.** The live mechanism is the
shell-plus-Makefile recipe above. If you need the declarative one, that is a
feature to build, and §3 is already its specification.

## 5. The design north stars, and what each one is for

- **`ir-as-substrate.md`** — push generality down into the IR, keep frontends
  thin. Track A is the one gate and the one multiplier.
- **`the-substrate-is-ast-and-ir-not-the-parser.md`** — the counterweight:
  share the AST and IR, **duplicate the parser and lexer per language.**
- **`normalise-dont-special-case.md`** — when a construct is reachable two
  ways, normalise; the second path is the one that stays broken.
- **`root-cause-over-microfix.md`** — a ticket reports a symptom; 9 times in 10
  the real fix is deeper, and the overhaul is often the *smaller* job.

---

## Known gaps in this document

- ~~Per-library configuration — could not find it.~~ **CLOSED 2026-09-10, see
  §4b.** It exists as a shell+Makefile recipe (synapse is the worked example);
  the declarative `.ini` format in `python-libraries.md` §3 is specified and
  unbuilt. Recording the failure rather than deleting it: I reported "could not
  find" while holding the file that describes it, having stopped one section
  short. **A `grep` that returns prose references is not evidence of absence** —
  it is a hint to read the prose.
- The dual-surface counts in §1 come from a crude heuristic, not a census.
- §2's cross-target rows are measured for i386 and wasm32 only. riscv32 and
  xtensa refuse earlier (`a heap arena needs mmap`), upstream of resolution, so
  they are **unmeasured, not clean.**

## What would make this document stale

Any of the five numbered sections being fixed. §2 in particular describes a bug
as current behaviour — when the p85 ticket lands, that table changes and this
file must change with it. Date your edits and name the measurement.
