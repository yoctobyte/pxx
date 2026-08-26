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

## Find your section

The sections below accumulated in the order they were learned, which is the wrong
order to read them in. Route by what you are holding:

**You have a failing thing and want the tool**
- `## Order` -- the tool per question, and the reason to reach for one at all
- ``## `perf` being blocked is not "no profiler"`` -- FPC `-pg` + gprof, read call
  counts not percentages

**A measurement or a verdict is telling you something and you are about to believe it**
- `## Two traps that produced confident wrong readings`
- `## A bisect can name the RIGHT commit and still be wrong` -- the tell is that
  the named commit looks like an improvement
- `## A number moving in the direction you hoped is not a check` -- the
  confirmation may be the symptom
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
