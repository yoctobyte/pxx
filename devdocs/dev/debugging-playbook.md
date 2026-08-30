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

## If you can name the hot spot without measuring, that is evidence it is not the hot spot

Three times in one day, in three domains sharing nothing — matrix composition,
devtest attribution, compiler hot path — a careful person named the obvious
candidate and was wrong, and the real answer fell out of a measurement in under
an hour:

- The matrix looked like it was made of Pascal micro-tests (44% of jobs). They
  are 7.4% of the time. **70% is one target**, and the tax is not part of a NilPy
  job — a zero-byte `.npy` costs nearly what a 288-line test costs.
- A flaky devtest file "obviously" flaked in the three cases whose notes said
  *measured on the 12-core xeon*. Those feed frozen literals and measure nothing.
  The offender was a fourth case that **passed**.
- A compiler slow at compiling looked like a register-allocation problem. **56%
  of a one-line NilPy compile was in the first 5 KB of `.text`** — runtime blobs
  and the builtin heap — with 8.7% in two `idiv`s dividing by the literal 8.

The mechanism is not that intuition is bad. It is that **the obvious candidate is
the one everyone has already optimised**, so the surviving cost is *definitionally*
in the place nobody looked. Which sharpens "measure first" into something you can
act on directly: **your ability to name a hot spot without measuring is itself
evidence that it was named — and therefore fixed — before you got there.**

## Find your section

The sections below accumulated in the order they were learned, which is the wrong
order to read them in. Route by what you are holding:

**You have a failing thing and want the tool**
- `## Order` -- the tool per question, and the reason to reach for one at all
- `## Order` item **6** -- *it faulted on a cross target and I have only an
  address*: `-strace` for the `si_code`, `-d in_asm` for the block, `--debug` to
  name the routine, and where the cross binutils actually live
- ``## `perf` being blocked is not "no profiler"`` -- FPC `-pg` + gprof, read call
  counts not percentages
- ``## Profile the SHIPPING binary`` -- and `tools/pxxprof`, for when `perf` and
  gdb-attach are both refused

**A measurement or a verdict is telling you something and you are about to believe it**
- ``## Profile the SHIPPING binary`` -- `-g` alone silently means `-O0`, so
  `make pxx-debug` profiles a different program and says nothing about it
- `## Two traps that produced confident wrong readings`
- `## A bisect can name the RIGHT commit and still be wrong` -- the tell is that
  the named commit looks like an improvement
- `## A number moving in the direction you hoped is not a check` -- the
  confirmation may be the symptom
- ``## "The compiler couldn't compile X" and "the language can't do X" look
  identical from inside `compiler/**` `` -- an "undefined" error in a
  compiler-internal file may be a define at the top of the translation unit,
  not a gap; compile it standalone before filing
- ``## "The pinned binary reproduces it" may be a claim about a MIXED compiler``
- `## A silent assertion makes the harness report something else, confidently`
- `## When you are about to conclude something`

**A check exists, passes, and you are trusting it**
- `## Assert the INVARIANT, not the current numbers` -- and assert the
  CONSEQUENCE, not the number
- `## A guard that greps the source can only catch what is visible in the text`
- ``## "Ruled out" and "could not look" must never print the same`` -- the
  strongest instance of the asserts-nothing family, plus close conditions about
  the wrong subject and diffs against a missing operand
- `## A correct fix on an opportunistic path is inert` -- the tests answer *does
  it work*, never *does it run*

**You are about to write the fix**
- `## A blocklist costs one outage per symptom; an allowlist closes the class`
  -- and key an exemption on what a thing DECLARES, not what it appears to BE
- `## A one-way repair flag defeats the mechanism that would have corrected it`
  -- store a rule version, re-derive from bounds, never filter in place
- `## The design counterpart: choose an ILLEGAL sentinel, never a plausible one`

**You are reading a ticket, or writing one**
- ``## A ticket's prescription is a hypothesis, and it can rule out the answer``
  -- when a fix does not take, re-read what the ticket EXCLUDED
- `## A comment is an unverified claim, and tickets inherit it`
- `## Record the negative result` -- and record the option you measured and
  declined, with its number

Its sibling `normalise-dont-special-case.md` carries the structural half: why the
second path is the broken one, and why a special case gets the careful wording
while the general case keeps the words from before anyone knew.

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
PXXDBG=a.poisonslot compiler/pascal26 -O3 prog.pas out # does ANYTHING still read that slot?
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

`a.poisonslot` answers a DIFFERENT shape of question, and it is the one to reach
for when the blocker is an audit rather than a bug: *does anything still read X?*

At `-O3` a register-resident local is dual-written — register and frame slot
both current — and the optimisation that stops writing the slot is safe only if
nothing reads it. The readers you can find by grep are easy; the question that
stops you is whether some direct `[rbp+off]` emit, somewhere in 10k lines, still
does. **That is an audit with no completion criterion: unanswerable by grep,
unfalsifiable by reading, and normally the point where the work gets parked.**

The probe converts it into one experiment. It fills the slot with `$5EEDADAD`
immediately after each dual-write, so a surviving reader returns *garbage*
instead of a plausible value:

> **A stale slot and a correct slot are indistinguishable. A poisoned one is
> not.**

Same trick as `-dPXX_HEAP_DEBUG`'s `$DD` fill, one level up — and it works for
the same reason. Run the corpus under it and any reader announces itself.

Measured on the run it was built for: **2 of 19 programs changed behaviour, and
both were the ones with `try`/`except` in a loop** — one hung, the other printed
`1592634797` (`$5EEDADAD`) straight back. The culprit was the exception landing
pad, which re-syncs residents *from* the slot and so is the one reader residency
cannot see through. No amount of careful reading had found it; the probe found
it in one run, and the resulting gate (`RcProcHasExc`) is what made the
optimisation land.

**The rule that makes it evidence rather than decoration: a poison probe must
call the SAME predicate as the change it is testing** — `PoisonResidentSlot`
calls `ResidentSlotIsDead`, the function the optimisation itself gates on. Copy
the condition instead and you poison a *neighbouring* set, so a green result is
evidence about something you are not shipping. This is the whole reason the
result can be trusted.

Two things it does NOT tell you, which matter as much as what it does:

- **It writes exactly `TypeSize` bytes.** A wider store would corrupt the
  neighbouring slot and manufacture the bug it is hunting.
- **It covers only what it poisons.** It fills GPR residents; float residents
  (xmm8/xmm9) were never poisoned, so nothing is known about them and their
  dual-write stayed. *Not covered is not the same as fine* — a null result is
  only worth what the probe's reach is worth, so state the reach whenever you
  report one.

Generalise the shape, not the flag: when you are blocked on "is there a reader /
writer / caller I have not found", **poison the thing rather than auditing for
its users**, and make the poison match the change's own predicate.

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

**6. It faulted on a CROSS target and all you have is an address.**

```sh
tools/run_target.sh <arch> ./prog                  # the plain run
qemu-<arch> -strace ./prog                         # WHY it died, and where
qemu-<arch> -d in_asm -D /tmp/asm.log ./prog       # the block it died in
qemu-<arch> -d cpu    -D /tmp/cpu.log ./prog       # register state
compiler/pascal26 --debug ... 2>&1 | grep '^proc'  # "proc N: NAME at OFFSET"
```

New in 2026-08-30, because until then no xtensa binary could be executed at all
and "it faulted" was not a shape this repo had. Take them in that order — the
first line usually ends it:

- **`-strace` first, always.** It prints the syscalls, then the signal *with its
  `si_code` and address*. `SIGBUS si_code=1` is `BUS_ADRALN` and the address
  will be odd — which converts *"a wild pointer somewhere"* into *"a misaligned
  one, go look at the frame"*, and those are different searches. A wild pointer
  sends you hunting ownership; a misaligned one sends you to the frame layout,
  where the bug actually was
  ([[bug-a-a-hidden-aggregate-result-temp-gets-an-unaligned-frame-slot]]).
- **`-d in_asm` names the block**, and its last instruction is the faulting one.
  `-d cpu` gives the registers, but read it knowing the dump is at the last
  *exception*, which for a normal syscall is the syscall itself — a register
  there is not necessarily the register at the fault.
- **`--debug` maps an address to a routine.** It prints `proc N: NAME at
  OFFSET`, and the base is the ELF **entry point**, not the load address (our
  images have no section headers, so nothing else will tell you). Without this
  you are staring at a hex address with no name.
- **Then, and only then, a probe** in the backend's own emitter to print the
  offending symbol. That is what turned "an odd offset" into eight named slots.

**The cross toolchains are installed and are not on `PATH`.** ESP-IDF puts
`xtensa-esp-elf-objdump`, `xtensa-esp-elf-gdb` and the riscv32 pair under
`~/.espressif/tools/**`, reachable only after `. $IDF_PATH/export.sh`. A bare
`command -v xtensa-esp-elf-objdump` in a fresh shell answers about the SHELL and
reads exactly like the tool being absent — this cost the fleet five weeks on the
QEMU emulators and cost one session a weaker verification the same night, in the
same directory tree. **A stated absence about this box is a claim about a
search, not about the box**; before concluding a capability is missing, grep the
repo for something that already uses it (`tools/esp_run.sh` had been globbing
that directory for four weeks).

Our ELFs carry program headers only, so disassemble the raw image:

```sh
OD=$(ls ~/.espressif/tools/xtensa-esp-elf/*/xtensa-esp-elf/bin/xtensa-esp-elf-objdump|head -1)
$OD -D -b binary -m xtensa --adjust-vma=0x08048000 \
    --start-address=0x... --stop-address=0x... ./prog
```

Two cautions worth the lines. **Objdump desyncs on the inline literal pools**
xtensa emits mid-code (a `j` hops over each one), so anchor `--start-address` on
a known instruction boundary — a proc start from `--debug` — and treat
`excw` / stray `.byte` runs as the tell that you have drifted. And **the
strongest evidence is two backends, not one**: the same source compiled for
xtensa and riscv32, disassembled with each toolchain, showed *identical* frame
offsets, which is what proved a suspected xtensa codegen bug was shared layout
that five backends simply never trap. One backend's disassembly could not have
said that.

## Two traps that produced confident wrong readings

- **Stale binary.** A still-running instance makes the compiler's write a silent
  no-op (ETXTBSY) while still printing `ok:`. **Use a fresh output name and check
  it changed** — that is the whole fix, it needs no signal at all, and it cannot
  hurt anybody else. If you genuinely must kill the running copy, kill **the pid
  you started** (`$!`, or `setsid` and kill the group), never a name pattern:
  `pkill -f <tool>` asks *"is there a process whose command line contains this
  text?"* when your question is *"is there a process **I** started?"*. Those
  coincide exactly while one agent runs the tool and diverge silently the moment
  two do — and several agents share this box. `tools/gui_shot.sh:52` carries the
  same rule, learned when one agent's pattern-kill took down another's live Xvfb
  mid-capture; a `pgrep` waiter has the mirror-image bug, because it matches
  *itself* and never returns.
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

## A one-way repair flag defeats the mechanism that would have corrected it

Track T stored "this regression has been repaired" as a **boolean**. So
*already repaired* was indistinguishable from *repaired under a rule we have
since corrected* -- and the first rule was wrong, in the too-narrow direction. A
range narrowed by the bad rule could never be re-widened. **The fix for a wrong
rule had installed a flag saying do not revisit.**

The shape is worth recognising anywhere state records that work was done:

- **Store a rule VERSION, not a done bit.** Bump the constant and everything
  re-derives on the next pass.
- **Re-derive from the bounds; never filter the stored result in place.**
  Filtering in place is one-way by construction -- information leaves and cannot
  come back. Re-deriving from `good`/`bad` is idempotent and correctable in *both*
  directions, and here it cost no extra storage, because the bounds were already
  in the state file.

A repair that cannot be repaired is the corrective mechanism eating itself, and
it is invisible while the rule happens to be right.

The sharpened rule, after the same author caught a weaker instance in their next
commit -- a value stamped behind an existence check, write-once, whose answer
depended on a prefix list that can change: **cache a fact about a frozen
artifact, never a fact derived through a rule that can change.** A completed
run's `timed_out`, a build's `pin_built` -- immutable, safe to persist forever. A
verdict computed *through* a policy is a one-way cache wearing different clothes,
and recomputing it is almost always cheaper than the machinery that would make it
correctable. An audit on that criterion found every other persisted boolean in
the file was a fact about a run, and clean.

Its complement, for the other direction: **persist for the published artifact,
derive for the live reader.** A reader that waits on a writer-side field is inert
until the writer next happens to run -- so a status command that reads a stamp
shows a human nothing until the daemon's idle repair fires, while one that
re-derives (one `git diff-tree`, falling back to the stamp) answers tonight. The
cache rule says what is safe to freeze; this says who should be freezing it.

And a corollary from the same fix: **a distinction that is not recorded in the
history decays after one iteration.** Marking the current run torn-down while the
history rows stay unmarked buys exactly one cycle, until the pointer moves past
that sha. A fix that expires is not a fix.

## A property that holds for the wrong reason will stop holding silently

Track T set a new job's class to `selfhost` for its 600s timeout, then found it
was **already** classed that way -- but only because `classify()` matches on the
expanded `make -n` text, and the `$(COMPILER)` prerequisite expands to text
naming `compiler.pas`. The class was right by accident of a prerequisite, not by
anything about the job. A comment had been written asserting the opposite.

This is the quiet cousin of every defect in this file. Nothing is failing;
something is **passing through a path nobody chose**, and the day that
prerequisite is refactored the timeout silently drops to the default and a
600-second job starts getting killed -- with no change to the job, no change to
the class, and no diff to blame.

- **When you find a property already true, ask WHY before being pleased.** "It
  already works" and "it works for the reason I would have chosen" are different
  facts, and only the second survives someone else's refactor.
- **Then make it true on purpose.** They changed `classify()` to match
  `selfcompile` directly, so the class no longer depends on how a prerequisite
  happens to expand. Same cost, and now the reason is the one written down.
- **Correct the comment that asserted the other thing.** This one had been wrong
  from the start and nothing had ever contradicted it.

## A guard that greps the source can only catch what is visible in the text

Same session, second defect. A repair path called `testable_only()`, which reads
like a module helper and is in fact a **closure nested inside another function**.
It parsed. It read correctly. And it **passed the devtest written for it** --
because that guard grepped the source for the call. The guard asserted the call
existed; the call existed; the call was wrong. It would have raised `NameError`
the first time an idle cycle reached that branch, hours later, in a process
nobody watches.

This is the same failure as the `137 -> 2` measurement above: **a check that
runs, passes, and asserts nothing about the thing at issue.**

A third costume, since it recurs: **a close condition about the wrong subject.**
The breadth ticket above closed on `carried_runs != 0` -- satisfied from the day
the mechanism shipped, so it would have closed the ticket **six days early, on a
mechanism recovering 0.33% of what it saves, in the middle of a 40-hour breadth
gap.** `resume_health()`'s own docstring stated the right standard -- *"One line
of RATES, not events"* -- and the ticket closed on an event anyway. **The
instrument that answers "is breadth starved" is breadth staleness**, and nothing
else. Write close conditions on the symptom the ticket is about, not on the
mechanism you happened to build.

The sharpest instance of the family is worth stating on its own, because it is
the one that hides best: **the run that proved the least was the one that most
effectively silenced the request for more.** Staleness asked *is there a record
for this sha?* -- and a torn-down run leaves a record. A timed-out run is the
weakest possible evidence about a sha and was being counted as the strongest,
purely because its artifact is shaped like a completed one. Whenever a check asks
whether an artifact EXISTS, ask what the artifact looks like when the work
failed. Text-shaped guards
are especially prone to it, because writing one feels like verification and the
grep is trivially satisfiable by the broken code.

Three separate text-shaped guards failed this way in one night, which is enough
to call it: **a grep-guard is the weakest guard shape available.** One asserted a
call existed when the call was a scoping error; one matched a name form the
consumer never keys by; and one -- nearly a joke, and the clearest possible
demonstration -- **went red on its first run against the comment explaining the
rule it checks**, because the author had written the forbidden string three lines
above while saying why it was forbidden. A grep reads prose as eagerly as code.
Prefer a guard that executes the path. Where only text will do, strip comments
and match on the form the CONSUMER uses, not the form that reads naturally.

A related recurrence worth naming: the same fix nearly died twice on **coarse
predicate where a precise one exists** -- `target in PIN_BUILT_TARGETS` (a list
that is sufficient, never necessary) standing in for `j.pin_built` (the measured
fact). Same author, same file, same pair of predicates, twelve hours after the
first instance. A wrong distinction does not get learned once; it gets learned
per call site. When you correct one, grep for the predicate, not for the bug.

It was found by running the path end to end against a live case rather than
trusting that it looked right.

The response was a **narrow** checker rather than a linter (`tools/tools_scope_devtest.py`;
there is no pyflakes/flake8/ruff on these boxes). It reports exactly one class:
*a name LOADED where it is not in scope but BOUND somewhere else in the same
file*. That pairing is what keeps it near false-positive-free -- an unbound name
has a dozen innocent explanations, but a name bound in a **sibling function** and
read here is almost never anything else, and it is precisely what a 5,000-line
file of nested helpers invites. Verified by re-injecting the real defect, not a
synthetic one.

Deliberately not general, for the reason this file keeps arriving at: **a checker
that reports everything gets suppressed, and a suppressed checker asserts
nothing.**

## A ticket's prescription is a hypothesis, and it can rule out the answer

Stronger than "distrust the ticket's where-to-look", and more expensive: a ticket
can name the fix that works and **explicitly exclude it**.

`bug-t-the-push-rate-starves-breadth-coverage-entirely` summarised itself as
*"Fix is resumability plus bounding consecutive idle, NOT reserving a slot."*
The dates say the opposite and they are not close. The two prescribed shapes
landed 2026-08-19, after which full-to-full gaps went 12.8h, 9.4h, 21.6h, 19.2h,
31.5h, **40.1h**. The ruled-out shape -- breadth reserves a slot when stale --
landed 2026-08-25, and the next three gaps were **1.1h, 3.1h, 1.3h**. Median
full-to-full over the following 24h: **1.3h**, from 3,828 run records.

Six days of degradation after the prescribed fix; recovery within the hour of the
excluded one.

- **A prescription in a ticket carries the confidence of a decision and the
  evidence of a guess.** It was written before the work, by someone reasoning
  about a system they had not yet measured, and then it sits there in the
  imperative for months looking settled.
- **This is a triage hazard, not just an engineering one.** The prio and the plan
  both inherit the wrong frame, so a ticket can be correctly ranked for work that
  cannot fix it.
- **When a fix does not take, re-read what the ticket ruled out.** That set was
  never tested; it was reasoned. It is the cheapest unexplored space available.

**State the confound rather than let someone find it.** Here, 08-20 is when this
box became a shared workstation, so load rose almost exactly when the prescribed
shapes landed -- the fair reading is that they were not harmful but insufficient.
That does not rescue the headline, because *the confound never went away*: still
a shared workstation, still throttled, same push cadence. **Load held constant,
mechanism changed, outcome changed** -- as close to a controlled comparison as a
live box will give, and worth saying in exactly that form.

### And a structural ceiling, recorded so nobody tries to raise it

The resume ledger reused **73 of 22,280 saved job-results, 0.33%**, and
`superseded: 70` is the whole explanation. A partial is keyed on `(sha, tier)`,
and on abort the watcher re-targets to the new HEAD -- so the partial it just
saved is for a sha nobody will ask about again. **Resumability can only pay where
the same `(sha, tier)` is retried, and a push-driven ladder almost never retries
one.** That is a ceiling, not a defect. It does pay for the one phase that does
retry a single sha -- pin verify, where the log shows 56 jobs already decided
against that exact binary.

## A correct fix on an opportunistic path is inert, and nothing reports it

The runtime twin of every routing defect in this file, and the one that hides
best, because **the code is present, the tests pass, and the output stays wrong.**

`repair_regressions` was correct. It lived inside `bisect_step`, which is the last
arm of an elif chain of idle phases -- pin verify, breadth backfill, opt, bench,
then bisect -- so it ran only once every earlier phase had declined. Pin verify
alone was preempted by a push three times in one hour, and idle work on this box
has been starved for 40 hours at a stretch. **A correction to what the board
publishes was gated behind the busiest lock in the system.** A dry run found
three repairs that had never reached the published board, two of them written
hours earlier: 99 untestable commits still in one range, and a red still
attributed to a commit that could not have caused it.

The generalisation: **it is not enough for the right answer to exist and be
correct; it has to be on a path that runs when the answer is needed.**

- **The tell is a trigger that is a PHASE rather than an EVENT.** "Runs during
  idle", "runs after the queue drains", "runs on the next full pass" -- each
  inherits the availability of something unrelated to the thing it fixes.
- **Correctness tests cannot see this.** They call the function directly, so they
  answer *does it work*, never *does it run*. A guard that exercises the caller's
  scheduling is a different test and usually does not exist.
- **The honest status of such a fix is "fixed in the code, inert in this
  configuration"** -- not "fixed". Say it that way; a count of closed tickets that
  includes inert ones is worth less than a smaller honest count.
- **Make the repair idempotent and call it unconditionally.** It now runs every
  cycle before any phase decision, costing one `diff-tree` and one `rev-list` per
  *open* regression -- two -- against a cycle that otherwise spends minutes
  compiling. And `bisect_step` calls it too rather than assuming the loop did:
  **a repair that depends on its caller having been polite is not a repair.**
  Guard that a second pass is a no-op, or an always-saving repair dirties the
  tree every cycle and wedges the publish loop.

## A blocklist costs one outage per symptom; an allowlist closes the class

When plexus stopped being headless, every test job began inheriting a live
desktop session -- 24 variables, including `XDG_RUNTIME_DIR`, which is where
at-spi autolaunches its bus. `test_c_gtk_call.pas` then hung forever after
`gtk_init` and cost three days of native tiers their full hour.

The first repair set `NO_AT_BRIDGE` and `GTK_A11Y`. It worked, and it fixed
nothing: the next opportunistic client of a display, bus, keyring, portal or
notification daemon hangs identically and looks just as mysterious, because the
repo has not changed. **A blocklist buys one symptom at a time and leaves the
class intact.** The allowlist -- 11 keys plus the `PXX_`/`TESTMGR_`/`LC_`/`QEMU_`
families -- ends it.

**And it found something a blocklist never would have**: an unrelated third-party
API key from the login profile had been reaching ~3,000 job subprocesses per run
for days. Nobody was looking for it. That is the general argument for enumerating
what may pass rather than what may not -- you find out what was passing.

### The pass-through rule was backwards in the dangerous direction

The obvious reading of "plus whatever a job explicitly asks for" is *a job that
runs `xvfb-run` or `Xvfb` is a display job, so give it the session.* **That is
exactly wrong: those tools start a display of their own.** All three GTK jobs run
under `xvfb-run -a`, including the one whose at-spi hang started the ticket -- so
matching on the tool name would have re-admitted the session bus to the fix's own
motivating case. The rule triggers on a literal reference to a session
*variable* in the recipe text instead: a dependency the job states, not a guess
about what it probably does.

The generalisation: **an exemption keyed on what something appears to BE will
re-admit the case you built it for; key it on what the thing DECLARES.**

### Guard the mirror failure too

Stripping an environment creates the opposite defect -- a job losing something it
needs and going red with no cause in its log. Three things hold it off, and all
three are worth copying: the run **prints** what it dropped and which jobs kept
the session, into the same log as the verdicts it could change; a one-run
rollback exists and is **implemented, not merely documented**; and the guard pins
**both** directions, including that an `xvfb-run` job is *not* given the session
and a job naming `$DISPLAY` *is* and actually receives it.

## A silent assertion makes the harness report something else, confidently

The most expensive misread of 2026-08-26 traces to one shell idiom. A red job's
recorded `reason` was:

```
ok: $TMP [code=152328B ...] | ok: $TMP [code=65652B ...]
```

Two compile summaries with wildly different code sizes, which reads unmistakably
as a codegen divergence -- and was passed between two agents and put at the top
of a worker brief as "the strongest signal" before anyone checked. **They are the
aarch64 and x86-64 builds of the same source.** The job compiles for two targets
and then compares their *output*; the sizes were never supposed to match.

The mechanism is worth knowing because it will do this again. `job_reason` is the
**log tail**, by deliberate design. The recipe's actual assertion is a bare

```sh
test "$a" = "$b"
```

which prints **nothing** when it fails. So the tail is necessarily the two lines
*before* the assertion -- the last thing that did print, which was the two `ok:`
summaries. The harness reported them faithfully. Nothing was broken.

- **A silent assertion does not merely fail to explain itself. It causes a
  confident wrong explanation to be published in its place**, because a tail-based
  reporter always has something to show and no way to know it is unrelated.
- **Every failing check should print what it compared.** `test "$a" = "$b" ||
  { echo "outputs differ: ..."; exit 1; }` costs one line and removes an entire
  class of misdirection.
- **When a `reason` reads as a smoking gun, check whether the tool that produced
  it knows what the failure was.** A log tail does not. Read the recipe before
  reading meaning into its output.

A cross-target size difference in particular is the **null hypothesis, not
evidence**: two targets emit different amounts of code for the same source, and
that is the expected state of the world.

## A guard's human-readable note is triage evidence, so it must say what the guard DID

A devtest file flaked intermittently. The ticket fingered three cases; all three
were innocent, and they were innocent in a way that should have been visible:
they feed **frozen literals** to the predicate and measure nothing at all. The
real offender was a fourth case, **absent from the ticket entirely because it
passed** -- it called the timing probe three times against the real box and
asserted on the relationship between three ambient numbers.

What sent triage to the wrong three was a note in the *passing* output:
`Measured on the 12-core xeon`. That describes **where a constant came from**. It
was read as describing **what the case does at run time**. Meanwhile the one case
that genuinely measured the box said nothing about measuring. So the file
advertised the wrong suspects and concealed the real one, and every word of it
was true.

- **Anything a guard prints is read during triage, under time pressure, by
  someone who has not read the code.** Provenance and behaviour are different
  claims and must not share a phrasing.
- Say `FROZEN observations, fed in as literals` where a triager will see it, and
  say plainly when a case *does* touch the live environment.
- **An intermittent-flake ticket that cannot say WHY it is intermittent is
  usually pointing at the wrong line.** Here the explanation only appeared once
  the right case was found: the probe takes `min()` of three samples, so a
  momentary stall is absorbed -- the flake needs a load window spanning all three
  samples of the first call that has lifted by the second, i.e. a tier finishing
  mid-devtest. That is exactly the recorded observation (red during a full,
  green on immediate rerun) and exactly why it never reproduced on demand.
- **Supplying the timings made the assertions stronger, not weaker**: `r2 == 4.0`
  where observing had forced a loose `> 2.0`, and an exact reference where the
  old file could only bound it -- plus one it had never made at all, that a
  slower probe must not raise the reference. Determinism is not a weaker test; it
  is what lets you assert the thing you actually mean.

## A comment is an unverified claim, and tickets inherit it

Two N tickets in a row named the wrong mechanism, and the second one shows how a
wrong lead becomes durable. `PyImportIsConsumedOnly` carried a comment asserting
that `Counter` maps to *"pylib's TPyCounter constructors"*. It does not:
`TPyCounter` is the `itertools.count` shim, sharing four letters with `Counter`
and nothing else. The comment was wrong, the ticket quoted it as its "where to
look", and the investigation started up the wrong tree with a citation behind it.

The real binding was ordinary and discoverable in a minute: pylib has three
`function Counter` overloads returning a dict in counter mode, so `Counter("aab")`
compiles **with no import at all** and the from-import binds nothing.

- **A comment is documentation of an intent, not of a fact**, and unlike code it
  is never executed, so nothing ever contradicts it. It rots silently and in
  place.
- **A wrong comment is worse than none, because it launders into tickets.** Once
  quoted, it arrives with apparent provenance and the next reader has no signal
  that it was one person's belief.
- **Verify the lead before following it.** Find what a name is *actually* bound
  to -- read the binding site, or print it (`PXXDBG=n.locals`, `n.sig`) -- before
  theorising about why it misbehaves. That check is cheap and it is exactly the
  step the ticket's confident wording persuades you to skip.

The companion habit, from the same fix: **when you disprove a comment, correct
it in place, and grep for its copies.** That one had two.

## "The compiler couldn't compile X" and "the language can't do X" look identical from inside `compiler/**`

A new backend file needed to write a text file. It used the idiomatic form —
`var f: Text` with `Assign` / `Rewrite` / `Writeln` / `Close` — and the
self-host build failed:

```
pascal26:166: error: undefined variable (Close)
  in: compiler/asmtext_wasm.inc
```

That reads as an RTL gap, and the obvious next move is a ticket against the RTL
for a missing `Close`. **The RTL is fine.** Three steps settle it, and they take
about ten seconds:

- A standalone pxx program does `Assign` / `Rewrite` / `Writeln` / `Close` and
  writes its file. **This is the disproof, and it is the step people skip.**
- The implicit textfile surface is pulled in by a token pre-scan at
  `pasparser_prog.inc:651` — but only `if (not NoDefaultRtl)`.
- `compiler.pas:19` is `{$define PXX_NODEFAULTRTL}`.

The compiler deliberately opts out of the default RTL surface. `Close` is absent
**by design**, and the error is the compiler handing back exactly what it asked
for. Nothing at the failure site points at any of that: the define is one line
near the top of a 2000-line program, and the gate that consumes it lives in a
different file from the error.

- **Inside a compiler-internal file you are not compiling in the language's
  ordinary environment**, and an "undefined" diagnostic cannot tell you which of
  the two you hit. It reports absence at the *use* site; the cause is a define at
  the top of the translation unit.
- **Compile the same construct standalone before filing anything.** Works there,
  fails here → the absence is a property of the translation unit and there is no
  language or RTL bug to file. Fails in both → now you have something.
- **Getting this wrong files a bug that does not exist**, against a component
  that works, with a real error message as its evidence. That is the durable kind
  of wrong: nothing about it looks like a guess.

**And it decides which form is platonic**, which matters under the
do-not-revert-platonic-patches rule, where direction is the whole rule. If the
idiomatic form is blocked by a defect, it is platonic and stays, with a
`blocked-by:`. If it is blocked because this translation unit excludes the
surface it needs, it was never the platonic form *here* — the house form is
(`sysopen`/`syswrite`: 18 sites in `compiler/**`, zero declare a `Text`), and the
idiomatic form remains right on the other side of that boundary. Both are correct
in their own translation unit, neither is a workaround for the other, and nothing
is owed a revert.

Companion habit: **when you resolve one of these, write the chain into the file,
not just the conclusion.** The conclusion alone gets re-litigated by the next
person who hits the same error message, and their most likely move is the RTL
ticket that should not exist.

## "The pinned binary reproduces it" may be a claim about a MIXED compiler

A ticket recorded that `$(PXX_STABLE)` reproduced a segfault, which made a
brand-new feature's own hole read as a pre-existing bug and sent the next agent
looking in the wrong century of the history. It was measured honestly and it was
wrong.

**A stable binary run from a directory with no `builtin/` beside it falls back to
the CWD-relative `compiler/builtin/` -- that is, to the WORKING TREE.** So a
"pinned" run launched from the repo root is the pinned executable driving
whatever builtins are checked out right now, uncommitted work included. That is
not the pinned compiler; it is a hybrid that exists on nobody's machine but
yours, and it can fail in ways neither endpoint does.

The rule this file already states -- *any result you report must name the sha of
the binary it came from* -- is necessary and, here, not sufficient. The binary's
identity was known. Its **builtin tree's** identity was not, and nothing in the
invocation made the difference visible. So:

- Run a pinned binary **from beside its own frozen `builtin/`**, or verify which
  tree it actually resolved before believing the result.
- When an endpoint measurement says "broken at both ends", suspect the harness
  before concluding "latent since forever". Two greens and a red in the middle is
  a shape a mixed compiler produces easily.
- A provenance line in a ticket is evidence like any other, and it decays. The
  agent that closed this one re-measured instead of inheriting, found v374 and
  v375 both green, and turned "latent, unbounded" into "fixed two commits after
  it was filed".

Same family as `code : STALE` in the watcher and the frozen-builtin seam
`gate.sh` now guards: **the artifact you are measuring is assembled from more
parts than the one you named.**

## "Ruled out" and "could not look" must never print the same

The sharpest version of this file's refrain, and it cost six days. A ticket
recorded: *the kernel log is unreadable unprivileged, so OOM can be neither
confirmed nor excluded.* That sentence made **ruled out** and **not looked at**
indistinguishable -- and a hypothesis nobody can check is the one an
investigation drifts toward, because nothing ever pushes back on it.

It was also false. `dmesg` is blocked here (`kernel.dmesg_restrict=1`), but
**`journalctl -k` is not, for anyone in group `adm`, and this account is.**
Everyone who hit the wall hit it with `dmesg` and stopped. The real answer took
minutes: **0 kernel OOM kills across three boots**, 35,486 kernel lines, journal
reaching back far enough to cover the date in question.

Three things to carry:

- **One blocked tool is not a blocked question.** Before writing "cannot be
  determined", find the second reader. Privilege here is per-interface, not per-
  fact: `dmesg` restricted, `journalctl -k` open to `adm`.
- **Check the mechanism that logs somewhere else.** `systemd-oomd` kills on cgroup
  PSI *before* the kernel is out of memory, logs to its own unit rather than the
  kernel log, and targets the heaviest cgroup -- here, a fuzz batch or the test
  matrix. A kernel-only answer would have read as an all-clear with the actual
  candidate unexamined. (It had killed nothing, ever.)
- **State exactly how far the exclusion reaches.** Kernel OOM and oomd both leave
  a durable record; a peer's `SIGKILL` leaves none. So excluding them is not
  "nothing killed it" -- it is *every hypothesis that would have left evidence
  did not happen*, which leaves the one that never does. That is a real narrowing
  and it is the most the evidence supports.

**And the most dangerous: a corrupted input arriving dressed as a finding.** A
differential probe used fixed paths -- `/tmp/fdp.pas`, `/tmp/fdp_f`, `/tmp/fdp_p`
-- so two concurrent copies overwrote each other's source and binaries. The
result was not a crash. It was a **report**: `new divergences: 34`, `no-oracle
skips: 90`, rows reading `fpc=[]`. An oracle whose binary had been overwritten
mid-run presented as an oracle that *disagreed*. This is worse than a torn-down
run publishing in the vocabulary of a completed one, because the tool's entire
job is to be believed about findings, and the corruption is indistinguishable
from its output. **A tool that reports divergences must isolate its workspace
(`mktemp -d` + trap), or its worst failure looks exactly like its best work.**

**The most literal instance: a diff against a missing operand.** The bench
harness emits `CANARY-DIFF vs -O0` for each optimisation level -- and when the
`-O0` build itself fails, `ref_out` stays `None`, so every other level dutifully
reports a difference from a baseline that was never produced. Three red rows, one
defect, and nothing in the output separates *the levels disagree* from *there was
nothing to compare against*. Any comparison must state that its reference exists
before reporting a difference from it.

The design counterpart is now in `tools/whokilled.sh`: **three verdicts, and any
blind probe forces a distinct exit code**, so a caller cannot mistake blindness
for clean. Its CANNOT-TELL branches had never executed on this box, so the
devtest drives them with fakes on PATH -- a branch that has never run is not yet
known to work.

## A caveat attached to a claim is not the same as declining to make the claim

The sharpest self-correction of 2026-08-26, and it came from someone who had
already written the caveat that would have saved them:

> *"105 logs is a partial view, so tell me if the clean result does not hold at
> the end."*

They wrote that, and then reported the hazard **absent** anyway — twice,
confidently. The signature appeared at log 684. The caveat was true, was
attached, and did no work at all, because **a hedge does not change what the
reader does with the claim.** Everyone downstream acted on "absent"; nobody acted
on "of 105".

The rule: **if the caveat is load-bearing, the claim is not ready.** Report the
observation (*"clean through 105 of ~3000"*) rather than the conclusion
(*"the hazard is absent"*), and let the conclusion wait for the evidence that
would justify it. This is the same failure as stopping a search at the point
where the evidence agrees with you — the caveat is what you write instead of
continuing to look.

Its twin, from the same day: **when a fix works, count how many things you
changed.** A gate went RED from a `/tmp` worktree; the worktree moved and the
seed mtime changed in the same window; the RED went away; one story fit, so
nobody looked for the second variable. Both errors are the same shape — stopping
at the first sufficient explanation — and neither is caught by any test.

## A suite that never sets the flag is blind to what the flag guards

A green suite is evidence about the code the suite *reached*. For anything behind
a gate, the gate is what decides whether it was reached — so the same property
that makes a feature safe to land makes the suite unable to say anything about it.

The instance, 2026-08-26: four `-O3` optimisation passes, and the question was
whether to promote them to `-O2`. The tempting evidence was a full-tier verdict at
the sha that contained them. But **almost nothing in the tier compiles at `-O3`**
— the NilPy recipes are `./$(COMPILER) test/x.npy out`, no `-O` flag at all — so a
full-tier GREEN would have proven mainly that *the gate kept the passes out of the
default path*. That is a fact about the gate, not about the passes, and reading it
as "they are safe to promote" inverts what it shows.

**The same reasoning tells you which evidence does bear on it:** the two-oracle
differential run across all four `-O` levels, and `test-selfcompile-odiff`, which
actually varies the flag. Ask *what in this suite sets the flag* before treating
its verdict as coverage.

**The corollary that catches bugs rather than just weak evidence:** if a change
carries a gated half and an ungated half, the tier can only see the ungated half —
so when a gated-feature window produces a regression, the ungated half is the
first suspect, however small it looked in the commit message. A commit whose
subject was `-O3 cmp-immediate` also carried an ansistring runtime blob change
that no gate guarded, and that half is the only part of the work the suite could
observe.

The general form: **a flag makes a feature invisible in exactly the tier you
would use to judge it.** Coverage is not "did the suite pass", it is "did the
suite execute this path", and a gate is a machine for guaranteeing it did not.

## Record the negative result, or someone will spend a night rediscovering it

Track T profiled the test matrix and reported three findings, one of which was
that **the scheduler is fine** -- 90% core utilisation, ~1,343 idle core-seconds
out of 13,663, near the floor for a job graph with dependencies. Nothing to
unpick. They wrote it down deliberately, in the owning ticket, in the same
prominence as the positive findings: *"I would rather cost myself the finding
than have the next person spend a night discovering it."*

That instinct is right and it is rare, because a negative result feels like an
absence of work. It is not. "The obvious suspect is innocent" is expensive to
establish and free to forget, and it is the single most re-derived kind of fact
in a long-running project -- the scheduler, the allocator, the disk, whichever
component *looks* like it should be the problem will be re-measured by every new
arrival until someone writes down that it was not.

So: when a measurement clears a suspect, **say so in the ticket, name the number,
and say plainly that nobody should start there.** The same applies to a plausible
fix you tried that did not help. An unrecorded dead end is a trap that resets
itself.

**And record the option you measured and DECLINED, with its number.** Track T
priced a skip cache for pin-built jobs -- provably unchanged verdicts, genuine
repeated work, the predicate already written -- at **~3% of the matrix**, and
turned it down. The reason is the one worth copying: its failure mode is *a job
that should have run and did not, reported as a pass*, which is the exact defect
class removed five times in two days (the unenrolled rung asserting nothing, the
torn-down run silencing the request for coverage, unreached jobs reading as
FIXED). **Adding a sixth source of silent under-coverage to save 3% is a bad
trade at any exchange rate** -- and the fact that the mechanism would have been
easy to build is not a point in its favour.

The general form: **price a saving in what it costs you in assurance, not only in
what it costs to build.** A cache, a skip, a memo and an early-exit are all the
same bet -- that a thing you did not check is unchanged -- and the bet is only as
good as the predicate, forever, including after someone edits the predicate. In
the ticket it now sits as *declined, with the number and the reason*, plus the
condition that would reopen it: if the NilPy tax is fixed, 3% becomes a large
share of what remains and the trade is worth re-pricing.

That is the difference between a decision and an oversight, and only the write-up
tells them apart later.

The companion rule, also demonstrated: **do not extrapolate across a moved
denominator.** They declined to state a post-fix matrix total until the next full
lands, because the compiler's own cost had changed underneath the measurement.
Multiplying two estimates is how a number stops being a measurement.

## A number moving in the direction you hoped is not a check

Track T narrowed a blame range from 137 commits to 2, ran it against the live
regression, saw the reduction, and read that as confirmation. It was evidence of
the bug. The cut had been derived from "a pin-built job builds with the pinned
binary, so only pin moves can change its verdict" -- but `make pin` freezes only
`compiler/builtin/**` and **deliberately leaves `lib/rtl` and `lib/pcl` live**
(the Makefile says so: Track B expects its lane editable), and the job compiles
from the live `test/` tree. A pin-built job is blind to `compiler/**`, not to
everything except the pin. Those 137 commits held **2 `lib/` and 34 `test/`**
commits, every one a genuine candidate, and the cut discarded all of them. The
corrected number is **137 -> 37**.

Two lessons, and the second is the transferable one.

**Too narrow is the direction that costs you.** A too-wide range costs bisect
steps; a too-narrow one can exclude the culprit, and then the bisect terminates
cleanly, prints a sha, and is indistinguishable from a correct answer. So when a
range shrinks, the question is never "by how much" but "what did it drop, and
could any of it have caused this?" **A commit whose file list cannot be read is
KEPT.** Never narrow blindly.

**The measurement confirmed what it was pointed at, which was the wrong
question.** It answered *did the range shrink* when the question was *did it drop
anything causal*. This is the sharpest instance in this file of a check that
runs, passes, and asserts nothing about the thing at issue -- and it is more
dangerous than an absent check, because it discharges the urge to look. A result
that agrees with your hypothesis is the moment to ask what else would have
produced that same result.

The catch, both times it has happened: **writing the assertion forced an
enumeration where the reasoning had been gesturing.** Asking "what must a
pin-built job be able to see?" as a guard, rather than as a sentence, put `lib/`
in the list immediately. The guard has now caught two defects the reasoning
missed, both by demanding names instead of a wave.

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

And the author's own account of why it caught them is the part to copy into the
next guard you write: **it asserted the CONSEQUENCE, not the number.** The
message was "a pin taken during one of these runs can no longer be called safe",
not "expected 0 pin-built jobs, got 1". Their words: *"the number would have
been just as red and I might well have edited it."* A count mismatch invites you
to update the count -- it reads as a stale expectation, which is usually what a
red count is. A sentence naming what breaks tells you which side is wrong, and
makes editing the guard visibly the wrong move. Assert the property somebody
downstream depends on, in the words they would use.

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

## Reaching for the instrument is necessary and not sufficient — the FORMATTER is part of its aperture

The section above is about choosing a sentinel the *program* cannot mistake for
a value. This is its mirror: an illegal sentinel, chosen correctly, destroyed on
the way to your eyes by the thing that printed it.

Measured 2026-08-30, hunting `bug-c-a-header-reached-by-uses-discards-function-
bodies-and-imports-them-instead`. The question was what `CModuleOfTok` returns
for a token in a `uses`d header, where **-1 means "no C module"** — a properly
illegal sentinel, exactly as the section above prescribes. The probe printed it
with `IncSmallIntStr`, whose own doc comment says *"decimal text of a small
**non-negative** int"* and whose first line is `if n <= 0 then Result := '0'`.

So the probe printed `module=0`. Which is a module id. The one value that meant
*"no module"* was rendered as a real answer, the output looked entirely
reasonable, and the conclusion drawn from it was wrong. `differential-probes.md`
already carries this warning — *a probe that FORMATS its output can answer a
different question than you asked* — and it had been read the same night, in
this repo, by the person who then walked into it.

**The sequence is the lesson, because each step was closer to measurement than
the last and each still produced a plausible wrong answer:**

1. **Reasoned about the function instead of printing it.** This file's headline
   failure, committed by someone who had read this file.
2. **Printed it — through a formatter that could not represent the answer.**
   The instrument was right, the aperture was not.
3. **Measured a harness artefact and read it as the bug.** The test program and
   the test header shared a stem, so `uses foo` resolved to `foo.pas`, the
   program itself. The compiler reported a real and correct error about *that*,
   and it was read as the defect under investigation — which is the most
   expensive of the three, because everything about it looks like signal.

Only the fourth attempt — distinct names, and a formatter with a branch for the
negative case — produced the boundary table the ticket now carries.

**What to actually do**, in rough order of cost:

- **Print the sentinel's own spelling, not its number.** `module=NEG` /
  `module=none` cannot be confused with an id. Branch on the sentinel in the
  probe rather than trusting the renderer.
- **Read the helper you reached for.** `IncSmallIntStr` says non-negative in its
  first comment line and clamps in its first statement; thirty seconds of
  reading beats a rebuild and a wrong conclusion. Its siblings
  (`CPSmallIntStr`, `AsmIntToStr`, `RIntToStr`) do not all agree on this, so
  which one is in scope changes the answer.
- **Sanity-check the probe against a case whose answer you already know.** Here
  a header with no includes at all was known to work; had its probe line said
  `module=0` while the failing one also said `module=<some id>`, the collision
  would have been visible immediately.
- **Give the harness distinct names.** A test program and its test header
  sharing a stem is not an exotic mistake — it is what you get from naming both
  after what they test.

The general form, which is what makes this more than one bad night:

> **An instrument narrows what you can be wrong about; it does not eliminate it.
> Everything between the value and your eyes — the accessor, the formatter, the
> harness, the file names — is part of the instrument, and any of it can quietly
> answer a different question.**

## A background job's reported exit code is the LAST command's, not the job's

Measured 2026-08-30, six times into a night of the same class.

I launch gates as:

```sh
tools/gate.sh quick > gateq8.log 2>&1; tail -12 gateq8.log
```

so that the log is visible when the job returns. The `;` makes **`tail`** the
last command in the list, so the shell's exit status is `tail`'s — always 0 —
and the completion notification read:

> `Background command "Gate slice 2a" completed (exit code 0)`

for a gate whose own last line was `gate: RED (exit 1)`.

**A green light reporting on a red run, produced entirely by the shape of my own
invocation.** Nothing was wrong with the gate, the log, or the notification —
each reported correctly on what it was actually given. Had I trusted the
notification instead of reading the log, I would have committed on a red gate
and had a green summary line to point at.

**The fix**, and prefer the first:

```sh
tools/gate.sh quick > gateq.log 2>&1              # exit code is the gate's
tools/gate.sh quick > gateq.log 2>&1; rc=$?; tail -12 gateq.log; exit $rc
```

**The rule.** In a `;`-list the status belongs to the last command, and a
convenience appended for readability is a command. Pipelines have the same shape
(`cmd | tee log` reports `tee`); so does `cmd && echo done` in the other
direction. **Anything appended after the thing you are measuring becomes the
thing that reports.**

This is the same family as the formatter section above and the stdout-capture
one: the instrument was fine and the *plumbing around it* answered a different
question. It belongs with them because the tell is identical — a result that
looks clean, arrived at through a layer nobody was examining.

## `perf` being blocked is not "no profiler" — build the compiler with FPC and `-pg`

`perf` is refused on plexus (`kernel.perf_event_paranoid = 4`) and cannot be
lowered without root. A session concluded from that there was no way to profile
the compiler, recorded *"there is no pathological function to optimise"* on the
strength of a linearity argument instead, and was wrong: the next session's
profile found **four** hotspots and cut the measured cost in half
(`bug-a-every-nilpy-compile-pays-a-fixed-nine-second-cost`).

`compiler.pas` is FPC-bootstrappable by construction. FPC supports `-pg`.
`gprof` is installed. Eleven seconds:

```sh
fpc -O2 -Tlinux -Px86_64 -pg -FU/tmp/units -o/tmp/pascal26-pg compiler/compiler.pas
/tmp/pascal26-pg /tmp/repro.npy /tmp/o        # writes gmon.out into $PWD
gprof -b -p /tmp/pascal26-pg gmon.out         # flat profile WITH CALL COUNTS
gprof -b -q /tmp/pascal26-pg gmon.out         # call graph: who called whom, how often
```

(`-FU` a scratch unit dir, or a `-pg` `.o` will collide with a later non-`-pg`
build and fail at link with `undefined reference to mcount`. Run the compiler
from the repo root — it resolves `pylib`/`builtin` relative to the working
directory.)

**Read the CALL COUNTS, not the percentages.** The `-pg` binary is FPC's
codegen, FPC's ansistrings and FPC's heap manager, so its time shares are
*indicative* of ours and no more — measured on the same workload, the FPC-built
compiler runs 3.8x faster than our own build of the same source. But the counts
are properties of the SOURCE and are exactly ours. "284,481 calls issuing
20,058,632 AppendChar" is not a judgement call, and it is what named the
function. Confirm every fix on the real self-hosted binary before believing it.

**Linear throughput is not evidence against a hotspot.** The wrong conclusion
above came from a good measurement read badly: compile time tracked emitted code
volume at a near-constant ~4 s/MB across a 150x range, which rules out a
*superlinear* blowup and nothing else. A function costing a fixed 3 microseconds
per emitted instruction plots as a perfectly straight line and is still 30% of
the compile.

## Profile the SHIPPING binary — `-g` alone silently means `-O0`

The section above gets you call counts. When you want *shares* — where the time
actually goes — the trap is one line of `compiler.pas`:

```
compiler.pas:739    OptLevel := 2;        { the default }
compiler.pas:1536   if DebugInfo and not OptLevelExplicit then OptLevel := 0;
```

So **`make pxx-debug` builds a `-O0` compiler.** For gdb that is the point (1:1
codegen keeps breakpoints on the lines you set them on). For a profile it is a
different program from the one everyone runs, and *nothing in the output says
so* — you get a plausible, well-shaped, confidently wrong weighting.

Build the real one explicitly, and check you got it:

```sh
./compiler/pascal26 -O2 -g compiler/compiler.pas /tmp/p26-g-O2
# its code=NNNN must match the plain default build's code=NNNN.
# If it does not, -g changed the codegen and the profile is of something else.
```

Measured 2026-08-26 on the same zero-byte `.npy`: the `-O0` build put 53.5% of
in-`.text` samples in the builtin runtime blob range, the real `-O2` build 48.1%,
and the parser's share moved with it. The *ranking* happened to survive; the
numbers did not, and there is no way to tell which you are holding from the
report alone. **Record the `-O` level of the profiled binary the way you already
record its sha.**

### `tools/pxxprof` — when `perf` AND gdb-attach are both refused

`perf_event_paranoid = 4` blocks `perf`; yama `ptrace_scope = 1` blocks
attaching to a non-descendant. `tools/pxxprof` forks the target and
`PTRACE_SEIZE`s its own child, so it needs neither:

```sh
cc -O2 -o /tmp/pxxprof tools/pxxprof.c
/tmp/pxxprof /tmp/samples.txt 150 /tmp/p26-g-O2 /tmp/repro.npy /tmp/o
python3 tools/pxxprof_symbolize.py /tmp/syms.txt /tmp/samples.txt | head -30
```

Two things it will not tell you, both of which have to be read around:

- **The `<outside .text / vdso>` bucket is not time.** Its own header warns the
  share swings 8-38%; measured, it was **70% in one run and 0.9% in the next of
  the same binary**, with the address moving under ASLR
  (`75522eaa642c` -> `73d5a58a642c`). Cross-check against `/usr/bin/time`: if
  `user` is within a few percent of `wall`, the process is pure user CPU and the
  bucket is sampling noise. **Exclude it and renormalise on in-`.text` samples**
  — every percentage that includes it is deflated by an amount that changes per
  run.
- **The builtin runtime carries no DWARF**, so `PXXAlloc`, `PXXFree` and the
  hand-emitted retain/release blobs all fall into the FIRST symbol's range and
  show up under the *file* name. When that range is hot — it was 48% — read it
  by histogramming the raw addresses and disassembling around the hot ones, not
  by trusting the label. That is how three `idiv`s by the literal 8 turned out
  to be 11.4% of the whole compile.

**It did not compile as committed** (`open()` with no `<fcntl.h>`; fixed in
`1202429f4`). Worth naming because of what it cost rather than what it was: a
profiler that does not build is a profiler nobody reaches for, and the published
figure it was committed with — 56% in the first 5 KB of `.text` — is closer to
what the `-O0` debug build gives than the `-O2` one. **A tool that fails to
build fails silently in the worst possible way: as an absence of measurements,
which reads exactly like an absence of anything to measure.** Build it before
you trust a number attributed to it.

## Only binaries timed inside ONE interleaved run are comparable — and a pass changed to fix a measurement is as sound as the measurement

The `-O3` residency slice (2026-08-28) measured mandelbrot at **1.10 s** before
a change and **1.18-1.24 s** after it: a clean 7% regression, min of 5, same
command, same box. The obvious reading was that the change had a cost, so a
per-class fix was built to remove it, and — this is the part worth recording —
**the causal explanation was written into `ir_codegen.inc` as a comment stating
it as fact**, complete with the two numbers.

Re-measuring all three binaries *inside a single interleaved run* gave
**1.34 / 1.33 / 1.34**. The same "before" binary that had measured 1.09 now
measured 1.34. There was no regression, there had never been one, and the fix
was a fix for the box's load.

Why the usual precaution did not save it: `%U` user time, A/B alternating,
**min of 5** is the discipline this repo already uses, and it is not enough
here. plexus runs Track T's watcher and several agents; load swung between 4
and 13 during that session. Min-of-N removes noise *within* a run and removes
nothing at all *between* runs, so two numbers taken ten minutes apart are two
measurements of the machine, with the binary as a minor term.

- **Time every variant you intend to compare inside one loop**, alternating, in
  the same process invocation window — `for k in 1..N; do for v in old new t3;
  do time ./$v; done; done`, then take each one's minimum. Three variants in
  one run is comparable; the same three run one after another as separate
  commands is not.
- **A delta measured across runs is not evidence for a cause.** It is not
  evidence for an effect either. The interleaved re-run comes *before* the fix,
  never after it.
- When you do revert an experiment, **verify the revert by rebuilding and
  comparing the binary sha to the pre-experiment one.** Bit-identical is proof
  the tree is back where it was; "I undid the edits" is not.

The general shape, which is why this sits next to the bisect entry above: a
change made to fix a measurement inherits every weakness of that measurement,
and a *comment* asserting the cause outlives the measurement entirely. The
comment would have been read for years as a finding. It was a load average.

**Interleaving alone is not enough, and the same slice proved that too.** Having
adopted the rule above, the same session then reported a "~2-6% slower
self-compile", *interleaved*, "reproduced in three runs" — and it evaporated at
higher repetition (min of 6: +0.3%; and the same compiler was FASTER on a
min-of-15 short-compile workload). Three under-powered runs share a bias; they
do not confirm each other. **Interleaving fixes WHICH runs you may compare;
repetition fixes how confidently.** Concretely, on this box: 3-4 reps cannot
resolve a 5% effect on a 17-second workload, and **a short workload with many
reps beats a long workload with few** — `hello.pas` at min-of-15 settled in two
minutes what `compiler.pas` at min-of-3 had got wrong in ten. If the effect you
are claiming is smaller than ~10%, say how many reps produced it, or do not
claim it.

## Regenerate the baseline; never reuse one from earlier in the session

The same slice checked that an `-O3`-gated pass had not disturbed `-O2`, by
hashing a fixed corpus compiled for all six targets and diffing against hashes
taken earlier that session. One program, `exc`, came back **changed on all six
targets**.

That result is impossible: the pass exits on `OptLevel < 3` and the corpus is
compiled at the default level. The impossibility is what made it cheap —
an implausible-but-conceivable delta would have been debugged for an hour.
Direct comparison of the two compilers on that program showed `cmp` finding no
difference at all, which located the fault in the harness rather than the
compiler. `exc` is the only corpus program that `uses SysUtils`, and a
`git pull` between the two hash runs — the v389 pin — had updated `lib/rtl`
underneath it. Re-running **both** sides back to back gave 48/48 identical.

- **A baseline is only valid against the tree that produced it.** In a repo
  where a pin can land `lib/rtl` mid-session and other lanes push continuously,
  "earlier today" is a different tree. Regenerate both sides, back to back,
  from the state you are actually comparing.
- **Say what you pinned, when, to whoever is mid-measurement.** A pin that moves
  `lib/rtl` invalidates every in-flight before/after in every lane, silently.
- The tell that saves you is the one above: **when a result is not merely
  surprising but structurally impossible, suspect the harness first**, and go
  find the shortest path that bypasses it.

## An optimisation's value is a property of the transform AGAINST A BASELINE — and the baseline moves, sometimes by your own hand

Three items of one optimisation ticket were sized on 2026-08-27, ranked, and
dispatched in that order. Within a day the ranking had inverted twice, and both
times the cause was **another item of the same ticket landing**:

- **An item was emptied.** Store->reload elimination for register-resident
  destinations was filed when the value round-tripped through the frame, which
  made it a real memory access to remove. By the time it was claimed, the
  residency change had put that value in a register, and the "reload" was a
  reg-reg move worth nothing. 6 instructions out of 13,483.
- **An item was revived.** An emit-time operand scheduler had been *correctly*
  disconfirmed at **1.4%** hours earlier — the loop body was then 12 cyc/iter
  dominated by two frame round-trips, and every `mov %rN,%rax` sat in their
  shadow. The residency change removed the memory traffic. The body became 6.5
  cyc/iter with **zero memory reads**, the dependency chain now ran *through*
  those staging moves, and the same transform measured **~1.6x**.

**The same instructions that are free while they overlap a 5-cycle
store-forward are the critical path once it is gone.** Neither measurement was
wrong; each was a measurement of a different machine.

So: **re-measure the prize before starting an item, not just the mechanism.**
Disassemble what the compiler emits *today* and time it; the ticket's number
describes a compiler that may no longer exist. A stale prize is more expensive
than a stale number, because it does not look like a claim to re-check — it
looks like work waiting to be done, and the backlog protects it.

## An A/B comparison is only valid when B is A minus exactly ONE thing

The same session's first model priced "make the register authoritative" at
**2.15x** by comparing a variant that kept the frame dual-writes against an
idealised body that had neither the dual-writes nor any of the operand staging.
Two changes, one credited. Isolated properly — every variant transcribed from
the *current* disassembly and differing from the baseline **by deletion only** —
the store removal was **~5%** and the staging removal was the rest.

The failure mode is not carelessness, it is that a variant table looks rigorous.
Four rows of times with four descriptions reads as a decomposition whether or
not the rows are separable. Two habits fix it:

- **Build each variant by deleting from the previous one**, never by writing the
  "ideal" version from scratch. If you cannot express B as "A minus X", you are
  not measuring X.
- **Calibrate the baseline against the real artifact** before trusting any row —
  the transcribed A above had to reproduce the shipping binary's 0.61 s. A model
  that does not reproduce the thing it models decomposes nothing.

## Interleaving, repetition, amplification — three different fixes for three different lies

One optimisation session produced three separate false readings in one night, on
one box, with the same command. They are worth stating together because they
look identical from the outside — a number that is wrong — and each needs a
different fix. The two entries above cover the first two; this is the third,
and it is the one that survives both of them.

**Amplification: below ~2% of the workload, `/usr/bin/time` is quantisation, not
measurement.** A boolean-heavy loop benchmark measured **0.49 vs 0.51**, and on
a re-run **0.55 vs 0.56** — "2-4% slower", twice, interleaved, min-of-15 both
times. That is exactly the shape of a real small regression: consistent sign,
survives repetition, plausible mechanism available if you go looking for one.
It was **one 10 ms tick** on a ~0.5 s workload. `%U` is reported to 10 ms, so at
half a second the quantum *is* 2%, and the "consistent" sign was one tick
landing the same way twice.

The fix is to make the sample long enough that the timer's resolution is small
against it — run the binary several times inside one timed command:

```sh
/usr/bin/time -f "%U" sh -c './bench >/dev/null; ./bench >/dev/null; ./bench >/dev/null'
```

At ~1.9 s per sample the same comparison resolved to **1.46 vs 1.45** — neutral,
and the regression had never existed. The same correction turned a compile
workload's "0.18 vs 0.19" into "0.64 vs 0.64" on a longer input.

The three compose, and the order matters because each is invisible to the one
before it:

| | fixes | symptom when missing |
| --- | --- | --- |
| **Interleaving** | WHICH runs you may compare | the same binary measures 1.09 and 1.34 |
| **Repetition** | HOW CONFIDENTLY | three under-powered runs share a bias and read as confirmation |
| **Amplification** | WHETHER THE TIMER CAN SEE IT AT ALL | a one-tick difference reads as a consistent few-percent effect |

So before believing any delta under ~5%: is it interleaved, is the rep count
enough to resolve it, and **is the effect larger than one tick of the timer?**
The last question is the cheapest of the three to ask and the easiest to skip,
because the number already looks like a measurement.

## When the box is busy, stop timing and start COUNTING

All three corrections above make a wall-clock delta trustworthy. None of them
help when the box itself is the problem — this fleet routinely runs nine agents
and seven concurrent self-host builds, at load 9-19 on 12 cores. At that point a
wall-clock A/B is not measuring your change, and no amount of interleaving fixes
it.

**Count retired instructions instead. The count is load-invariant by
construction, not by assumption.**

`perf stat` is the obvious tool and is **unavailable here**: this workstation runs
`kernel.perf_event_paranoid = 4`, which denies unprivileged access to every event,
hardware and software alike. Raising it is a root sysctl on the owner's machine.

So use qemu's execution trace, which is better anyway (frank-optimize-b4,
2026-08-29):

```
qemu-x86_64 -one-insn-per-tb -d exec ./bench 2>&1 | wc -l
```

One log line per instruction **executed** — exact and deterministic rather than
sampled, with no multiplexing and no skid. It costs ~100x slowdown, and you pay
for that by **shrinking `n` instead of enduring it**: a straight-line loop with one
back-edge has a constant per-iteration cost, so the count scales exactly and small
`n` proves the same thing. Measured on the W1 shift slice:

| n | BASE | HEAD | delta | delta/n |
| --- | --- | --- | --- | --- |
| 2 000 | 44 211 | 42 211 | 2 000 | 1.000 |
| 20 000 | 440 227 | 420 227 | 20 000 | 1.000 |
| 50 000 | 1 100 235 | 1 050 235 | 50 000 | 1.000 |

**Delta exactly `n` at all three sizes, no residue** — one instruction per
iteration, proven rather than argued. Load was 9.51 during the run and 16.44
shortly before; recorded, and *irrelevant*, which is the whole point.

**It also corrects the denominator, which eyeballing the emitted code will not.**
b4 had counted the hot loop as 18 instructions from the straight-line body. The
execution trace showed 18 addresses hit exactly `n` times **and 3 hit `n−1` times**
— the increment tail, skipped on the last iteration. The real body is 22, so the
win was 4.55%, not 5.6%. **Reading the emitted code tells you what was emitted;
only running it tells you what retires**, and loop control is the part a human
reading a listing reliably forgets.

Wall clock is still owed for anything claiming a *time* improvement — instruction
count cannot see cache behaviour, port pressure or branch prediction. Take it when
the box is quiet, and stamp both numbers with the binary sha **and** the load
average.

## A capability that exists and cannot be asked for costs you at the worst moment

`compiler/asmtext_wasm.inc` could write a `.wat` — the text form of a wasm
module, the oracle you diff the binary against — from the day it landed. The
compiler had no way to ask for it: the only caller was a standalone test.

That was invisible for weeks and then cost an hour, because the moment it
mattered was `0001db0: error: unable to read i32 leb128` — a *parse* failure,
which reports a byte offset and no function name, on a module of 124 functions,
with no way to look at what had been emitted. The gap and the need arrived
together, which is the shape: **an unreachable capability is only ever
discovered from inside the problem it would have solved.**

Two things to take from it:

- **When a tool grows an output the maintainer uses by hand, wire it to the
  command line the same day.** The fix here was one branch on the output
  extension. Deciding it was not worth a flag was correct and irrelevant — the
  cost was not the flag, it was that nothing could reach the code.
- **When a diagnostic reports a byte offset, the first move is to make the
  thing readable, not to read the bytes.** The actual root cause (an
  `i32.const` of 4294967295, unencodable as a 32-bit signed LEB) was five
  minutes' work once the `.wat` could be produced and the WAT/binary pair could
  be compared. Decoding the binary by hand first was the slow path, and it is
  the one you take when the fast path does not exist yet.

## A comparison with no floor: two totally-failed runs diff clean

`FAIL` compares equal to `FAIL`. So a differential harness that emits a per-case
verdict and is then diffed will report **perfect agreement** when both sides
managed to run *nothing* — and it reports it in exactly the same words it uses
when both sides ran everything and agreed.

Measured, 2026-08-29. A corpus harness compiled 8 programs for 6 targets with two
compiler binaries and diffed the hash lists. It did not export `PXX_HOME`, and
the binaries under test had been copied into a scratchpad, so neither could find
its RTL. All 48 rows on both sides were `FAIL`. The diff was empty. The result
was read as "48/48 byte-identical across all six targets", written into a commit
message, and cited in a ticket — for **four separate steps** of an optimisation
campaign. Every one of the four conclusions turned out to be true when re-run
properly, which is luck, not method: the evidence had been vacuous the whole time.

> **A comparison that can succeed by measuring nothing has no floor.** It is most
> confident exactly when it is least informed, and no amount of staring at the
> output distinguishes the two cases.

Same signature as `make compiler/pascal26` printing `up to date` in a freshly
seeded tree (CLAUDE.md): a success message in the wrong dialect, with everything
downstream healthy. Both belong to the family this whole document is about — the
expensive failures here do not crash, they return a plausible answer.

**So give every differential harness a floor, and make it refuse rather than
answer emptily:**

- **Count the comparisons you actually made, print the count, and exit non-zero
  when it is zero.** One line. It is the whole fix.
- **Report the count alongside the verdict**, so "identical" is never read
  without its sample size. "identical (25 rows)" cannot be misread; "identical"
  can.
- **Subtract the rows that can never work** — 3 of those 8 corpus files were
  `unit`s, compilable standalone on no target ever, and 8 rows were xtensa, which
  has no dynamic-symbol support. Their permanent `FAIL`s were the noise that made
  a screen of `FAIL` look normal.
- **Set the environment inside the harness, not in the caller's shell.** The bug
  was one missing `export` in a script that had been correct every time it
  happened to be invoked from the right directory.

And the discipline that catches it when the harness is someone else's: **before
believing a clean differential, make it fail on purpose.** Point it at a
deliberately broken binary. If it still says "identical", it was never looking.

## A count inferred from a size delta is not a count

Sibling of the empty-diff entry above, from the same day, and the more common of
the two because it reads as *more* rigorous rather than less.

A probe was added that emits an 11-byte instruction per site. To find out how
many sites there were, two binaries were compiled — one with the probe, one
without — and the size difference divided by 11. Answer: 261 sites. The probe
was then asked directly, and the answer was **76**.

Nothing about 261 looked wrong. It was arithmetic on two measured quantities,
and it was three and a half times the truth, because a binary's size is not its
code size, code motion and alignment absorb bytes, and the emitted sequence was
not the length assumed.

> **The instrument that produced the effect can also count it. Ask it.** A number
> derived from a side effect of the thing you are measuring inherits every
> assumption you made about that side effect — and unlike the measurement, it
> carries no signal when one of those assumptions is wrong.

Chasing the discrepancy paid twice over: reconciling the counted 76 against the
37 instructions actually removed from the binary is what surfaced a real gap
between codegen-time site counts and emitted code, which two further hypotheses
(dead-proc elimination, double emission) were then measured and ruled out.
The gap is recorded as unexplained rather than smoothed over.

**In practice:**

- **Print the count from the code that does the thing.** One `WriteLn` behind a
  debug flag, emitted where the transform fires. It cannot drift from reality
  because it *is* reality.
- **When two counts disagree, that is a finding, not an annoyance.** Both were
  measurements of the same population; one of your models is wrong and you have
  been handed the case that proves it.
- **Quote the artifact number, not the derived one**, and say which is which.
  "37 fewer instructions in the binary" survives review; "261 sites, inferred"
  does not, and should not.
- **`code=NNNNB` from the compiler's own success line beats `stat -c%s`** for
  anything about code size — the file carries data, bss and headers too.

## When success and a failure produce the same output, the output is not evidence

The entries above are each an instance; this is the shape they share, written
once. It is the most expensive family in this repo's history because every
member of it *reads as a pass*, so nobody looks.

The canonical case is already in `CLAUDE.md`: in a tree seeded with a copied-in
binary, `make compiler/pascal26` prints `make: 'compiler/pascal26' is up to
date` and exits 0. A verified fixedpoint also exits 0. **No fixedpoint was
proved and nothing says so** — the absence of `converged after N round(s)` is
the only tell, and an absence is precisely what a reader does not notice.

Four more from a single day, all different mechanisms, all the same shape:

- **A skipped test and a passing test both printed nothing.** 39 guards in
  `lib-test`; three of them, when their dependency was missing, took a branch
  that emitted no line at all and let the rule continue. "green" meant "passed"
  for 36 of them and "was never run" for 3, in the same word.
- **A remedy already in force and a remedy that worked are indistinguishable.**
  Applying a fix and seeing the symptom gone proves nothing until you know the
  fix was not already there. The test is *"did applying it change anything"*,
  and it is answerable **before** the result exists.
- **"Still red" and "the pin has not moved" are the same red.** Under the pin
  boundary a `$(PXX_STABLE)`-gated job keeps failing after the fix lands,
  because it is not running the fixed compiler. "It is still red, so there is a
  second cause" is the natural reading and it is wrong.
- **A no-op patch and a correct component are the same measurement.** Patching a
  suspect arm and seeing byte-identical output was read as "this arm is not
  defective". It licensed only "this arm is not on *this shape's* path" — the
  arm was in fact broken, for a spelling the repro did not contain. **A
  refutation is scoped to the shape that was tested**, and the negative result
  cannot tell you which of the two it earned.

And the cheapest one, which cost a full probe cycle the same evening: a compile
whose output flag was wrong (`pascal26 x.pas -o out` — there is no `-o`; the
second positional IS the output) wrote a file literally named `-o`, exited 0,
and left last night's `out` on disk. Running it printed the pre-fix answer.
**"The fix does not work" and "you ran yesterday's binary" produce the same
bytes**, and the fix was correct the whole time.

> **Ask of every green: what else would produce exactly this?** If a second
> state answers, you have not measured anything yet. Do not go looking for the
> cause of a result until you have established the result is real.

**In practice:**

- **Make the two states print differently, and prefer a POSITIVE token.** Not
  "no failure line" but `converged after N round(s)`, `SKIPPED: synapse-ssl`,
  `76 sites`. A pass that is defined by an absence cannot be distinguished from
  a run that did not happen.
- **A summary line must name what it did NOT cover.** `lib-test ok (...) --
  SKIPPED: x y z (green here does NOT cover them)` is the whole fix for the
  first case, and it is three lines of `make`.
- **Name the binary, not the commit.** "The fix is in HEAD" and "the fix is in
  the binary I just ran" are different claims and only the second is evidence.
  `git merge-base --is-ancestor` answers the first while you execute a stale
  artifact. Check the sha of the thing that ran.
- **Confirm the intervention took before reading the result.** The compiler sha
  changed; the toggle is present in the file; the flag reached the process. A
  probe that never fired and a probe that fired and found nothing both print
  nothing.
- **A regression test nobody has watched fail is not yet a regression test.**
  Run it against the pre-fix binary. If it passes there, it does not test what
  you think, and you will never learn that from a green suite.
