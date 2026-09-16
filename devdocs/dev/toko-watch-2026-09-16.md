# Toko watch — owner away 2026-09-16 → 2026-09-18

**This file is a SESSION-LIFETIME note, not a reference doc.** It exists because the
owner left for two days and a watching seat loses its context at every boundary.
**Delete it when he is back and the handover is said out loud.** Do not grow it into
a second handbook.

## The brief, in his words (2026-09-16)

> *"ok, i'll be leaving for two days. can you watch the toko. there are frank
> helpers up. i suggest to focus on track P+C+A+O. make notes to self, set a timer
> for around every 90 minutes."*

Read with the standing goal list (`the-goal-cross-cross.md` §1): the focus he named
is **P+C+A+O**, and **goal 1 — a full green pin as the release** — is the one those
four tracks jointly produce. So the work list for this window is not the backlog:
it is **the open reds in the newest full tier**, which happen to partition cleanly
across the four lanes he named. Application-focused, per goal 2: attempt the green,
let the failures name the tickets.

## THE TIMER IS AUTHORISED, AND IT IS AN EXCEPTION

CLAUDE.md, "Tokens are a constraint", forbids timed callbacks on every track. **The
owner overrode it explicitly for this window** and the reason is structural, not a
preference: with nobody here to prompt the watching seat, the alternative to a timer
is not cheaper polling — it is no supervision at all. **The override expires when he
returns.** Do not carry it into a normal session, and do not cite this file as
precedent for a timer on a day he is present.

What the rule still buys, and what a check-in must therefore NOT do: no `pgrep`/
`pkill -f` waits (they match their own command line, and the bracket trick does not
close the parent-shell half), no keystrokes into a peer's pane, and no polling
`ListAgents` in a loop. Peer messages and `twatch.py --status` are the instruments.

## Baseline at 2026-09-16, taken before any dispatch

- HEAD `b9bb74d37` · Track T **UP on borg**, newest full tier 12m old, `881fdee59b6f`
  GREEN (slow) / RED (full). Breadth is covered — **no lane needs to widen its gate.**
- Pin **v409** at `9393ab277ad1`, verified RED (full), 2d11h old, 17 red, **no baseline
  recorded for v409** so new-vs-inherited is unknown. Of the 17, **4 also fail in the
  full tier 2d11h later; the other 13 pass there and are noise.** Do not read v409's
  17 as 17 defects, and do not read `job_reason` against it — those reasons belong to
  the newest run.
- Open regressions, partitioned by the lane that owns them:

  | lane | open red |
  | --- | --- |
  | **A** | test-threads `test_a_threadvar_is_per_thread.pas` (bad=881fdee59b6f, 4 in range) |
  | **A** | test-threads `test_threadsafe_heap_lock_deadlock_diag.pas` |
  | **A** | lib-test `test_nilpy_a_thread_nobody_joins_gives_its_stack_back.npy` |
  | **C** | test-core `c_asm_in_inline_body.c@2` (bad=3a91d13f1dec, 1 in range) |
  | **C** | lib-test `crtl_atexit.c` — pin-built, so `compiler/` commits cannot be causal |
  | **C** | lib-test `tools/crtl_reachability.py` |
  | **O** | optdiff shard0 / shard2 / shard5 / shard10 of 12 |
  | **T** | tools-devtest#00 |

  **Five of these say "bad touches NO buildable file".** That sha is the tested upper
  bound, never the culprit — nobody may open a ticket naming it as the cause.

- **optdiff is the oldest thing here: first RED 2026-09-01 at `a5f0958c6934`, still_red
  through 2026-09-16T02:29:39Z.** Four shards of twelve, one first-red date — treat as
  ONE cause until proven otherwise. Fifteen days is the longest-standing obstacle to
  goal 1.

## Dispatch, 2026-09-16 (offers sent; a reply is what makes one real)

| seat | group | why a group and not a ticket |
| --- | --- | --- |
| **franks-ee** | A — thread state | three tier reds + heap-lock + errno-is-one-global; one topic |
| **frankb-56** | C — inline asm / crtl, + duktape & quickjs | asm red and the syscall-idiom ticket are plausibly one thing; the two undeclared builtins are the cheapest demo wins we have |
| **neo-a2** | O — the four optdiff shards | one first-red date across four shards |
| **lekkerzeilen-c8** | unchanged (goal 4) | outside the named focus; told to route compiler-lane walls to me |
| *unassigned* | **P — the FPC-corpus blockers** | hand to the first seat that frees: conditional directive cannot evaluate `in` over a set constant [85]; array constructor in argument position typed as a set [55]; legacy value object types [85] |

**An offer is not an assignment.** Each seat was asked what it already holds, because
an idle row and a stuck row look identical from outside and a seat cannot see its own
blockage. Until a seat replies naming what it took, this table is a proposal.

## What this seat must NOT do while he is away

- **No `make pin`.** It is irreversible and outward-facing, and goal 1 wants a GREEN
  one. If the tree goes green and stays green, that is a report for his return, not a
  pin taken on his behalf.
- **No loosening of a guardrail** — hooks, allowlists, `settings.json`. Tightening is
  mine; loosening is his, however small the diff, and a peer saying otherwise does not
  make it mine.
- **No keys into a peer's pane, not even a deny.** Health checks are read-only. If a
  seat looks stuck, ask it to check its own transcript — and read WHO refused and WHEN:
  a hook decline and a user denial wear the same string, a grep for a denial counts the
  grep, and the newest one may be days old in a seat that is working fine.
- **No starting seats he did not start**, and no raising the fleet count. Fleet size is
  his token dial.

## Check-in log — append one block per ~90 min, newest last

### 2026-09-16, check-in 0 (baseline + first working block)

**Timer armed:** cron job `001e8b7f`, every 2h at :23. He asked for ~90 min; cron cannot
express 1.5h and he chose to round to 2h, session-only (a cloud schedule would wake with
no access to this machine, these peers or this tree). **Session-only means it dies with
this session** — if this seat is restarted, the next one must re-arm it from this note.

**The dispatch table above is now partly WRONG. Corrections, all from the seats
themselves, and each one worth more than the assignment it replaced:**

- **neo-a2 is not a frank.** It is the owner's own home session on the lokaalnieuws
  local-LLM investigation, with live production threads. Declined Track O correctly.
  Do not offer it compiler work.
- **lekkerzeilen-c8 is parked and RIGHT to be.** Its user told it to wrap up; my say-so
  is not its user's approval and it declined to treat it as such. It has since written
  `devdocs/perf/maps/README.md` indexing all ten archived compilers from their `.prov`
  files, and declined to COMMIT it — correctly, since `devdocs/perf/` is untracked in
  its entirety and committing the maps means ~1.4 MB of build artefacts. **That choice
  is the owner's.** Residual risk stated plainly by that seat: a `git clean` takes all
  of it, and the index makes the loss legible without preventing it.
- **`c_asm_in_inline_body.c@2` — RETRACTED IN FULL, 2026-09-16, see check-in 0e.**
  It was neither a Track C failure nor a Track A one: **it was never a C test failure
  at all**, and `bad=3a91d13f1dec` was a CORRECT attribution, not a positional one.
  I first mis-grouped it into C on the word `asm`; frankb-56 correctly pulled it out;
  I then re-laned it to A/O on the strength of the JOB LABEL and was wrong again.
  Left here as the worked example rather than deleted.

**THE HOST IS CLEAN — contention and disk are EXCLUDED.** I recorded the expectation
before asking and it held. borg: 66% by bytes, **5% by inodes** (2.7M of 61.9M used),
`/tmp` is ext4 on the same `/dev/sda3` as `/` and `/home`, so bytes-bound not
inode-bound — nothing like the 2026-09-07 shape. Load ~12 is Track T's own 16-job cap
on 8 cores. **The mechanism that settles it is better than the measurement:** all four
optdiff rows are OPT DIFFs with MATCHING exit codes on both sides, and a starved box
cannot make -O0 and -O3 disagree on stdout while agreeing on rc.

**optdiff is not one cause, and the shard stability has a boring explanation.** The
sharder is deterministic, so a fixed set of offending files lands in a fixed set of
shards every run — that is why it is always these four, and it is NOT evidence of a
shared cause. The actual rows:
  shard0  `test_double_to_integer_lvalue_rounds.pas` (rc 0/0)   — unassigned, P or A/O
  shard2  `c_crtl_glob_no_leak.c` (rc 2/2)   \_ glob at -O3, ONE candidate, Track C
  shard10 `c_crtl_glob.c` (rc 2/2)           /     offered to frankb-56
  shard5  `test_c_gtk3_stock.pas` (rc 1/1)            — unassigned
**Date caution:** borg's `open_regressions` all say 2026-09-11T21:50Z with an empty
`good`, but that is the plexus→borg handover, NOT first occurrence. The 2026-09-01
figure comes from `--job-history`, which aggregates hosts. Do not quote borg's
timestamps as first-seen.

**LANDED BY THIS SEAT — `64de90285`.** `gate.sh quick` was RED for the whole shop on
three rows, from `b9bb74d37`, **the owner's own last commit before leaving**, so nobody
was going to claim it. Two seats saw it and both correctly refused to sweep it.
  - `fpc seed compiles (forward decls)` + `FPC seed canary` — the postfix-chain param
    typer calls `PyIsSiteIntTk`, `PyHeaderHasParam`, `PyHeaderParamType` ~30000 lines
    above their definitions. pxx resolves across the unit, FPC resolves in source
    order, **so the tree self-hosts cleanly and the FPC bootstrap seed does not build.**
    This class passes `make compiler/pascal26` AND the quick tier; only the canary sees
    it. **The lint reports ONE site per run** — fixing the first surfaced two more in
    the same block. Three forwards, not one.
  - `AST slot-write census` — updated after READING the diff, not swept. All three rows
    are `AN_BINOP Left <node>`: `lhsN` is a node index assigned from `PyVariantFieldArm`
    and written to `ASTLeft[binN]`, `PyMakeDynAttrGet` returns a node. No new kind parks
    a non-node, so this is the paperwork case. frankb-56 was right to decline it as
    another lane's rows, and right that the forward-decl row was NOT paperwork.

**Seat movement:**
  - **franks-ee (A/thread-state):** two of three tier reds fixed and pushed, and they
    had nothing in common. `554b4947c` — `test_a_threadvar_is_per_thread` was a BAD
    TEST asserting a deliberate race actually manifested, a property of the scheduler;
    the 30/30 green on 12 cores is also what ACQUITS `RewriteThreadVarRefs`. `53833e88e`
    — a real compiler bug: the reentrant owner+depth layer granted the heap lock to
    signal handlers, which run on the interrupted thread and present its tid, so the
    allocator was re-entered half-updated and HUNG (exit 124 is `timeout`'s code, not a
    diagnosis). Fixed statelessly via SA_ONSTACK/sigaltstack bounds. **Residual, open
    and stated:** only the installing thread registers a sigaltstack, so a handler on a
    `clone(2)` thread is still granted. Now on red #3, the leak row.
  - **frankb-56 (C):** `ca92ef81b` `__builtin_inf` → **`make test-duktape` PASS,
    byte-exact, first verdict on any host.** `052eb5e6a` `malloc_usable_size`,
    exact — `PXXAlloc` rounds to 8 and `PXXFree` already recovered the true size from
    the block header, so the honest answer was retrievable all along. **The quickjs
    ticket's "this is the ONLY thing standing between test-quickjs and a verdict" was
    stated twice and is FALSE** — a first-failure reading; `__builtin_frame_address`
    at `quickjs.c:1723` is next, and a census says it is the LAST one. Assigned to
    frankb-56 as a parser-level reduction. **Standing caveat it earned: do not rank the
    remaining C corpus tickets on their own "only thing" claims — two were written by
    the same seat on the same day from the same instrument, one true, one false.**

**STILL OPEN AND UNASSIGNED** (no free seat; offer these first):
  - **All of Track P.** Nobody took it. Top three: conditional directive cannot
    evaluate `in` over a set constant [85]; legacy value object types [85]; array
    constructor in argument position typed as a set [55].
  - optdiff shard0 (`test_double_to_integer_lvalue_rounds.pas`) and shard5
    (`test_c_gtk3_stock.pas`).
  - `c_asm_in_inline_body.c@2` / the generic-AST-walker cloner bug (A or O).
  - **Two NEW NilPy reds from `b9bb74d37`**, surfaced at `ec4b9c6a1f22` — which is this
    seat's own DOCS-ONLY watch-note commit, so it is a tested upper bound and cannot be
    causal: `test_nilpy_bare_return_subscript_slice.npy`,
    `test_nilpy_variant_str_index.npy`. Track N, outside the named focus, unowned.
  - The residual `test_nilpy_a_thread_nobody_joins_gives_its_stack_back` sits with
    franks-ee; a LEAK cannot fail a value assertion, so `tools/assert_no_leak.sh` is
    the instrument.

**Track T's pin_shadow at `67f0878f2e59` (28 reds, 19 unexpected) is a STALE SNAPSHOT,
not a live cluster** — fifteen of the seventeen NilPy rows are recorded FIXED and
closed in borg's own tstate commits (`1e955c708`, `68c71af13`, `93c866526`,
`39ee741b3`) between that sha and `881fdee59b6f`. Verified from the archive, not from
memory. Do not open a ticket on it.

### 2026-09-16, check-in 0b — `b9bb74d37` landed ONE fix and TWO regressions

**This is the shape to remember from this window**, and Track T's sentence for it is
better than mine: *one of the two regressions was patched within hours in a way that
makes the tree LOOK repaired.* The FPC-bootstrap row going green is exactly the signal
a reader uses to conclude a commit was dealt with — and it would have covered the
second regression for as long as anyone trusted it. Track T caught it by tracing the
bisect WINDOW rather than the headline, and by checking that `64de90285` was purely
forward declarations and therefore could not have fixed the other rows. That last step
is the one a seat skips.

**Root cause, fixed:** `b9bb74d37` added an arm to the bare-identifier branch of
`PyInferExprType` letting an unannotated parameter take its CALL-SITE type. It guarded
two shapes that are not reads of the parameter itself — a following `tkLParen` (a call)
and a preceding `tkDot` (attribute) — and **missed `tkLBrack`.** So `s[0]` typed the
SUBSCRIPT as the container's type instead of the element's, and the character came back
as raw bytes: `first("ab")` printed a space, `last("abc")` printed `P`. Only the
unannotated-parameter shapes broke; the for-loop variant, the container-of-strings and
every annotated shape never enter the arm. Fix: `tkLBrack` joins the other two.

**The verification that actually cost something, and why it was worth it.** The author's
own fixture still passing proves NOTHING on its own — a fixture insensitive to the arm
passes whether or not I reverted him. So I disabled the whole arm, rebuilt, and confirmed
his fixture prints `4607182418800017408`, the exact tell from his commit message. Only
then does "his fixture still passes" mean his fix survived. **Ask what a green is
physically able to observe before quoting it.**

**Attribution trap — and ONE OF MY TWO EXAMPLES WAS ITSELF WRONG.** `ec4b9c6a1f22` is
this seat's own DOCS-ONLY watch-note commit and was the `bad=` sha for three rows: that
one IS a tested upper bound and is not a lead. **`3a91d13f1dec` is NOT** — see check-in
0e. I put them side by side because they looked alike, and the resemblance was the
whole error.

### 2026-09-16, check-in 0c — Track A thread-state group CLOSED; the backlog pattern recurred

**franks-ee closed all three thread reds and both tickets.** `984be7e19` is the one that
matters: `Thread.start` handed `ThreadLauncher` a raw `Pointer(Self)` with **nothing
retaining the object**, so `threading.Thread(target=f).start()` unbound — the shape
CPython itself documents — was a use-after-free. 30/30 with refs kept, 0/30 dropped,
10/30 on one CPU. **Not daemon-only:** `LiveAdd` stores a pointer so the exit path can
join and a plain array store does not retain, so "the registry holds it" is false
(1/30, 9/30). Retain belongs in `start()`, not inside `if not daemon`.

**THE P90 TICKET CLOSED BY EVENTS — carry this to the owner, it is about the backlog and
not about one ticket.** `bug-a-a-nilpy-object-allocation-takes-no-heap-lock` was filed
2026-09-13 at **p90, top of the queue**, and fixed the NEXT DAY by the owner's own
`02b7f7250` — the allocator spinlock was gated `PXX_TS_SOFTLOCK` while x86-64 selects
`PXX_TS_HARDLOCK`, so nine sites compiled out on the one target everything is built for.
**Nobody closed it for three days.** That is the same mechanism as the `atan2` ticket
found closed-by-events 26 days late, which is what produced goal 2. Three days rather
than twenty-six, and the same failure. Re-measured verbatim before closing: list 0/10,
dict 0/10, tuple 0/10 against the recorded 5/5.

**Three method findings worth more than the fixes**, all from franks-ee, all now in the
tickets:
- **A control that PASSED when it must not**, because a `-Fu` override silently did not
  take. The tell was the binary's **code size being byte-identical** to the unmodified
  build — not the test result. Assert the PRECONDITION, not just the comparison.
- **Reclaim is lazy.** A stack returns during `ReapSweep`, which runs on thread
  CREATION, so measuring straight after a batch compares a swept state against an
  unswept one. The measurement's own earlier steps supply what the later one reads.
- **glibc recycles a finished thread's stack**, so a recycled gs-block address is
  indistinguishable from two live threads sharing one. franks-ee's first run said the
  OPPOSITE of its second. **Assert distinct WHILE CONCURRENT**; sampled across a
  thread's death is a different claim, and it is the one that fails.

**errno stays open, and its counts FELL an order of magnitude without being progress** —
`errno.h:5` is still `extern int errno;`, nothing in that path changed, the thread route
did. Flagged by franks-ee itself, which is the direction nobody checks. Its stated
blocker ("fixes no FOREIGN thread") is measured FALSE for every thread a pxx program
makes including from C, so the cheap path is unblocked; remaining work is Track C.

**Reassigned:** franks-ee → `c_asm_in_inline_body.c@2`. **THIS ASSIGNMENT WAS BUILT ON A
MISREAD LABEL — see check-in 0e.** Its fallback, `test-tthread-fails-under-full-tier-load`,
had already been dispositioned to `low-prio/` by franks-ee before I flagged it, correctly.

### 2026-09-16, check-in 0d — Track C group closed; Track P census running

**frankb-56 closed the duktape/quickjs group.** `84af01b80` `__builtin_frame_address(0)`
— **quickjs-ng now compiles IN FULL**, ~85k lines / 3052 procs / 5.3MB. It then segfaults
at runtime (`js_bytecode_function_finalizer` hands `js_free_rt` a `0xffffffffffffffff`,
the signature of a field never written rather than a double free), filed as its own p60
bug. **Both of its compile fixes were exonerated by CONTROL, not by argument:** a
`malloc_usable_size` returning 0 unconditionally — quickjs's own portable arm — still
segfaults identically at rc 139, and frame_address in quickjs's exact shape measures
positive and monotonic against gcc. It gave the self-blaming reading the same scrutiny
as the flattering one, which is the half that terminates a search early.

**A GATE VERDICT IS A CLAIM ABOUT A TREE AND NEEDS THE TREE'S IDENTITY ATTACHED — the
same way a measurement needs its binary sha.** Two instances in one hour, opposite
directions, same seat:
- frankb-56's commit quoted fixedpoint `7f8a0ce6e2e5`; `47a5d356e` landed **34 seconds
  earlier** and arrived inside `sync.sh`'s own `pull --rebase`, so the pushed tree's
  actual fixedpoint was `e790ec9e027f`. **The sha is the one quantity a peer's
  concurrent compiler commit silently invalidates, and it looks like the most rigorous
  thing in a gate report, so it is the least likely to be re-checked.** Corrected in
  `9281da35b` rather than force-pushed.
- Its gate report then described three rows as still failing in the present tense from a
  run that predated `64de90285`. **I re-measured instead of correcting from memory:**
  `PASS fpc seed compiles (forward decls)` at HEAD, all three forwards present.
In both, every OTHER fact in the message survived intact — which is exactly what makes
the one stale item invisible.

**Gate at HEAD is RED on ONE row and it is new: `AST slot-write census`, `+AN_ADDR Left
fraIdn`** from `84af01b80`. Reviewed: `fraIdn := AllocNode(AN_IDENT)` written to
`ASTLeft[Result]` on an `AN_ADDR`, same kind as the six `AN_ADDR Left` rows already in
the snapshot. No new kind parks a non-node — **paperwork.** Left with frankb-56 rather
than swept here, on the principle frankb-56 itself stated when it declined to update
the NilPy rows: that rule cut in its favour then and against it now, which is how you
know it is real.

### THE INSTRUMENT I WAS ABOUT TO REBUILD ALREADY EXISTED

I read the umbrella's *"the instrument that would answer the size question — nobody has
built it"* and started to build it. **`tools/fpc_compiler_corpus_probe.sh` already has
`PXX_CORPUS_DETAIL` and `errs=N`**, added 2026-09-11, documented in its own header,
and the umbrella body says so too further down. One `sed -n` of the file cost nothing
and saved proposing a mechanism that already existed under the name it already had.
**Read the prose the grep returns.**

**Census running now** — detached, `PXX_CORPUS_DETAIL` set, binary `e790ec9e027f` at
`9281da35b`. **EXPECTATION, RECORDED BEFORE THE RESULT:** `TDoubleRec` is the first
failure of 132 of 207 units (64%), and I expect clearing it to convert **close to zero**
— a sixth null row — because five consecutive walls have converted at 0, 3 and 2. The
question I actually want answered is different from the one a first-failure census asks:
**for how many units is `TDoubleRec` the LAST wall?** Those are the only units a fix
delivers. I expect that number to be small and the detail files to show most of the 132
carrying several independent errors behind it. If the detail files instead show most
units with `TDoubleRec` alone, my model is wrong and the wall is worth far more than the
umbrella's queue-position finding predicts.

### 2026-09-16, check-in 0e — I WAS WRONG ABOUT `c_asm_in_inline_body`, TWICE, AND CONFIDENTLY

**Nothing was broken. There was no defect, no re-laning to do, and the bisect I
discredited was correct.** Corrected with all three seats I had told otherwise.

**What it actually is:** `testmgr` keys a job by SOURCE FILE, and the
`python3 tools/ast_slot_overloads.py` line sits in the same recipe region as the
`c_asm_in_inline_body.c` rows — so an **AST-slot snapshot drift is reported under a C
program's name**. The C test passes at HEAD, both rows, default and -O3, printing its
expectation `35 14 5`. **The tier's own failure detail says "census diff" if you read
it; I read the job key instead.**

**And the cloner ticket I said it pinned has been in `done/` since 2026-09-02.**
`tools/ast_slot_overloads.py` IS the guard that fix installed. Its summary records no
observable instance across 2233 files and 238k firings. **Those rows are pins on shapes
that WORK, not repros — them passing is the designed outcome, not a missed
reproduction.**

**THE CORRECTION THAT IS WORTH THE MOST, because it generalises:** `3a91d13f1dec` adds
`ASTLeft[binN] := lhsN` and `ASTLeft[dynBin] := PyMakeDynAttrGet(baseNode, fname)` —
**exactly** the two `+AN_BINOP Left` rows in the failure detail. The bisect was right.
It looked positional because **it moved a SNAPSHOT, not BEHAVIOUR**, so nobody can find
a defect at the sha — there isn't one — and *"no defect at the bad commit, 1-in-range"*
is ALSO the exact signature of a positional false positive. **A snapshot-guard
regression and a mis-bisected one are indistinguishable from outside the commit.** The
only discriminator is reading the diff, which costs one command and which I skipped
because the positional reading fit my prior.

**AND THE WAY THE WRONG ANSWER SURVIVED IS THE REAL FINDING — Track T corrected my
correction on this, against its own interest, and it is right.** I first wrote that
Track T "had the right answer and was talked out of it." **It did not bisect anything.**
The correct attribution came from borg's tstate `bad=` field — the WATCHER's output, a
machine result — which Track T relayed and then argued AGAINST, adding a rationalisation
of its own (*"nothing NilPy-shaped, so it is positional"*) that made my wrong answer look
better supported than I had left it. So the sequence was: a correct machine answer,
explained away by two agents who each found the other's reasoning corroborating.
**Two readings that can go wrong the same way are one reading** — and here they went
wrong the same way because the second was BUILT on the first. Crediting Track T with a
check it never ran would have been worse than the diagnosis error itself: it makes a
seat look like a verification that happened. Its own words: *"a false credit costs the
owner more than the diagnosis did."*

**The paperwork class has now cost THREE seats a diagnosis** (frankb-56, franks-ee, me).
franks-ee's durable fix, relayed to Track T and left for the owner: **give the AST slot
census its own job key** so a snapshot drift stops being reported as a C test. Not done
here — it is Track T's tool, and Track T has DECLINED to take it on its own judgement on
exactly the grounds two other seats already used: it is a Makefile/testmgr reshape and
its seat's owner has not asked for it. It is putting that and the coverage-hole fix to
its owner **as a set**, since they are now the second and third unclaimed Track T
changes. Correct call; three independent declines on the same kind of fork is the rule
working, not caution.

**The cheaper item is the better one, and Track T says so too: a fourth `bad=`
qualifier, *"bad touches only a guard's expected-output file."*** It is computable at
the same moment as the existing *"bad touches NO buildable file"*, from the same data,
and it **prevents the wrong INFERENCE rather than relocating the symptom** — which is
what the job-key split does. Verified by Track T from the Makefile: the
`c_asm_in_inline_body` compiles are at :16970 and :16972, `ast_slot_overloads.py
--self-check` at :16978, six lines down in the same recipe region.

**Also corrected:** I quoted binary sha `1d694b44d75d` to another seat as a landmark. It
was MEASURED at my tree, not predicted — but quoting it to a seat several commits ahead
turns a local measurement into something another tree gets checked against and read as a
divergence. franks-ee's `e790ec9e027f` was right. Same family as frankb-56's fixedpoint
catch: **a figure that was true about one tree, travelling without it.**

### 2026-09-16, check-in 0f — the census answered, and the expectation held

**My prediction was right and the useful part is what it was right ABOUT.** I said
`TDoubleRec` would convert close to zero and that the real question was how many units
have it as their LAST wall. Answer: **0 of 132.** Sixth null row confirmed, and confirmed
cheaply because it was stated before the run.

**The finding the first-failure census structurally could not show:** all 132 of those
units hit **exactly two** errors and nothing else — `unknown type: TDoubleRec`
(`x86_64/cpuinfo.pas:36`) and `too many array initializer elements` (`:281`). **Both
walls are in ONE FILE.** Not a truncation artefact: 38 units report 1 error, 132 report
exactly 2, and only one unit in the entire corpus reaches `MAX_REPORTED_ERRORS=20`.
Totals 21 BOTH-OK / 10 ORACLE-NO / 176 PXX-FAIL, binary `e790ec9e027f` at `9281da35b`.

**The second wall had no ticket.** Now `bug-p-an-array-constant-with-a-set-element-type-cannot-be-initialised`
(p80), and it is **the UNFIXED SIBLING of the record-constant arm `138604b5e` fixed** —
the exact case `normalise-dont-special-case.md` warns about, sitting unfound for five
days. Repro is 4 lines; `array[0..0] of set of TF = ([])` is one element against one
slot and still says "too many", so the DIAGNOSTIC NAMES A COUNT AND THE DEFECT IS NOT A
COUNT. Isolated by probe: enum bound innocent, set type innocent, a set as an ARRAY
CONSTANT's element is the whole cause.

**Recorded before anyone starts, so it cannot be discovered as a disappointment:**
clearing both walls most likely lands the 132 on a **third wall in the same file**, not
on 132 compiling units. And a complete *reported* failure set is not a guarantee of
compilation — `ErrorRecover` carries past SEMANTIC failures only, so a halting
diagnostic later in a unit never appears in the detail file at all.

**`cpuinfo.pas` is the third time this umbrella has recorded one file's contents wearing
the shape of a population** (after `cclasses.pas` at :895, :1327, :1726). That is the
pattern, not a coincidence, and it is why unit counts must not rank a ticket.

Offered to franks-ee alongside optdiff shard5; frankb-56 has the glob pair.
