---
track: N
prio: 30
type: feature
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
