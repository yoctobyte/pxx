---
track: N
prio: 72
type: feature
status: done
---

# Measured stdlib coverage: json and re are solid; os, time and math.fabs are absent

A sweep of the modules a small script typically reaches for, each a handful of
representative calls, diffed against CPython:

| module | result |
| --- | --- |
| `json` | **exact** — `dumps` of a dict, `loads` and subscript |
| `re` | **exact** — `match` with groups, `sub` with a class |
| `math` | `sqrt`, `floor`, `ceil`, `pi` fine; **`fabs` undefined** |
| `os` | **`undefined variable (os)`** — no `os.path.basename`, no `os.path.exists` |
| `time` | **`no overload of time matches these arguments`** — `time.time()` |
| file I/O | `open(...)` binds something typed TPyList, so `.read()` fails with `TPyList has no method read` — the known [[feature-nilpy-file-io-and-comprehensions]] |

json and re being exact is the notable half: those are the two hardest to fake
and the two most likely to appear in a real script.

The gaps are all compile-time, so nothing computes a wrong answer. Priority is
low deliberately — the fix is per-function plumbing with no design content, and
`os.path` is the only one with real surface area. `math.fabs` is one line
(`abs` on a double).

One thing worth checking while doing this: `open()` binding to TPyList suggests
the name resolves to something unrelated rather than being absent, which is the
shape [[bug-nilpy-stdlib-name-binds-pascal-unit]] describes.

## Partially fixed (this session)

`math.fabs` and `os.path.basename`: both added to `PyStdlibCallProc`'s
dotted-name table (pyparser.inc), pointing to new `pymath_fabs`/
`pyos_path_basename` in pylib.pas — the same one-line-per-name shape
`os.path.dirname` etc. already use. Note that `os.path.exists` was ALREADY
in the table and already worked — re-measuring found the original repro's
"undefined variable (os)" was actually `os.path.basename` failing first
inside the same statement, not `os` itself being unbound; the table just
had a gap for that one name.

`time.time()` NOT fixed: `time` collides with `sysutils.Time` (a Pascal
`TDateTime`-returning RTL function, wrong shape for Python's Unix-epoch
float) — same wrong-target problem `math.floor`/`math.ceil` had — but
unlike those two, there is no existing epoch-seconds syscall wrapper
anywhere in this codebase to point `time.time` at (checked: no
`gettimeofday`/`clock_gettime` call site exists). Needs real per-arch
syscall plumbing (the same shape `pyos_path_exists`'s own comment
describes for `access`/`faccessat`), which is a different-sized task than
the other two names in this ticket — left open rather than folded in.

`open()`/file-I/O binding to TPyList: not investigated this pass: tracks
with the separate `feature-nilpy-file-io-and-comprehensions` ticket already
referenced above.

## Gate

`make test-nilpy` + self-host byte-identical, plus the table above.

## 2026-08-09 — four more os.path names, and what the syscall ones need

Added, each the same one-line-per-name shape the ticket describes, pinned by
`test/test_nilpy_os_path_more.{npy,expected}` (`.expected` from CPython):

| name | note |
| --- | --- |
| `os.path.split` | the (head, tail) TUPLE; its edges are a trailing slash and a bare name, neither of which falls out of dirname/basename by accident |
| `os.path.normpath` | the one with real content — '..' popping, '..' past the ROOT staying at the root, a LEADING '..' in a relative path that cannot be collapsed without the cwd, repeated slashes, and '' answering '.' |
| `os.path.getsize` | via `pyos_stat`, so a missing path RAISES rather than answering 0 |
| `os.path.expanduser` | `~` and `~/...` from $HOME; `~user` returned unchanged, as CPython does when it cannot resolve |

### Still missing, and why they are not one-liners

`os.makedirs`, `os.listdir` and `os.rmdir` came out of the same sweep and are a
different job: **there is no `mkdir`, `rmdir` or `getdents` entry in the PAL**
(`compiler/builtin/pypal.pas` has open/read/write/close/lseek/ftruncate/unlink/
rename/getcwd/stat/access/poll and nothing else). So each needs a new PAL
syscall first, and `listdir` additionally needs the `getdents64` buffer walk
rather than a single call.

And the PAL is **per-target**: `pypal.pas` carries a separate syscall-number
const block for x86-64, i386, aarch64, arm32, riscv32 and xtensa, each with its
own numbering and its own `NR_* = -1` holes. So "add mkdir" is six const blocks
plus the routine, not one line — which is the real reason these three are a job
rather than plumbing, and why they were left when the four pure `os.path` names
above were added.

Worth doing together, and worth checking the ESP platform arm at the same time
— `devdocs/dev` records that ESP refuses a batch of POSIX entry points
deliberately, and directory enumeration is likely one of them.

### Also still missing from the same sweep
`os.sep` and `os.linesep` — ATTRIBUTES rather than calls, so they need a
different hook from the dotted-call table this ticket has been extending.

## 2026-08-09 (later) — three container names, from a dict/set sweep

`set.symmetric_difference`, `set.isdisjoint` and the TWO-ARGUMENT
`dict.fromkeys(seq, value)`. Pinned by
`test/test_nilpy_set_dict_gaps.{npy,expected}`.

The first two were thin over operator forms that already existed (`pyset_xor`,
`pyset_and`), so the gap was the METHOD name, not the algorithm.

`fromkeys(seq, value)` is a genuine Pascal **overload**, reached because
`PyParseStdlibCall` re-targets by ARITY via `FindProcArity` — the route that
site's own comment recommends ("declare a 3-argument overload like any Pascal
routine"). Worth knowing for the next shim: arity is reachable that way, TYPE
still is not.

### Verified working in the same sweep — do not re-file

`dict` keys/values/items/get with and without a default/pop/setdefault/update/
popitem/`in`/`not in`/`len`/`clear`/dict(d) copy/`{**a, **b}` merge; `set`
union/intersection/difference/add/discard/remove/issubset/issuperset/`len`/set
comprehension/`set(s1)` copy. 17 lines, all byte-identical to CPython.

## 2026-08-15 — re-swept, name by name. Most of the table above is now DONE

The 2026-08-15 sweep ran one name per program against CPython, rather than a
handful of representative calls. `os`, `time` and `math.fabs` — the three
"absent" rows above — are all present and exact now. What remains is a much
shorter list, and every entry still fails LOUDLY:

| module | absent |
| --- | --- |
| `re` | `split`, `subn`, `finditer` (`match`, `fullmatch`, `search`, `findall`, `sub`, `compile`, `escape`, the `I`/`IGNORECASE` flag all agree) |
| `os` | `sep`, `linesep`, `listdir` (`path.join/basename/dirname/splitext/exists/isdir/abspath`, `getcwd`, `environ.get` all agree) |
| `sys` | `maxsize`, `version`, `byteorder` — these do not fail at compile: they raise pxx's own explanatory "this build has no sys.X" exception, which is a designed refusal, not a gap to plug blindly |
| `math` | twelve names, split by whether they are exact or transcendental — measured separately in [[feature-nilpy-math-module-twelve-absent-names-measured]] |

`json` re-verified exact, including `dumps` of nested containers, `sort_keys=`,
and `loads` of every scalar type.

`re.split` is the one worth doing first: it is how a script tokenises a line,
and it is the only absent name here that a small program is likely to reach for
before anything else on the list.

## Re-measured 2026-08-16 (a later sweep, same method)

`import copy` is the one new absence found by a broad builtin/stdlib sweep:
`import: no unit named copy and no shim mimic_copy`. Everything else the sweep
touched — dict/set/list/str methods, slicing (including negative and strided),
`%` and `str.format` and f-string mini-languages, `divmod`/`round`/`int(s, base)`,
comprehensions of all four kinds, closures with `nonlocal`/`global`, `*args`/
`**kw` definitions, dunder-driven classes (`__repr__`/`__eq__`/`__lt__`/`__add__`/
`__len__`/`__iter__`/`__contains__`/`__getitem__`), inheritance with `super()`,
`try/except/finally` including `return`-through-`finally` and nested re-raise,
`while/for ... else`, and bytes — **matched CPython exactly**.

`copy.copy` / `copy.deepcopy` is the whole surface worth having: a shallow copy
is the slice/`dict(d)` that already works, so the module is mostly a naming
shim, and `deepcopy` is the one that needs a real recursive walk over the
variant container tags.

## 2026-08-29 — re.split/subn/finditer done, and a count that meant its opposite

Re-measured every row before touching anything, because a ranked queue says a
ticket is unblocked, not that it still has work in it. **The 2026-08-15 sweep
above was wrong on two of its three "now present" claims:**

| 2026-08-15 said | actually, at HEAD |
| --- | --- |
| `os` present and exact | `os.path.*` yes; `os.sep` / `os.linesep` / `os.listdir` still `undefined variable (os)` |
| `time` present and exact | `time.time()` still `no overload of time matches these arguments` |
| `math.fabs` present | correct |

New since that sweep: `copy.copy` works now, `copy.deepcopy` does not.

### Done here

`re.split`, `re.subn`, `re.finditer` — all in `lib/rtl/re.pas`, no frontend
change. 22 lines byte-identical to CPython, pinned by
`test/test_nilpy_re_split_subn_finditer.{npy,expected}`.

**And a real bug found on the way, which is the part worth reading.** CPython's
count/maxsplit convention is not the engine's, and they disagree on exactly one
input:

    CPython:    0 = no limit,   NEGATIVE = do nothing
    ReReplace: -1 = no limit,   every negative reads as "no limit"

`sub` mapped 0 -> -1 and passed a negative straight through, so a count meaning
"replace nothing" replaced everything:

    re.sub("a", "X", "banana", -1)    pxx: bXnXnX    CPython: banana

A wrong VALUE with no error, present since the module landed — the silent-wrong
kind, not the compile-time kind this ticket's own summary says these gaps all
are. Normalised once in `ReLimit()`; split and subn use it too.

`split` is not a scan, and the cases that make it not one are all pinned: groups
interleave into the RESULT; a non-participating group is `None` and not `''`
(ReGroup answers `''` for both, so the start sentinel is read directly); an
empty match still splits; the tail piece exists even when empty.

`m.end()` — CPython's spelling — added as `&end`, an escaped identifier the
dialect already supports. Working CPython code says `m.end()`, so its absence
was an upward-compat gap. Rejected the alternative of mapping `end` -> `stop` in
`PyMethodName`: that is a global rename and would hit every user class with an
ordinary method called `end`.

Two divergences recorded in `devdocs/dev/nilpy-semantics-divergences.md` rather
than filed as defects: `finditer` answers a list where CPython answers a lazy
iterator (identical for `for`/`list()`, `len()` works here and raises there —
the accepting-more direction), and `m.end`/`m.stop` being one method with two
names.

### Still open in this ticket, measured at HEAD

| name | why it is not a one-liner |
| --- | --- |
| `os.sep`, `os.linesep` | ATTRIBUTES, not calls — the dotted table only intercepts call forms, which is why the error is `undefined variable (os)` rather than a missing member. Needs the hook `sys.X` already has (it reaches a runtime module object and raises AttributeError, so the mechanism exists). |
| `os.listdir` | needs `getdents64` in the PAL, per-target, plus the buffer walk — the job described under "Still missing" above, unchanged |
| `time.time()` | needs `clock_gettime`/`gettimeofday` in the PAL, per-target; and `time` collides with sysutils' `TDateTime`-returning `Time` |
| `copy.deepcopy` | a recursive walk over the variant container tags; `copy.copy` now works |
| `re` | nothing left — `split`/`subn`/`finditer` were the last three |

The `os.sep` route is the cheapest of these and is the one I would take next:
the `sys` module already resolves attributes at runtime, so it is wiring an
existing mechanism rather than adding a syscall to six const blocks.

## 2026-08-29 (later) — time.time() and os.listdir() done; the ticket is closed

Both needed a PAL syscall rather than a shim, which is what had kept them open.
`compiler/builtin/pypal.pas` gained `NR_CLOCK_GETTIME` and `NR_GETDENTS64`
across its six blocks, plus `PyPalClockRealtime` / `PyPalGetdents` /
`PyPalHasGetdents`.

**Which targets were actually executed: x86-64 only.** i386, aarch64 and
riscv32 are header-transcribed and NOT run. arm32's `getdents64` is not filled
at all. That distinction is recorded in the table's own comment, not just here,
because a wrong syscall number is invisible on five of six targets.

Numbers were read one arch at a time from this machine's kernel headers, never
derived from a sibling — i386 and arm32 sit +27 apart for five syscalls in this
table and **220 vs 217** for `getdents64`, so the offset that looks like a rule
is not one.

The 32-bit targets use `clock_gettime64` (403) rather than the legacy
`clock_gettime`, because **riscv32 does not have the legacy one**
(`asm-generic/unistd.h` gates `__NR_clock_gettime 113` on
`__ARCH_WANT_TIME32_SYSCALLS || __BITS_PER_LONG != 32`, and riscv32 defines
neither) — and because it makes `TPyPalTimespec` one layout on every target and
y2038-clean.

`import time` resolves the NAME to the C header, so `time.time()` was binding
to C's `time(2)` — the same wrong-target shape as `math.floor`, intercepted the
same way.

### The final state of this ticket's table

| name | state |
| --- | --- |
| `re.split` / `subn` / `finditer` | **done** — and `m.end()` with them |
| `os.sep` / `os.linesep` | **done** |
| `os.listdir` | **done**, except arm32 → [[bug-n-pypal-arm32-getdents64-is-unfilled]] |
| `time.time()` | **done** |
| `copy.copy` | already worked by the time it was re-measured |
| `copy.deepcopy` | **not done, deliberately** → [[decide-nilpy-deepcopy-over-the-container-subset]]; the module documents it as absent ON PURPOSE and the owner decides |
| `sys.maxsize` / `version` / `byteorder` | designed refusal, unchanged — not a gap to plug blindly |
| `math`, twelve names | never this ticket's → [[feature-nilpy-math-module-twelve-absent-names-measured]] |

### Filed rather than folded in

- [[bug-n-a-module-alias-does-not-resolve-for-attribute-lookup]] — `import sys
  as s; s.platform` does not compile. Pre-existing, verified as such.
- [[bug-n-pypal-arm32-getdents64-is-unfilled]] — the deliberate hole above.
- [[bug-n-pypal-ppoll-passes-a-64-bit-timespec-on-32-bit-targets]] —
  pre-existing, exposed by reusing `TPyPalTimespec`: one struct that is right
  for the clock on every target and wrong for ppoll on the 32-bit ones.

### Two things worth carrying elsewhere

- **`make compiler/pascal26` does not compile `pylib.pas`.** It is linked into
  NilPy programs, not into the compiler, so a broken interface section there
  passes the entire self-host fixedpoint and surfaces only when a `.npy` is
  compiled. The gate is real; its scope is narrower than it looks.
- **`PyStdlibCallAhead`'s base whitelist and `PyStdlibCallProc`'s table are one
  concept in two places.** `time.time` sat in the table doing nothing until
  `time` was added to the whitelist. Now commented at the whitelist.

Closing: every name in this ticket is either done, filed as its own ticket, or
an owner decision. Nothing is left here that a next session could pick up.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.
