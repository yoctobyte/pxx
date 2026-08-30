---
track: T
prio: 40
type: chore
blocked-by: []
summary: "A test expectation CAPTURED from a program's output records whatever the compiler did that day — bugs included — and then defends that behaviour after the fix, converting a defect into a requirement. Audit the Makefile's expect_same.sh values for which are DERIVABLE from the source independently and which are transcriptions of a run. test_alloca26 is the model of the safe form: 7088718 is reproducible by anyone, in any language, without running our compiler. File ownership is Track B where Makefile expectations are touched."
status: done
owner: frankB
---

# Which test expectations were captured from output rather than derived?

- **Type:** chore (test-infrastructure audit) — **Track T**, with **Track B**
  file-ownership wherever `Makefile` expectations are actually edited.
- **Filed:** 2026-08-30 by frankB, out of
  [[audit-b-no-test-expectation-was-frozen-by-the-silent-pchar-alias-arm]],
  which answered the narrow version of this question and left the general one open.

## The mechanism

Most expectations here have the shape

```make
tools/expect_same.sh <name> "$$($(TESTTMP)/<prog>)" "<value>"
```

and `<value>` can arrive two ways. Either it was **derived** — computed from the
source, from a spec, or from an oracle — or it was **captured**: someone ran the
program, looked at what came out, and pasted it in.

A captured expectation records **whatever the compiler did on the day it was
written, bugs included.** That is not a dormant risk; it inverts the test. After
the bug is fixed, the test goes red, and the red points at the *fix*. The
suite has converted a defect into a requirement, and the natural reading of that
failure — "the change broke something" — is exactly backwards.

This is the same class the fleet has been finding all night in other registers:
an instrument that agrees with itself, a claim with nothing under it, a status
read off the wrong command. Here the instrument is the expectation, and it agrees
with itself because it was copied from the thing it is meant to check.

## Why it is worth a ticket rather than a note

The narrow audit that produced this found the silent `PChar`-alias arm had
frozen **nothing** — but only because the construct that triggers it is used in
exactly one place in the repo, and that place postdates the fix. That is luck
about one defect's blast radius, not a property of the suite. Every silent
wrong-value bug we fix from here has the same second-order hazard, and there is
currently no way to answer "which expectations could have been poisoned?" other
than reading them.

## The model of the safe form

`test_alloca26` expects `7088718` from `test/test_alloca.c`. That value is
reproducible **by anyone, in any language, without running our compiler**:
re-implementing the arithmetic in Python gives 7088718, and building the same
file with **gcc** and running it gives 7088718. Three independent sources.

That is the acceptance criterion for this audit, and it is worth more than any
individual finding it produces:

> **An expectation should be reproducible without running the implementation
> under test.**

Where that is achievable it removes the failure mode completely rather than
mitigating it. Where it is not — output whose only definition is "what our
compiler prints" — the expectation should *say so*, so a future reader knows it
is a transcript and treats a diff against it accordingly.

## Suggested method, and the trap in it

Read and judge; do not grep for a pattern. The narrow audit's own first pass is
the warning: searching for "pointer aliases" matched **180** declarations, of
which **8** were the construct that could carry the bug — `PRec = ^TRec` *defines*
a pointer type while `LocalPC = PChar` *aliases* one and inherits the element
type. A search term can name a syntactic shape while the defect lives in a
semantic distinction that shape does not carry, and the cost is not a miss, it
is 172 false positives — a real hit buried in that many near-identical lines gets
skimmed, and a negative result off that surface would have looked thorough and
been worthless.

Sensible ordering, cheapest signal first:

1. Values that are **self-evidently derived** — a factorial, a documented
   constant, a string the source assigns two lines above. Cheap to clear.
2. Values that are **bare large integers** or long opaque strings — the shape a
   transcription takes. The narrow audit judged all four such integers in the
   Makefile today and they were clean, so this is a small set.
3. Values whose expectation and program were **added in the same commit as a
   compiler fix** — most likely to have been read off the new behaviour.
4. Whatever remains: read it.

## Acceptance

Not "every expectation is derived" — some legitimately cannot be. Rather:

- each expectation is classifiable as derived or captured, and the captured ones
  are **marked as such** where they sit;
- any expectation found to encode a *wrong* value is fixed, and the ticket says
  which defect froze it;
- the convention is written down somewhere a future test author will meet it.

## Scope note

This does not gate anything and nothing is known to be broken. It is
prophylactic work on the suite's trustworthiness, priced accordingly — but the
mechanism is real and has already been demonstrated once in miniature, which is
why it is a ticket and not a paragraph in a message.


## Progress 2026-08-30 (frankB) — the NilPy population is DONE and self-enforcing

The audit has an instrument and one population is closed. Recording what is
settled, what it cost, and exactly what is left, because the remaining work needs
a different oracle rather than more of the same reading.

### The strong result: 342 of 353 NilPy expectations are DERIVED, proven

A NilPy test is a Python program, so CPython can run it. That turns this audit's
question from a heuristic into a measurement for the whole `.npy` population:
run each test under CPython and compare byte for byte against its `.expected`.
An expectation CPython reproduces **is** reproducible without running the
implementation under test, which is this ticket's criterion exactly.

```
NilPy expectations with a CPython oracle: 353
  DERIVED  (CPython reproduces the .expected) : 342
  transcripts (cannot be confirmed)           : 11
```

**Only one of the 353 actually disagrees with the oracle**, and it is not a
frozen compiler bug: `test_nilpy_math_domain_errors` holds the older generic
`ValueError: math domain error`, while CPython 3.12+ emits per-function wording
(`expected a positive input`). That is an error-MESSAGE difference, which
CLAUDE.md's compat table defers explicitly — *"our diagnostic/message/error
number differs → defer"* — and no working program changes behaviour on it. So it
is **labelled, not fixed**, which is the disposition this ticket asked for.

The other ten cannot run under CPython at all: four use syntax NilPy accepts and
CPython rejects (a language feature under the N charter, since upward
compatibility runs one way only), three need companion modules that exist only
under our import resolution, two read stdin, and one pins our behaviour where
CPython raises mid-iteration.

### The labelling is enforced, not asserted

`test/nilpy_transcripts.txt` lists all eleven with a reason each, and
`tools/expect_audit.py --oracle` enforces it **in both directions**: a test that
stops agreeing and is not listed is reported as a NEW TRANSCRIPT; an entry that
starts agreeing is reported as STALE; an entry naming a test that no longer
exists is reported too. Exit 1 on any drift, so it can gate.

**Verified that it actually enforces** — an enforcement tool that does not
enforce is precisely the failure class this ticket is about. Dropped a real entry
and added a bogus one in a single run:

```
NEW TRANSCRIPT (not in test/nilpy_transcripts.txt): test_nilpy_package_imports
REGISTRY NAMES A TEST THAT NO LONGER EXISTS: test_nilpy_no_such_test_at_all
registry: OUT OF SYNC
exit=1
```

Registry restored byte-identical afterwards.

### The triage instrument, for the populations with no oracle

`tools/expect_audit.py` (no flags) classifies the Makefile's inline expectations
by a mechanical signal: **does the expected text appear literally in the test's
own source?** A test printing `writeln('looped 3')` checked against `looped 3`
is derivable by inspection; a value appearing nowhere in its source is a
*computed* result, and computed results are where capture happens.

```
Makefile expectations parsed: 3063 of 3101 mentions (98.8%)
  low  (derivable by inspection) 1716
  med                             542
  HIGH (computed)                 805
.expected files: 477 — low 260, med 178, HIGH 25, no sibling source 14
```

It is a ranked reading list, not a verdict: it cannot know that
`15511210043330985984000000` is 25!, and it flags it. The point is to spend
judgement where capture is possible at all.

The 38 unparsed are 35 line-continuations, 2 non-calls and 1 line with a
trailing comment — stated because a coverage claim with an unstated remainder is
the shape this ticket exists to distrust.

### Two things NOT filed, because checking beat filing

- **Unwired `.expected` files.** The classifier reported 24 named nowhere in the
  Makefile, which looked like dead weight. Sixteen are corpus fixtures driven by
  `tools/run_fgl_corpus.sh` and friends, and `tools/check_test_wiring.py` — which
  already exists and already gates this — reports the whole tree clean. My
  "unwired" test was Makefile-only and would have filed a finding an existing
  tool already covers.
- **It did flag a file of mine**, though: `test/lib_mimic_xml_dom_minidom.npy`,
  banked earlier today and deliberately not wired because the shim it tests hangs
  the compiler. Registered in `test/UNWIRED.txt` with the reason and the
  condition for wiring it. The gate is clean again.

### What is left, and why it needs a different instrument

The Pascal and C populations have no oracle wired into this tool. The probes
exist — `tools/fpc_diff_probe.sh` and `tools/gcc_diff_probe.sh` — so the same
strong check is available in principle, but only for the subset that compiles
under FPC/gcc, which for pxx-dialect tests is a minority. So the remaining work
is: extend `--oracle` to the C corpus (where gcc is a genuine oracle for most of
it), and hand-judge the Pascal HIGH bucket, which the literal-overlap ranking has
already ordered.

Returned to `unfinished/` rather than held in `working/`: one population is
closed and enforced, the next needs a different oracle, and nothing is
half-applied.


## Progress 2026-08-30, later — the C population is done too, with gcc as the oracle

`tools/expect_audit.py --oracle-c`:

```
C expectations tied to exactly one gcc-buildable binary: 395 rows, 362 binaries built of 395
  DERIVED (gcc reproduces it)          333
  no oracle: gcc rejects the source     33
  no oracle: cross-target row           29
  DISAGREES WITH GCC                     0
```

**Zero disagreements.** Every C expectation that gcc can be made to answer is
reproduced by gcc, so the same conclusion as the NilPy population holds here:
these are derived, not captured. The 62 without an oracle are counted rather
than judged — 33 sources use pxx C extensions gcc rejects, and 29 are
cross-target rows through `tools/run_target.sh`, where qemu correctly refuses a
natively-built ELF.

### The instrument does NOT reimplement the comparison, and that was earned

The first version did, and reported **321 of 362 expectations disagreeing**. A
321/362 disagreement rate is not a finding, it is a broken harness, and it was:
those rows have the shape

```make
$(TESTTMP)/prog; tools/expect_same.sh prog-rc "$$?" "89"
```

where the assertion is the **exit code of a binary the reimplementation never
ran** — so it compared 0 against 89, every time, and would have "found" 321
poisoned expectations.

The fix removes the class rather than patching it: run the Makefile's own recipe
line, with `tools/expect_same.sh` doing the comparing, against a `TESTTMP`
populated with gcc-built binaries instead of pxx-built ones. There is no second
implementation of the semantics left to get wrong. Same lesson as the earlier
association bug in this session, where tying an expectation to a source *by
proximity* attributed 105 unrelated rows to one file; keying on the binary the
expectation actually names fixed it.

Worth stating plainly because it is the trap this whole ticket is about: **an
audit instrument that is wrong produces confident findings, not obvious
errors.** Both times the tell was a number too large to be true — 321 of 362
expectations poisoned, one file owning 105 assertions — and not any error
message.

### Where the audit now stands

| population | oracle | result |
| --- | --- | --- |
| NilPy `.npy` + `.expected` | CPython | **342/353 derived**, 11 labelled + enforced |
| C, native rows | gcc | **333/333 derived**, 0 disagreements |
| C, no oracle | — | 62 counted (33 gcc-rejects, 29 cross-target) |
| Pascal | none wired | **open** — ranked by literal-overlap, needs hand-judging |

Two of the three big populations are answered by measurement, and neither
contains a captured-and-wrong expectation. What remains is Pascal, which has no
oracle for the dialect-specific majority and is the part that genuinely needs
reading. The triage ranking is already built for it.


## Progress 2026-08-30, third pass — FPC as a partial oracle for Pascal

The Pascal population was written up above as having *no* oracle. That was true
of the dialect-specific majority and **false of whatever subset FPC can
compile**, which was simply unmeasured — the same blind spot as the other two
populations, in the same shape: the artefact's purpose is to test *our*
compiler, so whether an independent implementation can run it is not what
anyone is thinking about.

`tools/expect_audit.py --oracle-pas`, full run:

```
Pascal expectations tied to one .pas-built binary: 1277 rows,
                                     fpc built 846 of 1212 binaries
  DERIVED (fpc reproduces it)            784
  no oracle: fpc cannot build it         380
  candidate: fpc differs (read it)        69
  no oracle: cross-target row             44
```

**784 answered by measurement**, and the reading queue drops from ~1277 to 69.

### This oracle is weaker than the other two, and the tool says so

CPython **is** the definition of what a `.npy` should do, and gcc **is** the
definition for portable C — a disagreement there is a finding. FPC is only the
reference for the subset of the dialect pxx shares with it, and CLAUDE.md's
compat table is explicit that accepting a form FPC rejects is *not a defect* and
a differing diagnostic is *deferred*. So the verdicts are deliberately asymmetric:

- **FPC reproduces it → DERIVED.** Sound in that direction: an independent
  implementation produced the value.
- **FPC differs → proves nothing on its own.** It is a *candidate*: either a
  deliberate dialect divergence or a captured expectation, and only reading
  tells them apart. The verdict is named `candidate: fpc differs (read it)`
  rather than `disagrees` so nobody reads the count as a defect count.

### The 69 candidates, categorised

Most are divergences by construction — the test's *subject* is a place we
deliberately differ:

| category | n |
| --- | --- |
| a mimic/strict-FPC flag is the thing under test | 9 |
| shift/width dialect semantics | 8 |
| float formatting (Track F) | 8 |
| platform / ESP defines | 4 |
| runtime-error numbers (ours by CLAUDE.md's rule) | 3 |
| our own `-O3` sweeps | 2 |
| **genuinely needs reading** | **26** |

### Worked example, so the method is not just asserted: `test_sizeof26`

Built `test/test_sizeof.pas` with FPC and diffed all 27 values. **25 of 27 agree
exactly.** The two that differ:

```
SizeOf(Variant)   pxx 16   fpc 24
SizeOf(String)    pxx  8   fpc 256
```

Both are deliberate: our `Variant` layout is smaller than FPC's `TVarData`, and
the `String` figure is the classic `{$H}` question — 8 for a managed string
reference against FPC's 256-byte `ShortString`. Neither is a captured value;
the expectation is derivable from the type widths the dialect defines, which the
test's own header sets out. **Verdict: derived.**

That is what judging one of these costs — a build, a diff, and identifying two
positions — and it is why the 26 remainder is a tractable queue rather than an
open-ended one.

### A silent cap in the audit tool, found and removed

The candidate list printed 60 rows and `... and 9 more`. **A truncated list in
an audit tool reads as "that is all of them"**, and the elided tail is exactly
the part nobody then reads — the no-silent-caps rule applied to my own
instrument. Cap removed; it now prints every candidate.

### Standing

| population | oracle | derived by measurement | left to read |
| --- | --- | --- | --- |
| NilPy | CPython | 342 / 353 | 0 — 11 labelled + enforced |
| C (native) | gcc | 333 / 333 | 0 |
| C (no oracle) | — | — | 62 counted |
| Pascal (fpc-buildable) | FPC 3.2.2 | 784 / 1277 | 69 candidates, 26 after categorising |
| Pascal (not buildable) | — | — | 424, ranked by literal-overlap |

**Across all three oracles, not one captured-and-wrong expectation has been
found.** The one disagreement anywhere is `test_nilpy_math_domain_errors`, which
is a transcript of an *older CPython*, not of one of our bugs, and is labelled
rather than fixed because the compat table defers error wording.


## The 26 read — verdicts, and the claim bounded properly

All 26 of the "needs reading" candidates were built with FPC and their
divergences inspected. **None shows the signature of capture** — a value with no
derivable justification. Every one has an identified reason:

| candidate | why FPC differs | verdict |
| --- | --- | --- |
| `test_pascal_at_procvar_d26` | `@procvar` mode semantics — the test's subject | dialect |
| `test_tsdefine_on26`, `test_tslock_on26` | pxx-only threadsafe defines; FPC sees `plain`/`no-hardlock` | pxx-only feature |
| `test_widechar_utf8_b31926`, `test_vws26` | our WideChar→UTF-8 handling vs FPC's 1-byte Char | dialect |
| `test_getinterface_guid_b25726` | `GetInterface` by GUID resolution | impl choice |
| `test_interface_containers_ts26` | interface refcount lifetime in containers | impl choice |
| `test_tcs26`, `test_syncobjs26` | our RTL's lock semantics — the test itself prints `BUG:` for the behaviour FPC shows | deliberate |
| `test_aoc_types26` | `array of const` marshalling of a float | dialect |
| `test_variant_catchable26` | *"cannot convert string to integer"* vs *"Invalid variant type cast"* | **error wording — deferred by the compat table** |
| `test_sizeofexpr26` | SizeOf of an expression: width promotion | dialect |
| `test_anontype26` | anonymous enum/subrange support | pxx extension |
| `test_freebase_compact26` | free-through-base destructor sequence | impl choice |
| `test_managed_setlength_growth26`, `test_mlrr26`, `test_freemem26` | our managed-memory accounting | our RTL |
| `test_byref_lvalue26` | the byref lvalue *rule* — the test's subject | dialect rule |
| `test_sow_default26` | `--strict-overload` widths — a pxx flag | pxx-only flag |
| `test_trsat26` | float→int **saturation**, which we define and FPC does not | deliberate |
| `test_dynlib_stub26` | expects the no-loader stub path on this host | host/config |
| `test_thread_api_no_uses26`, `test_cast_deref_varparam26`, `test_var_litcat26`, `test_aoc_xunit26` | FPC binary emitted **no content** | not a divergence — see below |
| `test_sizeof26` | `SizeOf(Variant)` 16/24, `SizeOf(String)` 8/256 | dialect (worked example above) |

### A limitation of my own instrument — and a count that moved three times

**Four** of the 26 are not divergences at all: FPC built the binary and it
**emitted no content**. That is the absence of an answer, not a disagreement,
and counting it as one overstates the candidate list. Now reported as
`no oracle: fpc built it but it produced no output`.

The number is worth its own paragraph because it moved **3 → 1 → 4** before
settling, and every move was my measuring instrument rather than the corpus:

1. **3**, read off a hand-judging script that printed only the first six diff
   lines. Rows whose `+` lines fell past the cap looked like they had none —
   the *silent-cap* failure I had fixed in the audit tool minutes earlier,
   reproduced in the throwaway script I used to check the audit tool.
2. **1**, after re-checking with a detector that asked "are there any `+`
   lines?". That contradicted the ticket, so I went to correct it — and the
   contradiction was the new detector's fault: a binary emitting a single blank
   line produces a bare `+`, which counted as output.
3. **4**, asking the question that actually matters: is there a `+` line
   carrying **non-whitespace content**? `test_cast_deref_varparam26`,
   `test_var_litcat26`, `test_aoc_xunit26`, `test_thread_api_no_uses26`.

The first correction was right to make and *arrived at a worse number than the
one it replaced*, which is the part worth keeping: a check that disagrees with a
recorded claim is not automatically the better measurement. Both the claim and
the check have to be able to say precisely what they counted, and neither of
mine could until the third attempt. **"Emitted nothing" turned out to have three
different definitions, and all the disagreement lived there** — not in the corpus,
which never changed.

Worth noting how it was found. The oracle had already "worked" through two full
runs; nothing errored, and the count was plausible. It took hand-reading the
rows to see that some of the evidence was empty. **A plausible count is not
evidence the classifier is measuring what its labels claim** — the same lesson
as the C harness, arriving from the opposite direction: there the number was too
large to be true, here it was small enough to be believed.

### The negative result, stated with its aperture inside the sentence

Not: *"no captured-and-wrong expectation exists."* The true claim is:

> **No captured-and-wrong expectation exists among the rows an oracle could
> reach — 342/353 NilPy, 333/333 native C, 784/1277 Pascal — and 424 Pascal rows
> (380 FPC cannot build, 44 cross-target) plus 62 C rows have no oracle at all,
> where such an expectation would be not merely unfound but unfindable by this
> instrument.**

The two readings are indistinguishable in any quotation of the shorter form, and
the shorter form reads as conscientious, so nobody re-checks it. The aperture has
a size and a work plan — the literal-overlap ranking already orders those 486
rows — which is what makes it a bounded absence rather than an unbounded one.

The single disagreement anywhere remains `test_nilpy_math_domain_errors`: a
transcript of an *older CPython*, not of one of our bugs. A stale oracle rather
than a defect, and fixing it would have been the error.

## The aperture, read: measured, ranked, and smaller than it was

The claim above was written with an aperture of 486 rows and a plan to rank
them. Both happened. What follows supersedes the numbers in it.

### The corrected oracle counts

| population | rows | oracle-answered | no oracle |
| --- | --- | --- | --- |
| NilPy (CPython) | 353 | 342 derived | 11, registered in `test/nilpy_transcripts.txt` |
| C (gcc) | 395 | 333 derived | 33 gcc rejects the source, 29 cross-target |
| Pascal (FPC) | 1279 | 796 derived | 368 FPC cannot build, 44 cross-target, 12 built-but-silent |

The Pascal figure was 784 before the FPC oracle was given the tests' own `-Fu`
paths; 796 is the same corpus with the companion units it always needed.
**59 Pascal rows are candidates (FPC differs) awaiting reading** — dialect
divergence in every case examined so far, but they are not yet all read, and
that is the honest remaining edge of this audit.

### What the no-oracle region actually consists of

Not an opaque 486. For the 366 Pascal sources FPC cannot build, with the reasons
grouped over **all** of them (the first grouping said 262 of 366 because the
script called `most_common(30)` — a silent cap, in the script measuring the
aperture, and it hid the *largest* structural category, not a tail of oddities):

| n | why FPC cannot build it |
| --- | --- |
| 201 | pxx dialect/semantics FPC rejects — `Identifier not found`, `Syntax error`, `Duplicate identifier`, `class type expected`, published section needs `{$M+}` |
| 145 | a pxx RTL/support unit FPC does not have — `palparallel`, `scheduler`, `palthread`, `promocore`, `cprep_lib`, `Illegal unit name: platform` |
| 14 | **recoverable** — builds once FPC gets the test's own `test/` companion paths |
| 4 | inline asm FPC will not assemble |
| 2 | links against a `.so` the test builds itself |

On the C side, **exactly 1 of 52** unbuildable sources was recoverable by a flag
(`-include alloca.h`), and that row then proved derived. So the obvious next
suggestion — *configure the oracles better* — is answered with evidence rather
than a shrug: **it buys 15 rows across both languages and then stops.** The rest
is structural. These tests exercise constructs the reference implementations do
not have, which is most of why they exist.

### The ranked reading, and why the ranking is weaker than it looks

`tools/expect_audit.py --unoracled` intersects the two instruments: rows no
oracle reaches, ranked by whether the expected text appears in the files the row
actually compiles. **Every row in the zero-overlap band is derived.** The
mechanisms are three, and none is capture:

- **arithmetic on literals in the test** — `add_two(3,4)/(10,20)/(100,1)` →
  `7 30 101`; `sum7(1..7)`, `dsum10(1.0..10.0)`, `mix9(...)` → `28 55.0 45`;
  `my_add(40,2)` → `42`; `tolower(65)` → `97`; `fact(25)` → 25! exactly;
  `f(fact(20))` → 2×20!; `4π` → `12.5664`; `len("test/hello.pas")` → `14` and
  `stat -c %s` of it → `54`, both checked.
- **the value lives in the companion the test exists to pull in** — `4242` in
  `test/chdrstatic/hdrstatic.h`, `#define MIXED_CASE_SENTINEL 77` in
  `test/MixedCaseHeader.h`.
- **a self-counting harness** — `total ok 24 / 24`, where every expected value
  sits inline beside the code producing it (`Chk('ag sum', n, 11*(3+4+5+6+7+8+9))`)
  and the expectation is only *all checks passed*. This shape cannot carry a
  captured wrong value: capturing a failing run would have recorded `23 / 24`.

**And that is the finding about the instrument, which matters more than the
verdicts.** Literal overlap asks whether the expected text appears in the source.
A *computed* expectation is absent by definition — and computing the expected
value from literals in the test is the most common legitimate shape a test
expectation takes. So **low overlap is evidence of arithmetic, not of capture**:
the two populations are not separated by the thing the heuristic measures. The
ranking is still useful — it produced a finite ordered set that resolved
completely — but "lowest overlap first" is not "most likely to be a capture", and
it was asserted before it was checked. *A ranking's discriminating power is
itself a claim and needs its own measurement*; it usually gets validated by
whether its top rows are interesting, which is exactly the reading that cannot
tell a good metric from one that merely concentrates a shape.

### The instrument defects found while doing this, because they are the result too

Four, all in the audit's own tooling, and each found by running it rather than
reading it:

1. **The overlap metric could not see the second file.** It read only the primary
   source, so multi-file tests sorted to the top — *exactly where the hypothesis
   predicted captures*. A ranking that fails randomly costs a few rows; one that
   fails by agreeing with you costs the conclusion.
2. **Half of the repair was inert.** It read `-I`/`-Fu` from the `expect_same.sh`
   line, which never carries them. Unnoticed because the *other* half fired and
   moved the band 26 → 23, which reads as success. With the compile line carried
   through: 18. **A fix with two independent parts can have one part inert and
   still move the numbers — so numbers-moved is necessary, not sufficient, and
   the size of the move must be plausible for the whole fix.**
3. **The fix landed in the wrong function.** The old text was asserted present
   inside `oracle_pas`, then replaced with `count=1` over the whole file, landing
   in `oracle_c`, which had byte-identical code. The assert and the edit were
   checking different things.
4. **Giving an oracle the subject's own include paths turns it into a mirror.**
   `lib/rtl` holds `sysutils.pas`, `math.pas`, `classes.pas`, `strings.pas`,
   `dateutils.pas`, `strutils.pas` — each shadowing the FPC unit of that name —
   and 98 compile lines carry `-Fulib/rtl`. FPC was compiling *our* RTL. For such
   a row "FPC reproduces it" is our implementation built by FPC agreeing with our
   implementation built by pxx: circular, and **in the one direction this audit
   must never be wrong, because it manufactures confirmations of the claim under
   test.** It reduced DERIVED only because our RTL does not compile cleanly under
   FPC; had it compiled, the identical defect would have read as a *stronger*
   result. The gcc mirror of the same "improvement" made gcc build 10 fewer
   sources, because a pxx include dir shadows a system header.

Both instruments are now restricted to `test/` companion directories, and the
restriction is stated twice in the code with two different justifications —
independence for the oracle, metric preservation for the overlap scan — so that
relaxing one does not read the other as redundant.

**Defect 4 was caught by direction, not inspection, and so was its gcc twin.** A
change that can only *add* include paths cannot legitimately *reduce* the number
of buildable sources, nor turn a reproduced row into a differing one. The sign of
the move was wrong before the size was interesting — and **a sign is checkable
without knowing the right answer**, which is what makes it cheaper than the
magnitude check and usable on results you have no intuition about. Inspection
would not have caught either: in both cases the code does exactly what it says.

### The claim, restated with the aperture measured rather than estimated

> **No captured-and-wrong expectation exists among the rows an oracle could
> reach — 342/353 NilPy, 333/395 C, 796/1279 Pascal — nor among the
> zero-overlap band of the rows no oracle reaches, every one of which was
> hand-judged derived. 486 rows have no oracle; of the Pascal sources behind
> them, 346 of 366 are structurally unreachable (dialect FPC rejects, or an RTL
> unit it does not have) rather than unconfigured, and better oracle
> configuration buys 15 rows across both languages before it stops. 59 Pascal
> candidate rows remain unread.**

That last sentence is the open edge, and it is deliberately inside the claim
rather than after it.

## The 58 candidates — read, and the mechanism became repetitive

These were the real open edge: rows an oracle **did** reach and **disagree**
with. Everywhere else a capture could only hide behind the *absence* of a
verdict; here it could hide behind a real one. All were read.

**None is a capture.** Every one is a divergence the test exists to exercise, in
six families:

| n | family | what FPC does instead |
| --- | --- | --- |
| 11 | a pxx directive or CLI flag FPC ignores | compiles the OTHER branch — `{$THREADSAFE}`, `--mimic-fpc`, `--strict-fpc`, mode switches |
| 12 | a pxx RTL/runtime feature FPC lacks | managed-local reuse, `GetInterface` by GUID, `TCriticalSection` semantics, dynlib stubs |
| 14 | float formatting / precision | Track F by charter — digit counts, exponent form, `WriteFloat` |
| 13 | promotion / shift-width / layout | our widening rules; `SizeOf(Variant)`=16 vs FPC's 24 |
| 2 | unicode / widechar | FPC emits `?` and replacement chars where we emit UTF-8 |
| 6 | our own `-O3` passes and nil-check directives | no FPC equivalent exists |

The families are not a taxonomy imposed afterwards; by the second half the
mechanism was predictable from the test's *name* before opening it — a name
containing `strict_fpc`, `mimic_fpc`, `managed_`, or `nil_check` announces that
divergence from FPC is the subject rather than an accident. That is where the
returns flattened.

The two strongest individual cases, because they are the ones a rubber stamp
would have missed:

- **`sweep_regcall_O3`** — a deterministic arithmetic difference, the one shape
  in the whole set that could genuinely be a wrong recorded value. We expect
  `t1=5010003`, FPC produces `6010003`. Computed by hand: `Probe3(g, BumpG(1),
  loc)` with `g=5, loc=3` under **left-to-right** argument evaluation gives
  `5·10⁶ + 10·10³ + 3 = 5010003`. FPC's value is what right-to-left produces —
  it read `g` after the bump. pxx guarantees left-to-right and the test's own
  header says so. Derived from a stated language rule, checked independently.
- **`test_sizeof26`** — `16` where FPC says `24`, and the source documents its
  own divergence in a comment: *"16 Variant (pxx's own 16-byte tagged value: 8
  tag + 8 payload; FPC's TVarData is 24 — a representation difference, not a
  bug)"*, citing `docs/types-and-targets.md` as the contract. An expectation
  that names the reference value it differs from and cites its authority is the
  shape every divergent expectation should have.

### The 59th was a harness artefact, and that is the finding

`test_unitpath_posix26` was flagged a candidate with an **empty diff** — reported
as differing, with nothing shown to differ. Built on its own, FPC prints
`posix`, exactly our expectation.

The sweep compiled all 1215 sources with **one shared `-FU` unit-output
directory**. `test/unitpath/posix/platgreet.pas` and
`test/unitpath/esp/platgreet.pas` are different units with the same basename (as
are two `mymod.pas`), so whichever compiled first left its `.ppu` there and bound
for every later row using that name. Only two basenames collide, so the count was
barely affected — but the count is not the point. **Contamination between rows of
a sweep is indistinguishable from a finding, and it points whichever way the
sweep ORDER happened to go.** A re-run in a different order would have moved the
result with nothing to say why.

Fixed with a per-binary unit directory. The re-run moved exactly one row —
797 derived (+1), 58 candidates (−1) — which is the whole predicted effect and
no more, so the fix did what it claimed and nothing else.

**What exposed it was the empty diff**, not the verdict: a row classified as
*differing* with no difference to show. The classifier could not see the
contradiction because it reports the verdict and the evidence through different
paths, so nothing ever compares them. **A verdict and its evidence that travel
separately can disagree indefinitely** — worth a guard, and cheap: assert that a
row called a difference has at least one diff line.

### Final counts

**342/353 NilPy · 333/395 C · 797/1280 Pascal**, with 58 Pascal candidates read
and every one a documented dialect divergence.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
