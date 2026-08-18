# Debugging playbook — which tool, in which order

Start here. The individual tools are documented in
`devdocs/dev/debug-switches.md` (runtime + compiler switches) and
`devdocs/dev/dwarf.md` (gdb). This page is only the decision.

## The rule this is built on

**The expensive bugs in this project do not crash. They produce a plausible
wrong value far from the cause.** Three from one week:

| symptom | what it actually was | cost |
| --- | --- | --- |
| `len(self.evidence)` = `1751084129` | a missing retain; the field pointed at a recycled block | 3 sessions, 2 reverted fixes, a wrong root cause recorded in the ticket |
| correct-looking key analysis, WRONG keys, no error | `not <object>` was always true | found only by diffing one helper against CPython |
| SIGSEGV, no diagnostic | a `{Code,Recv}` pair jumped to as code | the cheap one — a crash has a location |

So: **reach for the tool that makes a wrong VALUE visible, not the one that
makes a crash easier to locate.** A crash was never the expensive case.

## Order

**1. Does it disagree with CPython (NilPy) or gcc/FPC (C/Pascal)?**

```sh
tools/pydiff.py run    prog.py      # NilPy vs CPython: stdout + exit code
tools/pydiff.py bisect prog.py      # names the first diverging statement
tools/pydiff.py probe               # the standing corpus
tools/fpc_diff_probe.sh             # Pascal vs FPC
tools/gcc_diff_probe.sh             # C / crtl vs gcc's libc
tools/gcc_diff_probe.sh --target i386|arm32|aarch64|riscv32   # ...and cross
tools/lib_cross_sweep.sh            # a cross target vs our own x86-64 output
tools/crtl_decl_probe.sh            # is a declared crtl fn IMPLEMENTED, or
                                    # silently binding to libc.so.6?
```

All five, plus the shared traps that make them lie to you, are indexed in
**`devdocs/dev/differential-probes.md`**. Read that before adding cases — the
rules there were each learned by chasing a phantom.

First, always, for a wrong-answer bug. It is the only method that finds a bug
with no crash, no error and confident output. `bisect` keeps every def/class and
varies how many top-level statements run, so it narrows without the truncation
problem.

**2. Is memory being read after it is freed?**

```sh
compiler/pascal26 -dPXX_HEAP_DEBUG prog.py out
```

Freed payloads become `$DD`, held out of the free list. A dangling read then
returns `0xDDDDDDDD` / `-572662307` / `-2459565876494606883` instead of a
recycled neighbour's plausible bytes. Also reports DOUBLE FREE, WRITE AFTER
FREE, and RETAIN/RELEASE of a freed object.

*Tell:* the bug appears only when something churns the heap in between, or
`list(x)` fixes it and `x` does not. That is ownership, not typing.

**3. Who took the reference, and who dropped it?**

```sh
compiler/pascal26 -dPXX_OBJTRACE prog.py out
./out 2>trace.log
grep 0x7fffd7e00018 trace.log       # one object's whole life, in order
```

Use *after* step 2 has told you there IS a use-after-free. Poison says which
read hits it; the trace says which release caused it.

**4. Step through it.**

```sh
compiler/pascal26 -g -O2 prog.py out
gdb ./out
(gdb) source tools/pxx-gdb.py       # Variant decoding + pxxrc
(gdb) break combine
(gdb) pxxrc obj                     # refcount — lives at [inst-16], else invisible
```

`-g -O2` works and is usually right: `-O2` is where the ownership bugs appear.
Works for Pascal, NilPy, C, Rust, Zig, including breakpoints inside imported
`.py` modules and C headers.

**5. Is the COMPILER doing the wrong thing?**

```sh
PXXDBG=help                                    # topics
PXXDBG=n.locals    compiler/pascal26 prog.py out   # inferred local types
PXXDBG=n.ctorargs  compiler/pascal26 prog.py out   # construction arg types
PXXDBG=a.ir:myproc compiler/pascal26 prog.py out   # IR of ONE routine
PXXDBG=a.ast:myproc compiler/pascal26 prog.py out  # its AST before lowering
make pxx-debug && gdb --args compiler/pascal26-debug prog.py /tmp/out
```

No rebuild, no source patch. **This exists because patching a probe in and
self-compiling (~90s) is how a wrong premise got recorded in a ticket** — the
cheap move was to reason instead of measure. Do not reason about what type the
compiler inferred; print it.

## Two traps that produced confident wrong readings

- **Stale binary.** A still-running instance makes the compiler's write a silent
  no-op (ETXTBSY) while still printing `ok:`. `pkill -9` first, or use a fresh
  output name and check it changed.
- **Lost stdout.** SIGTERM discards buffered stdout, so "the marker never fired"
  and "it fired and the output died" look identical. Give tests a clean exit.

## When you are about to conclude something

Check it against a second source before writing it down. Every wrong root cause
in this repo's ticket history was a plausible story that nobody diffed against
an oracle. `pydiff`, gcc, FPC and CPython are all cheaper than a reverted fix.

### When a NEW variable explains everything you have seen, cross it against the old one

Varying what you held fixed is how you find a boundary. Walking that one new
axis is how you write down a rule that fits every observation you have and is
still wrong.

Worked example, `bug-n-from-import-with-an-as-rename-loses-what-it-renames`,
2026-08-18. `from M import X as alias` was misbehaving. Two sessions measured
it, and each produced a table that was accurate and complete for the rows in
it:

| reading | evidence for it | why it was wrong |
| --- | --- | --- |
| "the argument count is the axis" | `alias()` with no arguments crashed; `alias(x)` worked | every working row happened to use a one-character source name |
| "the source name's length is the axis" | `a` worked, `ab`/`abc`/`abcd` crashed; a name sweep agreed | every crashing row happened to be a zero-argument call |

Both rules fit all the data their author had. Crossing the two settled it in
six compiles:

```
name len 12, ZERO args   -> CORE DUMPED     name len  1, ZERO args  -> ok
name len 12, ONE arg     -> ok              name len  6, ONE arg    -> ok
```

The crash needs **both** — zero arguments *and* a source name of two or more
characters. Neither variable alone predicts it, so neither rule was safe to act
on, and the second one had already been written into the ticket as superseding
the first.

**Two symptoms with different boundaries under one construct usually means two
faults.** The same investigation had a second symptom — an omitted default
coming back silently wrong — which was present at *every* name length and so
could not be the length fault at all. A fix aimed at the crash would have
turned the obvious test green and left that one alive. If your two symptoms
disagree about where the boundary is, do not unify them; record both, and say
in the ticket that a fix for one must be re-measured against the other before
it closes.

**And a crossed boundary still is not the mechanism.** The as-rename case above
was resolved by a crossing; a sibling bug found the same evening was not. That
one's boundary — "subscripting a container LITERAL inside a function crashes,
binding it to a local first does not" — held on every row of a four-axis
crossing, and the subscript turned out to be innocent: the fault was RETURNING
anything derived from a literal, including a method call with no subscript in
it, and the boundary looked like subscripts only because the rule that would
have saved it lived in a path keyed to a non-literal receiver. So a crossing
tells you where the behaviour changes, which is what you need to hand someone a
repro — it does not tell you why, and a rule that fits every row you have can
still be naming a correlate of the real path. Write the boundary into the
ticket as a boundary, not as a cause, and say which one you are claiming.

The corollary, since it is what actually caught this: **two sessions measuring
the same bug and disagreeing is a signal, not a nuisance.** Four confounded
readings were resolved that way in one day — including one where the correction
to a confound was itself confounded. Deferring to whoever measured last would
have given the wrong answer three of those four times.
