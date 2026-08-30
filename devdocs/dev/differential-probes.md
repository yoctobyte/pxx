# Differential probes — the bug generator

Standing harnesses that run small programs under pxx **and** under a reference
implementation, diff the output, and report divergences. They are the
most productive bug-finding method in this repo: the night of 2026-08-05, five
of seven fixed bugs came from adding case batches to two of them, including two
silent-wrong-value bugs in the backends.

This page is the **index and the shared rules**. Each script's own header is the
authority on its specifics and is worth reading before you add to it — they
record traps that cost real sessions.

## The parity probes — ours against somebody else's

**This index is not self-maintaining; enumerate before you trust it.**
`ls tools/ | grep -iE 'diff|probe|oracle|sweep'` is the population, minus the
`*_devtest.py` files (those test the tools, not the compiler). Run it before
concluding no probe exists for your question — see the audit note at the bottom
of this page for what happened the last time nobody did.

| tool | oracle | answers | lane that owns the TOOL |
| --- | --- | --- | --- |
| `tools/fpc_diff_probe.sh` | FPC stable **+ optional trunk** (`FPC=` / `FPC_TRUNK=`) | does our Pascal agree with FPC — and when it does not, is it FPC 3.2.2 that is wrong? | B |
| `tools/gcc_diff_probe.sh` | gcc's libc | does our C / crtl agree with gcc? | B |
| `tools/pydiff.py` | CPython | does NilPy agree with CPython? | N |
| `tools/lib_cross_sweep.sh` | **pxx on x86-64** | does a cross target agree with the native build? | B |
| `tools/crtl_decl_probe.sh` | — (census) | is a declared crtl function actually IMPLEMENTED, or silently binding to libc? | B |
| `tools/c_array_shape_census.py` | gcc | does every way C can *reach* an array agree with every way it can *use* one? | C |

`crtl_decl_probe` is the odd one out: it has no oracle. It answers *"is the
symbol there at all"*, which is the question **before** `gcc_diff_probe`'s
*"does it agree"*. A function can produce correct values for months while
quietly pulling in `libc.so.6` — `clock_gettime` did. `readelf -d` is the check;
that script automates it.

`lib_cross_sweep` is also not a parity probe: its oracle is **our own** x86-64
output, which `lib-test` already proves green. Anything a cross target prints
differently is a target-dependent bug.

`c_array_shape_census.py` is a **matrix**, not a corpus, and it exists for a
failure mode the others cannot reach. It crosses every way C can REACH an array
— a global ident, a local, `s.m`, `p->m`, `s.in.m`, `arr[i].m` — with everything
C can DO with one: decay stride, partial index, no-op deref, `sizeof`, pointer
difference, assignment to an `int (*)[4]`, passing to a function, load width,
and the 3-D forms. One standalone program per cell, gcc deciding each.

**Why a matrix rather than reading the code.** The routines that answer these
questions are written as an `AN_IDENT` branch beside an `AN_FIELD` branch, and
the failure mode is not a branch that *drifted* but one that was never finished.
*A search for duplicated logic cannot find the place where the logic is missing*
(frankS, 2026-08-29) — grep-for-the-sibling finds divergent copies and returns
clean when every arm is wrong together. A behavioural cell is wrong whether the
handling code is divergent **or absent**, and cannot tell the difference, which
is precisely the property needed. On its first run it found `sizeof(m[0])`
answering 4 instead of 16 on a *plain global array* — so
`memcpy(dst[1], src[1], sizeof(src[1]))` copied one element and returned — a bug
with no correct sibling arm anywhere to be noticed against.

**Report the cells that PASS.** A construct confirmed correct across all six
spellings is the only thing that stops the same ground being swept a fifth time,
and it is worth more than the failures: four of the six spellings had never been
probed at all before the census, and two same-day fixes were shown to generalise
to them unaided rather than assumed to.

**What it is blind to, and the first one bit immediately:**

- **One spelling per cell.** The harness parenthesises every `sizeof`, so its
  `sizeof` row read as one universal defect when it was **two** mechanisms with
  two different wrong answers — `sizeof(m[0])` = 4 everywhere, `sizeof gs.m[0]`
  = 8 through a field. An isolated hand probe disagreed with the grid and both
  were right. **A census cell that disagrees with a hand probe is a signal to
  vary the shape, not to pick a winner.**
- **The enumeration is only as complete as your model of the language.** It is
  closed and countable in principle — defined by C, not by the codebase — but a
  construct nobody listed is invisible, and it will not tell you it is missing.
- **A wrong answer that coincides with the right one passes.** `char` rows are
  8 bytes and so is a pointer, so the char column looked correct while measuring
  entirely the wrong thing; only running `int`, `char` **and** `double` showed
  it. Two element types would have blessed it.
- **It localises nothing.** A cell names a construct and a spelling, never a
  routine. That is the price of asking about behaviour, and the reason it pairs
  with a grep rather than replacing one.
- **Every cell is a MULTI-dimensional array.** Rank 1 is not measured at all,
  so a change that is correct for rows and wrong for `int v[8]` reads clean.
  This is not hypothetical: during
  `refactor-c-one-array-shape-reader-instead-of-four-ident-field-pairs` the
  obvious tidy-up — routing `CNodeDecaysToPointer` through the same shape
  reader as its four siblings — would have broken every 1-D field decay in the
  C frontend, and the grid would have stayed green through it. The reader was
  spared by reading it, not by measuring it.
- **A string literal is a seventh spelling, and there isn't a column for it.**
  The six spellings are all ways of naming an array *object*; `"abc"` decays
  too. So a clean grid says nothing about
  `refactor-c-string-literal-decay-belongs-at-the-producer`, however much it
  looks like it should. This is the previous bullet's abstract warning arriving
  as a specific one — which is the only form it is useful in.
- **Native x86-64 at the default `-O` only**, and gcc is the judge, so anything
  C leaves implementation-defined or undefined is not adjudicated.

## Self-differential probes — pxx against pxx under a changed condition

These have no external oracle. Their reference is **our own output under a
different setting**, which makes them the right instrument for a class the
parity probes are slow to reach: an optimisation that changes behaviour has no
FPC or gcc to disagree with, because the reference implementation was never
asked the same question.

**They also inherit the blind spot in full, and harder** — see *AGREEMENT IS NOT
EVIDENCE* below. Both arms here are not merely pxx, they are pxx built from the
*same source*, differing only in a flag. A defect that does not depend on that
flag makes both sides wrong identically and the probe is green. `-O0` and `-O3`
agreeing tells you the `-O` axis is sound; it tells you nothing whatever about
whether the answer is right.

| tool | the two sides | answers | run it |
| --- | --- | --- | --- |
| `tools/selfcompile_odiff.sh` | the compiler built at `-O0` / `-O1` / `-O2` / `-O3` | do the resulting compilers **emit identical bytes**? | `make test-selfcompile-odiff` (~200s), or the script directly |
| `tools/optdiff.sh` | every standalone-runnable test program, at each `-O` level | same stdout+stderr and exit code at every level? A DIFF is the **silent-miscompile class**, the highest severity Track T can detect | `testmgr --tier opt`; `--shard i/N` to split |

**`selfcompile_odiff.sh` closes the hole CLAUDE.md names in its own claims
section**, and its header quotes that section verbatim as its reason for
existing: the self-host fixedpoint proves byte-identity **at one optimisation
level**, and *"a `-O0`-only self-compile failure passed the entire gate on
2026-08-19 and was found by a benchmark."* If you are about to lean on "it passes
the self-host gate", this is the probe that says how far that claim reaches.

## Library-specific probes

| tool | oracle | answers | lane |
| --- | --- | --- | --- |
| `tools/libm_diff_sweep.c` | glibc's libm | do crtl's `exp`/`log`/`pow`/`cbrt` agree with glibc? | B |
| `tools/reportlab_diff.py` | **real** reportlab | does `lib/pcl`'s reportlab mimic put glyphs in the same place? Compares extracted text + per-word bounding boxes via `pdftotext -bbox`, deliberately **not** byte-identical PDFs | B |
| `tools/gen_arch_probe.py` | — (environment check) | does the QEMU user-mode environment actually **execute** foreign code? An emulator can be installed yet broken by binfmt; `--version` proves nothing | T |

**Read `libm_diff_sweep.c`'s header before filing anything from it.** crtl's
`exp`/`log`/`pow`/`cbrt` are correctly rounded and **glibc is not** — its
documented >0.5-ulp bounds misround roughly 6e-4 of random args for `exp`, 1e-4
for `log`, 9e-4 for `pow` and **~55% for `cbrt`**. A nonzero diff count is the
expected result, not a bug report: judge each diff against a high-precision
reference (Python `decimal`, 80+ digits) first. In the 2026-07 sweeps every diff
was glibc's.

**Fuzzers** (`tools/fuzz.sh`, `tools/pasmith*.py`, Csmith via
`tools/csmith_fuzz.py`) are the same idea with a generated corpus instead of a
curated one, and they belong to Track T — see `devdocs/dev/track-t.md`.

**`PXXDBG=a.poisonslot` is a fifth shape and is documented in the playbook, not
here**, because it has no external oracle at all: it compares a program against
*itself* under a deliberate perturbation. Where the four above ask "does our
answer match theirs", it asks **"does anything still READ this storage"** — the
question you hit when an optimisation wants to stop maintaining something and
the blocker is an audit with no completion criterion rather than a wrong value.
It poisons the storage so a surviving reader returns garbage instead of a
plausible value. Full note, including the rule that the probe must call the same
predicate as the change it is testing, in `devdocs/dev/debugging-playbook.md`.

## The rules every one of these shares

These are not style preferences. Each was learned by chasing a phantom.

**1. When the ORACLE looks wrong, it is the harness.** gcc segfaulting, FPC
printing garbage, CPython raising — none of those is a pxx bug. Check that
first; it is always quick.

**1b. An oracle can be RIGHT and still be OLD.** Rule 1 catches an oracle that
looks broken. This is the one that does not look broken at all: `fpc` on this box
is **3.2.2, released 2021**, so every FPC-parity verdict is "pxx vs a four-year-old
FPC", and a bug upstream has since fixed is indistinguishable from one of ours.
Twice that produced a false *"pxx diverges from FPC"* — once costing a Track U
decide ticket, a `DELIBERATE DIVERGENCE` comment on a test that was not one, and
a nearly-filed upstream report against an already-fixed bug.

`fpc_diff_probe.sh` now takes `FPC=` and `FPC_TRUNK=` (each may carry flags — a
freshly built trunk compiler needs `-Fu<its own RTL>`), and consults trunk **on
divergences only**, never across the corpus. It reports what outputs can actually
settle:

| the two FPCs | pxx matches | verdict |
| --- | --- | --- |
| agree | neither | `DIFF` — a real divergence, ours to account for |
| disagree | **trunk** | `FPC-STABLE-BUG` — fixed upstream; **not** our divergence, does not fail the run |
| disagree | neither | `3-WAY` — the reference moved and we match neither side |
| trunk cannot build it | — | `DIFF` + *"trunk cast no vote"* — never silence |

Two things it deliberately does not claim. *"pxx is wrong"* and *"FPC is wrong in
both versions"* are the **same observation** wearing different labels — pxx
differs from two FPCs that agree — and no output can separate them; a human does.
And when pxx and stable already agree, trunk is never consulted, so an upstream
behaviour change we both predate is **structurally invisible** to the cheap
design. A clean run means *"no divergence from stable, and what we found is
classified"* — never *"we agree with trunk"*.

Build recipe for a trunk oracle: `feature-t-fpc-probe-needs-a-trunk-oracle`. Two
traps encoded there — `make -C rtl FPC=<new>` silently builds the RTL with the
*installed* compiler (it wants `PP=`, and the only symptom is `PPU Invalid
Version` at use time), and remote tips must be read with `%cd`, not `%ad`.

**2. Never read a side effect in the argument list of the call that causes it.**

```c
printf("%d [%s]", fread(b, 1, n, f), b);      /* WRONG */
```

Argument evaluation order is unspecified, gcc goes right-to-left, and **pxx
orders arguments differently on arm32/aarch64 than on x86-64** — all legal. This
shape produced four separate phantom bug reports in one session. Sequence the
call, then print.

**3. A skip is not a pass.** A case the oracle cannot build compared nothing.
Both shell probes count and print skips for exactly this reason: one missing
`uses` silently disarmed two exception cases for months while looking like
coverage.

**4. Read the summary line, not the DIFF lines.** `grep -v '\[known\]'` has twice
produced a confident "0 new" while the summary said otherwise.

**5. Never edit a probe by slicing between markers.** A Python slice-edit once
deleted a block of cases; the tell was the run reporting 1 known where it had
reported 13. Append at the summary anchor.

**6. Compare FULL outputs when A/B-ing a sweep.** Two traps, both hit on
2026-08-05: a baseline built from `tail -25` of a 37-line report read as a huge
regression, and `comm -23` against a run that was killed part-way reports every
*unreached* test as "fixed". Restrict the comparison to the range actually
covered, or re-run.

**7. Network and thread tests under qemu flake.** `lib_platform_esp`,
`lib_sockets` and `lib_net_v6only` each flip verdict run-to-run with the *same*
compiler. Before believing one, re-run it with the pinned stable AND your build
— see `bug-t-three-network-tests-flake-and-cost-real-debugging-time`.

## Tags

A case that diverges for a filed, understood reason is tagged so a clean run
shows only NEW findings:

| tag | meaning |
| --- | --- |
| `known` | a filed divergence. Keep the case — it starts reporting again the day it is fixed, and the semantics stay under test meanwhile |
| `lp64` (gcc probe) | output legitimately depends on the data model (`long` width); not judged under `--target` |
| `charsign` (gcc probe) | output depends on whether plain `char` is signed — it is on x86-64, unsigned under the ARM PCS. Not a divergence |

**A `known` tag can hide a second bug behind the first.** `thread-critical-section`
was tagged for a compile failure; when that was fixed the case ran and exposed
`TCriticalSection` being a no-op stub — silent lost updates. When you fix the
reason for a tag, *untag and re-run* before assuming the case is now green.

## Adding a case

Ten seconds, and it is the whole point of the harnesses:

```sh
probe <name> [known|lp64|charsign] <<'P'
uses SysUtils;
begin
  writeln(Format('%n', [1234567.5]));
end.
P
```

The shell probes prepend the program header, build both sides, diff, and count.
Pick an area nobody has covered and write ten cases — that is what found the
aarch64 comparison bug (integer promotion), the 32-bit virtual-call bug (via the
cross sweep) and the whole threading batch.

Areas with no coverage as of 2026-08-05: `Currency` beyond arithmetic, variant
records, `array of const` past the basics, class helpers (blocked on the
parser), and on the C side `volatile` / `restrict` / bitfields-in-unions.

## Whose bug is it

**The probe owns the TOOL, never the bug** — the same rule Track T runs on. A
finding is filed into the lane that owns the code: IR/codegen/backends → A,
Pascal dialect → P, RTL/crtl → B, NilPy → N, C frontend → C. Tonight's batch
produced tickets in A, P and B from two B-owned probes, which is the normal
outcome and not a sign the lanes are wrong.

## Where else these are mentioned

`devdocs/dev/debugging-playbook.md` (step 1 — which tool, in which order) and
the tool table in `CLAUDE.md`. Ticket write-ups cite them constantly; those are
history, not instructions — this page and the script headers are the live docs.

## Hygiene: a differential that overwrites one of its own arms LIES TO YOU

Recorded 2026-08-17, Track A, while chasing the Synapse TLS crash.

The FPC control was built as `sslprobe` — **the same output name as the pxx
binary**. The next three `LD_PRELOAD` experiments then "proved" that preloading
libcrypto fixed the crash. They were running the FPC build.

The failure mode is worse than a wasted hour: **it reads as a discovery.** The
experiment produces a clean, consistent, repeatable result that points somewhere
plausible and wrong, and nothing about the output says which binary produced it.

**Rule: distinct output names from the very first command**, e.g. `probe.pxx` and
`probe.fpc`, never a bare shared name you intend to rebuild. If a probe script
takes an oracle flag, make it name the artefact after the oracle.

Same family as "to count how many times something ran, the observable must live
outside the thing being counted" — in a differential, the evidence must sit
outside the arm being varied. See also the standing rule that any reported result
names the sha of the binary it came from.

**Adjacent Pascal trap from the same session:** a brace comment does **not** nest,
so `{$MODE DELPHI}` written inside `{ ... }` as documentation is a **live
directive**. Documenting a mode table in a `.pas` comment will change the mode or
fail the parse. Use a spelling the preprocessor cannot read.

## A probe that FORMATS its output can answer a different question than you asked

Recorded 2026-08-17, Track B, twice in one night by the same session.

A boundary table was built by a probe piping each case through `head -1`. On the
rows where the module-level statement was a `print`, **the print's own output was
the first line** — so what got recorded as "the attribute reads correctly" was
really "the print ran". The attribute value was never in the captured output at
all.

The framing that makes it memorable: **those rows were not mismeasured, they were
unmeasured and labelled.** A mismeasurement is a wrong number; this produced a
number that was never about the subject, and the table looked complete.

Earlier the same night, the same lane's corpus scan died on strict UTF-8 decoding
because a diagnostic can echo a source line and the corpora carry non-UTF-8 bytes —
a scan that stops at the first odd byte is also its own artefact. Fixed with
`errors="replace"`.

**Rule: the capture step is part of the instrument.** `head`, `tail`, `grep -h`,
`| head -1`, strict decoding, and "first line of output" are all places where the
harness quietly changes the question. When a row of a boundary table surprises you,
check what the harness captured before checking what the compiler did — and prefer
labelled output (`K.A 7 J.A 0`) over positional output, so a shifted line cannot
masquerade as a value.

Related: `grep -h` suppresses filenames, which silently defeats a downstream
`grep -v /tests/` filter — same lane, same night, different pipe.

## The blind spot every pxx-vs-pxx arm shares: AGREEMENT IS NOT EVIDENCE

`lib_cross_sweep` and `fuzz.sh` differ from the other probes in one structural
way: **both arms are pxx.** The section above states the sound half —
*"anything a cross target prints differently is a target-dependent bug"* — and
the converse is the half that misleads, because it is the one a reader supplies
themselves:

> **When two arms share an upstream, their AGREEMENT carries no information
> about that upstream.** A defect in the shared frontend, the shared AST or the
> shared IR makes both sides wrong *identically*, and a differential whose two
> arms are wrong in the same way is green.

Measured instance, 2026-08-28: a set-membership item constant is funnelled
`Int64 → Integer → Int64` through one `var` line in the Pascal parser, so
`1 in [4294967297]` evaluates TRUE **on every target** — x86-64, i386, arm32,
aarch64 and wasm32 alike (`bug-p-set-membership-item-constant-truncated-to-32-bits`).
No cross-target diff can see it. The sibling bug found in the same session —
i386 and arm32 truncating the *test value* — **is** a cross-target divergence and
a diff finds it immediately
(`bug-a-set-membership-truncates-the-test-value-on-32-bit-backends`). Same
feature, same hour, one visible to the method and one invisible to it.

The tools are not mis-named: `fuzz.sh` calls itself an **IR** correctness fuzzer
and that scope is honest. The failure mode is in the reading — taking a green
cross-target sweep as coverage of *the compiler* rather than of *the part below
the frontend*.

### …and when it goes RED, it does not say WHICH ARM is wrong

The paragraphs above are about a green. The complement bites harder, because a
red *feels* like an answer:

> **A self-differential's reference is not an oracle.** Naming one arm "the
> oracle" is a **role assignment, not a measurement** — and the role goes to
> whichever arm was written first. When the two arms disagree, *which one is
> wrong* is precisely the question a two-arm comparison cannot answer.

The cross-target suites compare each cross build against the **x86-64 build**.
So the x86-64 side cannot be wrong *by construction* — it is the reference —
and any divergence is reported as the cross target's fault.

**Measured, 2026-08-30.** After the hidden-temp alignment fix let
`test_cross_float` run on xtensa at all, it still diverged, and the write-up
that nearly went into the ticket read *"xtensa diverges from the x86-64
oracle"* — true-sounding, publishable, and **backwards on two of three rows**.
Putting FPC beside both reversed it:

| expression | FPC | x86-64 | xtensa |
| --- | --- | --- | --- |
| `s1+s2` (Single op Single) | Single | **Double** | Single |
| `i * s1` | Single | **Double** | Single |
| `i / 2` | Double | Double | **Single** |

Both targets pick float widths for `Write` that FPC does not, in **opposite
directions on different lines**
(`bug-a-write-picks-a-different-float-width-per-target-and-both-disagree-with-fpc`).
The x86-64 half had been reachable on every run of the suite since the test was
written, and was invisible to it for the whole of that time.

**A second instance, and it is the stronger one, because the reference arm was
wrong for a documented stretch of time rather than for one measurement.**
`Int()` of a large double was broken on the 32-bit targets *and* on x86-64, in
different ways, and the two halves were fixed months apart:

| | i386 / arm32 | x86-64 |
| --- | --- | --- |
| `Int(1.0e300)` | saturated to 32 bits | `INT64_MIN` |
| fixed in | [[bug-a-int-of-a-large-double-saturates-to-32-bit-on-i386-and-arm32]] | [[bug-a-int-of-a-large-double-is-int64-min-on-x86-64]], later |

The second ticket states the window in its own summary: *"the i386/arm32 half of
this was fixed under [the other]; **x86-64 was never in scope and is still
wrong**."* So there was a real period in which the **cross targets were correct
and the reference was not** — and a cross-target red in that window, read by the
rule above, would have been attributed exactly backwards. Note also that the
x86-64 defect was found by **Track B, from a library**, not by the cross sweep
that ran over it the whole time.

**So: a red self-differential is a signal to add a THIRD arm, not to blame the
non-reference side.** For a Pascal cross-target red, FPC is that arm and it is
one `fpc -o` away; for C it is gcc. Reach for it *before* writing a cause into
a ticket, not after — the wrong attribution is cheap to publish and expensive
to retract, and it points the next agent at the innocent backend.

**One more, from the same measurement: vary the SHAPE before you trust an
isolated probe.** `WriteLn(s)` for a plain `s: Single` agrees across FPC,
x86-64 and xtensa, so the first probe reached for reported everything fine. The
divergence needs the **expression** (`s1+s2`, `i*s1`), not the type. An
isolated probe that clears a construct has cleared *that spelling of it*, which
is the same lesson the array-shape census learned from its parenthesised
`sizeof` row — and it is why *a cell that disagrees with a hand probe is a
signal to vary the shape, not to pick a winner*.

**And the same test applies to how you VERIFY, not just to what you run.** Two checking
methods can share an upstream as easily as two test arms:

> **GREP AND READ ARE NOT INDEPENDENT — they share the FILE as their population.**

Measured 2026-08-28: four `test/wasm/` checks were recorded as having "exactly one assertion
each", confirmed by grepping the check file and by reading it. Both were wrong the same way —
each check *also* prints a line emitted by the shared `wat_oracle.sh` helper, which is not in
the check file at all. A grep of the file misses it, and reading the file agrees with the grep,
so two methods corroborated each other into a confident wrong count. It surfaced only when the
annotated check printed both lines together, i.e. from the **output**, which was the one
population that contained the answer.

Before calling something double-checked, ask what the two checks READ, not how different they
feel.

**So: before trusting a green pxx-vs-pxx run, name what the two arms share, and
treat everything above that line as untested by it.** For anything at or above
the frontend the oracle has to be foreign — FPC, gcc, CPython — which is
precisely what the four probes at the top of this file are for.


---

## Audit note, 2026-08-30 (frankD), measured at `9899bf1ab`

This page opened *"Four standing harnesses"* over a table of **five**, and
listed **six** of the ten probe-shaped tools in `tools/`. The four it omitted are
now above. What makes the omission worth recording rather than just fixing:

- **`selfcompile_odiff.sh` was built specifically to close a hole CLAUDE.md
  documents, quotes that hole in its own header, is wired into the Makefile and
  scheduled by testmgr — and was not in the index the fleet reads to find
  probes.** A tool being in CI does not answer *"is there already a probe for
  this?"*, which is the question this page exists to answer.
- **`libm_diff_sweep.c`'s absence had a sharper edge than the others.** Its
  header carries the warning that a nonzero diff against glibc is *expected*
  because crtl is correctly rounded and glibc is not. An index that omits the
  tool also omits the warning, and the failure mode is not a missing check — it
  is a **confidently filed bug against correct code**.

The generalisable part: **a count in a prose header is a claim that goes stale in
silence, because nothing re-derives it.** *"Four standing harnesses"* was true
when written and the table under it had already grown to five without anyone
noticing the sentence above it. That is why the enumeration command now sits at
the top of this page instead of a number — the same substitution CLAUDE.md's
claims section makes for the two byte-identicals, applied to an index.

### Two lanes found this page stale within the same hour, independently

Worth recording as evidence rather than coincidence. On 2026-08-30 Track D hit
this page on a dispatched audit of the live references and found it listing six
of ten probes; **Track C hit it within the hour from the opposite direction**,
while adding its own census probe, and found the heading miscounting the table
directly beneath it. Neither knew the other was here.

**A defect two lanes rediscover independently in sixty minutes is a measurement
of the seam, not a fluke.** An index nobody can trust gets re-derived by whoever
needs it, and the re-derivation is invisible — it looks like ordinary work. The
cost is not the wrong number; it is every agent that quietly does the
enumeration itself and throws the result away.

Which is also the argument for the line at the top of this page. A corrected
count would have been true on 2026-08-30 and stale at the next probe; the
enumeration command makes the count **unnecessary** rather than **correct**, and
only one of those survives the next tool landing.
