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
PXXDBG=a.symptr:p  compiler/pascal26 prog.pas out  # what a pointer DECL recorded
PXXDBG=a.opovl     compiler/pascal26 prog.pas out  # operator lookups + candidates
PXXDBG=a.srcmap:*  compiler/pascal26 prog.pas out  # token->file map + every plant
make pxx-debug && gdb --args compiler/pascal26-debug prog.py /tmp/out
```

The last two answer a question this repo keeps asking in different words: *was
the metadata never populated, or never read?* `a.symptr:<name>` (or `:*`) prints
a pointer variable's recorded depth, pointee and ultimate base — the exact
fields `IsNodePChar` and friends consult, so a shape that lowers wrong tells you
in one run which half is missing. `a.opovl` prints every operator-table query,
each candidate for that operator with its stored right-operand key, and the
answer; "my operator did not fire" otherwise has four indistinguishable causes.
Both were added while chasing a bug whose FIRST fix attempt was written against
an assumed layout, compiled, and changed nothing.

`a.srcmap:*` answers the third variant of the same question: *is the map wrong,
or is the index into it wrong?* It prints the token->file range table (each
range's start, the source lines and text of the tokens on either side of the
boundary, and the path) plus the token index the diagnostic actually asked
about, and a PLANT line for every mark as it is recorded. It exists because
`in: <path>` was naming a 707-line RTL file for an error on line 2074 of a
corpus unit, and from outside there is no way to tell whether the ranges drifted
or the lookup was reading a different token — the first two guesses at the
mechanism were both wrong, and the dump settled it in one run
(`bug-a-a-diagnostic-in-a-used-unit-names-the-wrong-source-file`).

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

## A bisect can name the RIGHT commit and still be wrong

Measured 2026-08-26, on `test-uforth#core` and a NilPy type-name red. Read this
before you trust a bisect result, because the failure is not that the bisect
missed.

`293d70509` genuinely is the commit that changed the behaviour. It is also
**correct**, and reverting it would have been the wrong fix. It removed a
**leak** -- an unmanaged `tyPointer` handed back from a value-position arm and
never released -- and that accidental permanent reference was the only thing
keeping a borrowed closure alive. Deleting a real bug made a second, older real
bug reachable: a use-after-free that had been latent all along.

So the honest sequence is: bisect converges, names a commit, the commit really
did flip the symptom, you revert it, **the crash goes away**, and you record a
fix. You have restored a leak and re-hidden a use-after-free that will resurface
the next time anyone tidies that arm.

**The tell is that the named commit makes things better on inspection.** When a
bisect lands on a change that looks like a cleanup, a leak fix, a lifetime
tightening, or a removal of dead state, do not revert it. Ask what it was
propping up. The question to answer is "what did this change stop compensating
for", not "what did this change break".

What actually found it: `-dPXX_HEAP_DEBUG` put `0xdddddddddddddddd` in `rax` at
an `incq` -- a **retain** of a pointer read from freed memory, which is not a
thing a leak fix can cause and is a thing a borrowed reference can.
`-dPXX_OBJTRACE` then showed the free cascade. Endpoint measurement, not
bisection, is what separated "the compiler changed" from "the RTL changed":
pinned stable ran the repro clean, HEAD did not, and HEAD-compiler-plus-old-RTL
still crashed.

Related, and it compounds: the range that bisect ran over was anchored wrong, so
it had already converged in four steps onto a commit whose entire diff was 250
`prio:` frontmatter lines. A range can exclude the culprit *and* contain
untestable commits, and neither failure announces itself -- see
`normalise-dont-special-case.md` on why the compensating case is the one that
punishes bisection specifically.

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

---

## Assert the INVARIANT, not the current numbers -- and expect it to catch you

Two things happened within an hour on 2026-08-26 that belong together.

**A guard whose first catch is its own author is working.** Track T measured
which test tiers contain pin-built jobs (quick 0, native 0, limited 0, full 191)
so that pins could be scheduled around them, then wrote a devtest asserting it
so the answer could not silently go stale. One hour later, enrolling
`test-fpjson` into `limited` turned that devtest RED, naming the breach exactly:
*"limited now has 1 pin-built job(s) -- a pin taken during one of these runs can
no longer be called safe."* The author broke their own invariant, and the guard
said so before anyone planned a pin around a claim that had stopped being true.

The resolution is the part to copy: **the invariant won, not the coverage.**
`test-fpjson` became full-only rather than the guard being relaxed. "quick,
native and limited are pin-free" is a property other people schedule around, and
a property with an exception is not a property. `full` cycles ~40 minutes, so
nothing was really lost.

**Sufficient is not necessary -- do not assert equality where you mean subset.**
The same guard also asserted that `full`'s pin-built target set EQUALS
`PIN_BUILT_TARGETS`. Wrong direction. Membership in that list is *sufficient*
(it rescues a shell-out recipe like `make demos`, where the pinned path lives one
level down in the Makefile and the recipe body never names it) and never
*necessary* -- a recipe naming the pinned path directly is pin-built whatever its
target is called, which is exactly what `test-fpjson` was before it was listed.
Equality did not encode the rule; it froze an accident of which targets happened
to be enrolled that day. It is a subset check now.

Both are the shape this file keeps returning to: **the system held the right
answer internally and published something that could not express it.** An
equality assertion cannot express "at least these"; a tier count with an
exception cannot express "pin-free".

## The design counterpart: choose an ILLEGAL sentinel, never a plausible one

Everything above is about finding a plausible wrong value after it has travelled.
This is how to stop one being created in the first place, and it is a *design*
rule rather than a debugging one — it is decided when you pick the encoding, and
it is unfixable afterwards.

**The cost of a sentinel is paid entirely at the moment it is wrong.** A
*plausible* marker — 0, empty string, `None` — is indistinguishable from a
legitimate value, so the failure travels arbitrarily far from its cause and
arrives as this file's opening sentence. An *illegal* one collapses that
distance to zero.

Worked example, `PYSIG_DFLT_UNSET` in `compiler/defs.inc`. A NilPy signature
record holds one variant per defaulted parameter, and an unfilled slot needed a
marker. Zero was the obvious choice and would have been wrong: `VT_EMPTY` **is**
`0` and `VT_EMPTY` **is** `None`, so an unfilled slot would have answered `None`
— which is a perfectly ordinary default (`def f(x, lo=None)`). The marker is
`-1`, an illegal variant tag, precisely so "never filled in" cannot be mistaken
for a value.

### The half that makes it more than a convenience

When the slot was later reached, it did not merely fail early — **it detected a
bug nobody was hunting.** The raised error named the parameter, one `PXXDBG`
probe followed, and the cause turned out to be two unrelated parameters in
unrelated defs (`r.s` and `outer.inner.b`) reporting the *same symbol index*,
because a rolled-back trial parse frees an index and a later def's parameter
gets it. That symbol-recycling defect was independent of the feature being
built; a silent `None` would have hidden it along with the first fault, and it
would have surfaced months later in a corpus as a wrong value.

So the argument is not "a loud sentinel is easier to debug". It is:

> **A loud failure is a detector for defects you were not looking for.**

That is what to say when someone proposes a convenient zero. Applies equally to
variant tags, index fields, capacity counts, and any "not set yet" state whose
type has a natural-looking neutral value.

### And a companion trap from the same episode

**Verifying one arity and generalising.** The same callable-value work was
checked against a four-parameter callee and pronounced correct; a two-parameter
one was silently wrong (`map` answered `[1,2,3]` where CPython says `[2,3,4]`).
Boundaries are where these live — check the smallest and the largest case, not a
comfortable middle.
