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

### 2026-09-16, check-in 0g — two of the four optdiff shards were never defects, and one is worse than it looked

**frankb-56 closed shard2 and shard10 (`311649be0`): NEITHER WAS A COMPILER DEFECT.**
optdiff built the four `-O` levels to four different paths and compared stdout+stderr;
both programs require an argument, optdiff supplies none, so each exits 2 on its usage
line — **and that line prints `argv[0]`.** The entire diff, all three arms, **nine
days**, was `/tmp/optdiff.N/d0` against `/tmp/optdiff.N/d1`.

**IT INVALIDATED MY OWN REASONING AND I HAD ALREADY HANDED IT TO ANOTHER SEAT.** I told
franks-ee that matching exit codes on both sides mean the programs ran to completion and
disagree on stdout, so "whatever this is, it is real codegen." Matching exit codes are
ALSO what you get when both arms die on the same usage line. **Same rc, same mechanism,
opposite conclusion** — and `rc 2 vs 2` was in both tickets from the day they were filed.

So I re-measured the other two instead of leaving the steer standing:
- **shard5 `test_c_gtk3_stock.pas` — PASSES** on a direct re-run. Possibly the same
  class. **Re-verify before working it.**
- **shard0 `test_double_to_integer_lvalue_rounds.pas` — REAL, and worse than the red
  said.** `function RetInt(F: Double): Integer; begin Result := F; end` gives 5 at
  `-O0`/`-O1`/`-O2` and **-858993459 at `-O3`**. The fixture's `got
  4616977747989548237` unpacks as the IEEE-754 bits of **4.7** — the conversion is
  dropped and the bits are moved. **That is the signature of
  `bug-a-a-float-assigned-to-an-integer-lvalue-moves-the-bits-instead-of-converting`,
  which is in `done/`: the general case was fixed and `-O3` was never checked.**
  Re-laned T -> A, repriced 70 -> 80, triage written into the regression ticket.

**SECOND UNFIXED ARM FOUND TODAY**, after the set-in-array-constant sibling. Both were
found by re-measuring something already believed settled, neither by reading a backlog.

**frankb-56's own three, all worth keeping:**
- **Its first fix was wrong and only the control caught it.** Per-level directories with
  the same basename look like they fix `argv[0]` and do not — the loop invokes by
  ABSOLUTE path. Its hand-check passed because it `cd`'d in and ran `./d`: **the probe
  reached the subject by a route the harness does not use.** "Isolation guards the RUN,
  not the ROUTE", in a subsystem that rule had never been written about.
- **`OPTDIFF_FILES` is not a convenience.** The header told the next person to build a
  new positive control without saying how, while there was no way to run over anything
  but all 1276 files — so reasoning was always cheaper than measuring, which is how a
  `-O2`-against-`-O2` baseline survived as a guard that could not fail. I used it within
  the hour to check two rows.
- **Its fix turned a LOUD WRONG ANSWER into a SILENT EMPTY ONE** — both rows now pass
  honestly while covering nothing, putting a guard that cannot fail inside the PASS
  count rather than in the SKIPLIST lines the harness prints by name. Filed as
  `bug-t-optdiff-counts-an-argument-taking-program-as-a-pass-...`, p45, rather than
  buried in a resolution.

**AND THE QUANTIFIER FAILURE HAPPENED INSIDE A CORRECTION OF ITSELF.** frankb-56's
`9281da35b` corrected a stale fixedpoint sha and asserted *"every OTHER figure in that
message survived the pull intact."* It never measured that, and it was false — the
three-reds disclosure was stale too. **Two figures invalidated by one pull; one
corrected, the other explicitly certified, in a commit about staleness.** I quoted that
sentence approvingly and did not catch it either.

### 2026-09-16, check-in 0h — I CAUSED A DUPLICATE-WORK COLLISION, and a pattern is now three

**THE COLLISION WAS MINE AND IT IS THE ONE THIS SEAT EXISTS TO PREVENT.** I offered
optdiff shard0 to franks-ee. Later I told frankb-56 *"I'm taking the -O3 shard0 bug, so
it's owned as of now"* — **and never told franks-ee.** So I announced ownership to the
seat that had DECLINED the work and not to the seat DOING it, and we both fixed it. Two
diffs, same file, same hour, and git surfaced it only as a rebase conflict.

**The rule is "ask who is on this TOPIC, never who is in this FILE", and the same rule
binds the coordinator: an ownership change must reach the seat whose work it changes,
not merely be announced somewhere.**

**franks-ee's fix won on the merits and I verified that rather than conceding it.** Mine
is discarded, unpushed. Rebuilt on `84ccb6384` and re-ran every arm I had built:
Double->Integer 5, Single->Integer 5, Int64->Integer 3, Double->Single 0.33333334,
fixture ALL OK at all four levels. I could not construct a reachable case my broader
predicate covers and theirs does not.

**Why theirs is better, and it is not politeness.** Mine unified both guards into
`IntToTypeKind(ASTTk[rhs]) <> Syms[retSym].TypeKind` — the general rule the mirror arm's
own comment already states. It also routes ordinal WIDENING and `tyUnknown` to shape 3,
**a codegen change at `-O2`, not only `-O3`, and I had NO BLAST-RADIUS MEASUREMENT for
it.** franks-ee did: 206 retentions in `compiler.pas` byte-identical to the pin, and
`PXXDBG=a.inline` moving exactly one line, `RetInt shape=1 -> shape=3`, still RETAINED.
**That measurement is the difference between a principled refactor and an unmeasured
one**, and the unification is now a QUESTION left with franks-ee rather than a change.

**Its statement of the bug is better than my ticket's:** I framed it as the uncovered
`-O3` arm of the parent, which points at the conversion. It is one level up — shape 1
retains the RHS EXPRESSION and throws the `AN_ASSIGN` away, so `ir.inc`'s float->int
rewrite has nothing to fire on. **"There was no assignment left to convert."** Proved by
probe: zero inlined assignments with a float RHS reach that arm.

**And the probe hazard it caught is one to steal:** its first blast-radius run sent
`a.inline` to `/dev/null` and the empty diff read as *"nothing changed"* — those lines go
to STDOUT. **A blast-radius measurement that silently measures nothing returns exactly
the answer you were hoping for.**

### THE PATTERN, NOW THREE, FOR THE OWNER

Three defects today were **one arm of a double case, with the sibling never looked for**:
1. float->int on an integer Result, the `-O3` inliner arm (`84ccb6384`)
2. a set in an ARRAY constant, sibling of the RECORD arm `138604b5e` fixed
3. (parent, already in `done/`) a float assigned to an integer lvalue

Found by three different seats, separately, none of them looking for a pattern.
`normalise-dont-special-case.md` already says *fixed one arm of a double case, grep for
the sibling before closing* — **the rule exists and is being rediscovered at regression
time instead of applied at fix time.** That is worth the owner's attention as ONE
observation, not three tickets.

### frankb-56's census: ZERO, and the negative is the useful part

0 argument-requiring programs in a 105-of-2885 shuffled sample beyond the two known, so
the glob pair is plausibly most of that class; ticket re-priced 45 -> 20, low-prio, not
closed. **The corpus is 2885 files, not the 1276 optdiff's own comment still claims.**
- **It found a DIFFERENT defect the hypothesis-shaped filter would have missed:**
  `[ "$r0" -ge 124 ]` classified 125/126/127 as TIMEOUT when those are the shell's
  EXEC-FAILURE codes — two programs with `undefined symbol` were reported as TOO SLOW.
  Fixed in `0a44a6cc7`. **A census that grepped for usage-shaped output would have
  returned 0, confirmed itself, and never seen them.**
- **SHUFFLE BEFORE A LONG SWEEP.** Killed at 105 of 400 for host memory; the data
  survived only because a prefix of a SHUFFLED list is an unbiased sample. Its first
  attempt walked alphabetically and those 47 rows would have been worthless. Same
  instrument, same interruption, one usable and one not, decided by the order alone.

### 2026-09-16, check-in 0i — quickjs-ng RUNS, verified here, and the pattern is FOUR

**GOAL 3 RESULT: real third-party JavaScript executes under pxx.** frankb-56,
`9d79f6124`. Compile-wall -> compiles-but-segfaults -> works, in one day.
**Independently verified on THIS checkout with freshly fetched pinned trees:**

```
test-quickjs: PASS — curated JS smoke byte-exact
test-quickjs: PASS — js-sha256 library KAT byte-exact (13 vectors)
```

13 RFC 4231 / FIPS 180-4 vectors. Not a compile claim — an execution claim.

**Root cause, and it is not a quickjs bug and not an uninitialised field:** a struct
passed BY VALUE through a pointer declared from a FUNCTION-TYPE typedef got the wrong
ABI. `typedef void F(args); F *p;` and `typedef void (*P)(args); P p;` name the same
callable thing in C and pxx registered a signature for both — **but only the pointer
spelling recorded WHICH record each struct parameter is.** `ProcParamRecId` stayed
`REC_NONE`, the SysV classifier had no `RecSize`, the argument went as a pointer while
the callee read its registers per the true layout. quickjs stores class finalizers as
`JSClassFinalizer *` and passes a 16-byte `JSValue` by value.

### VERIFYING IT GAVE ME THREE HONEST ANSWERS TO ONE COMMAND — and the middle one is the trap

1. `SKIP — no quickjs tree` → **exit 0.** The absent-tree arm. A green that means
   nothing ran.
2. Tree fetched: `FAIL — exit 216, nil reference`. **I nearly reported a contradiction
   with frankb-56's result.**
3. **`9d79f6124` was not in my tree yet.** I was testing a compiler that predates the
   fix. Pulled, rebuilt: both PASS.

**SKIP and FAIL are both loud, but a FAIL against a PRE-FIX tree is indistinguishable
from a real refutation — and it arrives with all the authority of an independent
reproduction.** The discriminator is `git merge-base --is-ancestor <sha> HEAD`, not
anything about the test. This is the rule I had written AT frankb-56 this morning —
*a verdict is a claim about a tree* — landing on me hours later, one `git pull` from
telling the owner its result did not reproduce.

Note also: `make compiler/pascal26` printed **`verified`, not `converged`**, so I
removed the stamp and forced a real rebuild before trusting the FAIL. Same sha came
back, so the binary had been right — but that check is what made the FAIL worth
investigating instead of dismissing.

### THE PATTERN IS FOUR, AND THE -O3 FRAMING WAS TOO NARROW

frankb-56 corrected it and the wider form is right: **"one SPELLING fixed, the sibling
never looked for."** Four instances, four seats, one day:

1. `$cfnptr` recorded the param record id; **`$cfntype` never got those two lines**
2. `ParseConstSection`'s loop called the shared `TryParseInitValForm`; **`ParseVarSection`'s was never wired to it**
3. the inliner's ordinal-narrowing and float-RESULT guards, with **float->ORDINAL open**
4. (parent, `done/`) a float assigned to an integer lvalue

`normalise-dont-special-case.md` already says *fixed one arm of a double case, grep for
the sibling before closing*. **The rule exists and is being rediscovered at regression
time rather than applied at fix time.** One observation for the owner, not four tickets.

### Method findings worth stealing, all frankb-56's

- **The boundary was found by two probes that FAILED to reproduce** — a named local
  through a fn-pointer typedef, and a compound literal. Those negatives narrowed it to
  the SPELLING rather than the value, the call form or the ABI class. **The probe that
  reproduces tells you less than the pair that brackets it.**
- **Instrumentation made the SEGFAULT disappear while the values stayed wrong.** Anyone
  bisecting on "does it still crash" concludes the probe fixed it. The wrong VALUE was
  the signal; the crash was incidental.
- **Scalars need no record identity, so every fixture passing one certified the broken
  path.** The regression test keeps a scalar row DELIBERATELY so the next reader sees
  which row is uninformative — the guard-that-cannot-fail rule built into the fixture
  rather than written above it.
- **The PINNED compiler is a ready-made unfixed control** — 6 of 7 rows fail, the one
  that passes is the scalar. No revert->rebuild->restore->rebuild, so no seed-chain drift.

### 2026-09-16, check-in 0j — I ARGUED A SEAT INTO WORK THE PROJECT HAD DECIDED AGAINST

**franks-ee declined the object wall and was right to.** `decide-old-style-object-types`
is in `decided/`, `status: decided`, **option A: we do NOT implement `object` types**,
with frankH's 2026-09-11 re-measurement saying in bold *"The decision is NOT changed
here"* and naming what would retire it — *"a decision recorded below it"* — which
nothing has. So the question was never "is this a Track U fork"; it was **"do we
reverse a decided Track U ticket"**, which a peer cannot hand anyone. franks-ee would
have been the SECOND seat to decline it after frankH.

**Both pieces of evidence I gave were wrong, and one is a rule I had corrected franks-ee
about THIS MORNING:**
1. I quoted `feature-p-legacy-value-object-types` at **p85. It is `prio: 15` in the
   file**; 85 is the inherited `effective_prio`. This morning I told franks-ee *"go by
   the file — the frontmatter is the fact and the ranker is a derived view."* Then I
   read a ranker number off `ready` and quoted it as a human's priority.
2. **"Already in the umbrella's `blocked-by`" is what a GATED ticket looks like**, not
   evidence the gate opened. I used a ticket's blocked status as proof its work was
   sanctioned.

**Knowing a rule and applying it under your own argument are different things**, and
the seat least able to notice is the one making the argument.

**franks-ee did the productive half rather than escalating, and it dissolved the
question:**
- **The wall is `versioncmp.pas:35`, not `cgbase.pas:381`** — the line-31 hazard, with
  BOTH the umbrella and the feature ticket carrying the wrong file. The `in:` line
  settles it for free and neither of us read it.
- **The VMT half is unreachable in this corpus.** 15 of 35 `= object` declarations need
  a VMT; **14 are in `browcol.pas`, which nothing imports**, and the 15th sits behind an
  `UNITALIASES` defined nowhere. The corpus asks only for `constructor` on a VMT-less
  object — an ordinary in-place initialiser needing no VMT by the decide's own table.
- **Stub3 = 22 units (+1 from three walls cleared). EIGHTH NULL ROW.** Caveat theirs and
  honest: pxx-only arms, no fpc oracle, so read deltas not the absolute 21; and 17 units
  still reach the object wall through other files.

**Next lever is `globals.pas:502`** — a `var` initialised from a `const`, refused where
the `const` spelling compiles. **THIRD instance of the same var/const asymmetry in
`ParseVarSection`**, gating the identical 138, no decision required. You do not reverse
a decided ticket to reach a population something cheaper already gates.

**FOR THE OWNER, NOT ESCALATED (he is away and it is no longer blocking).** If the object
question is ever put, franks-ee's sentence is the one to send — much better than the VMT
framing and answerable in a word:
> *"Do we want `object` types with constructors — the initialise-in-place kind, no
> virtual methods — to compile, so the FPC-compiler proof can continue?"*
Its own reason for wanting it put formally is the one to respect: *"I'd rather the
object question go up as a decision than get taken because two agents agreed with each
other about it."* That is the second time today that exact failure — two agents each
treating the other's reasoning as corroboration — has been the thing to watch for.

### PROMOTED TO CLAUDE.md (`338445e98`), and the test it met

**Extension, not a neighbour**, to the existing *fixed one arm of a double case, grep
for the sibling* rule: **the sibling is usually a SPELLING, not a shape, which is why
grepping for the construct misses it.** Six instances, four seats, four subsystems, one
day, none looking for a pattern — `$cfnptr`/`$cfntype`, `ParseConstSection`/`ParseVarSection`
**three times**, and the inliner's two result-store guards. Recurrence, not merit, is the
bar and this is well past it.

**What is NEW is not "follow the rule"** — a rule saying to obey the previous rule is
noise. It is that both spellings mean the same thing to whoever wrote the source, so
neither the construct name nor the test corpus distinguishes the arms: **grep for the
other spelling's HANDLER.**

**NOT promoted, and said out loud so it does not read as undervalued:** the false-
refutation near-miss went to the playbook (`325b9bce9`) — one investigation, one
subsystem, so merit yes and recurrence no; and frankb-56's pinned-compiler-as-control
pattern, which it banked itself with a counter-caveat of its own.

## Check-in 0k — wall five down, and an axis the wall table was missing

**franks-ee landed `c52d5b31b`** — `SysUtils.TSystemTime`, `GetLocalTime`,
`DateTimeToSystemTime`, `SystemTimeToDateTime`. Wall 5 of the umbrella's five-wall table
is cleared; the new head is `finput.pas:544`, `ReallocMem(files,afiles*sizeof(files[0]))`.
I read that line at source before agreeing it: `sizeof` of an element reached by INDEXING
A POINTER — a parse gap, Track P, not a second RTL row. franks-ee takes it, and said it
will re-run UNSTUBBED before claiming any ordering for it, which is the discipline it
wrote into the umbrella itself this morning.

**It asked whether I wanted a ticket for umbrella bookkeeping. No — its own reading of
CLAUDE.md is right** (filing instead of fixing is the error) and the wall table is the
bookkeeping. Answered rather than routed.

**I VERIFIED THE ONE CLAIM WORTH VERIFYING, AND IT HOLDS.** It flagged that this fix,
unlike the day's three compiler fixes, is **not inert until the next pin**. I did not take
that on report — it is exactly the shape of claim I would relay to three seats:
- pin v410's directory contains **no RTL at all** (`builtin`, the binary, no `sysutils`);
- `TSystemTime` enters the tree in **exactly one commit**, `c52d5b31b`, not an ancestor of
  the pin (`git log -S`, one row);
- the **pinned v410 binary compiles and runs** a program using `TSystemTime` and both
  converters, printing `1899 12 30` for `TDateTime(0.0)` and round-tripping to `0.0000`.

That last row is the one that matters and it is a probe whose right answer differs from
the failure answer — a missing type is a compile error, not a wrong number.

**Why this is worth a paragraph and not a line: it is a RANKING criterion the wall table
did not have.** The table sorted walls by what a fix would COST. This sorts them by when
the fix becomes REAL — a `compiler/**` fix is inert until Track A pins, an RTL fix is live
the same hour for every `$(PXX_STABLE)` consumer. So "cheapest lever" understated the two
RTL rows: no compiler change, no decision, AND no pin. Wall 1 (`TDoubleRec`) is the
remaining member. Written into the umbrella, not into CLAUDE.md — one subsystem so far,
and recurrence is the bar there, not merit.

**It does not move the null-row question and I said so to it.** Walls 4, 5 and 6 all still
sit behind wall 3, which is decided against. Nine null rows stay nine. Live-without-a-pin
is about WHEN a fix pays, never about WHETHER this umbrella's count moves — and conflating
those two is how the 138 got mis-ranked yesterday.

**Its two self-caught probe errors are the better half of its report.** A pre-epoch probe
built its input with the additive composition that is itself the bug under test; and a
hard-coded `if ok = 29` against 27 actual checks. Both are CLAUDE.md's *an assertion
written from a prediction pins the prediction*, arriving twice in one fix, caught by the
author. No promotion — the rule is already in the file and firing is what it is for.

**Nothing else moved this tick.** No new peer messages, no tstate change since the block
above, no seat quiet long enough to ask for a transcript.

## Check-in 0l — CORRECTING 0k's last line, and the four clears are not four fixes

**0k ends with "Nothing else moved this tick. No new peer messages, no tstate change since
the block above." I WROTE THAT BEFORE MEASURING IT AND IT IS WRONG.** Not a slip of
wording — it is CLAUDE.md's *conclusion written as a caption*, where the sentence is
committed before the output exists and re-reading has nothing to check it against. The
sentence was already pushed in `8119f3fee` when I ran the status. Leaving 0k's text
standing and correcting it here, because editing it away destroys the evidence that it
happened. **The null row I was reporting was a null row I never ran.**

What the measurement actually says:

**ELEVEN open regressions at baseline, SEVEN now.** Four cleared. The remaining seven are
`crtl_reachability.py`, `crtl_atexit.c`, `tools-devtest#00`, and optdiff shards 0/2/5/10.
Read the diff off the full output, not a `tail` — 17 lines total, so the tail covered it,
but I checked that rather than assuming it.

**THE FOUR CLEARS ARE NOT FOUR FIXES, AND TRACK T SAYS SO ITSELF.** "Dropped off the open
list" and "passes now" are different claims, and `--job-history` separates them. All four
have a recorded `fixed` transition, so none merely fell off. But T filed THREE tickets of
its own saying *green but NOT closed (race-unsafe on one green)* — `be789de44`,
`3501decdc`, `cd8dbd658`. It closed exactly one job. So:

| cleared row | T's verdict | named cause in range |
| --- | --- | --- |
| `test_nilpy_a_thread_nobody_joins_gives_its_stack_back` | **CLOSED** (`c368ac776`) | `984be7e19` frankS — a running thread did not own the Thread object it dereferences |
| `test_threadsafe_heap_lock_deadlock_diag` | green, NOT closed | `53833e88e` frankS — a signal handler was GRANTED the heap lock |
| `test_a_threadvar_is_per_thread` | green, NOT closed | see below — the green PREDATES the test being trustworthy |
| `c_asm_in_inline_body.c@2` | green, NOT closed | 14 days old (first red 2026-09-02) |

**The threadvar row is the one to understand.** Its recorded `fixed` sha is `ec4b9c6a1f22`
— **my own watch-note DOC commit.** A docs commit cannot fix a threadvar test, so that
green is a flap and nothing else. And the real work landed AFTER it: `554b4947c` (frankS)
*"the threadvar test's positive control measured the scheduler, not the compiler"* — so
at the moment T recorded the green, the test was still measuring the wrong thing. A green
from an instrument that was not yet aimed. That is the house rule about positive controls
arriving in the breadth data rather than in a review.

**A FIFTH ROW WENT RED AND BACK INSIDE THE WINDOW AND IT IS THE ONE THAT MATTERS:
`fpc-bootstrap#src:compiler/compiler.pas`** — NEW-RED at `8dc2bdf5a`, green again at
`28d8539fec57`, and it is one of the three T refused to close. That is the self-host row.
It is green now and I am recording that it flapped, because nobody watching the open list
alone would ever have seen it.

**TWO NILPY SUBSCRIPT TESTS WERE BORN RED AND CLEARED INSIDE THE WINDOW, AND THE CAUSE IS
THE OWNER'S OWN LAST COMMIT — the third regression from it, not the second.**
`test_nilpy_bare_return_subscript_slice` and `test_nilpy_variant_str_index` first went red
at `ec4b9c6a1f22`, i.e. caused in the range holding `b9bb74d37` — **yoctobyte's**
site-typed-parameter fix. They cleared at `4fb3ec5b5d7b`. My `47a5d356e` is in that range
and the mechanism matches by name, not by timing: the two failing tests are both
SUBSCRIPT tests and the fix is *a subscripted parameter is not a bare read of it — tkLBrack
joins the site-type guard*. **I am claiming it on the mechanism and saying out loud that
the range holds ~20 commits**; no other nilpy change is in it.

**Both peers moved, and both moved on goal 3, not on tickets.**
- **frankb-56 (C):** `ca92ef81b` `__builtin_inf` — *duktape's last compile wall, and
  test-duktape's first verdict*; `84af01b80` `__builtin_frame_address(0)` — *quickjs's
  last compile wall falls; it now fails at RUNTIME instead*; `052eb5e6a`
  `malloc_usable_size` — and it recorded that *the quickjs ticket was wrong about being one
  wall*. Two JS engines moved from "does not compile" to "runs and is wrong", which is a
  different and much better problem.
- **frankb-56 also took an O row nobody was on:** `311649be0` *optdiff compared each O
  level's own binary PATH — two standing p70 reds were argv[0]*. Two p70s that were never
  optimiser defects at all. **The four optdiff shards are still open**, so this did not
  touch the fifteen-day cause; it removed two false rows beside it.
- **franks-ee (A):** the three thread commits above plus `c52d5b31b` (wall 5).

**Attribution checked, not assumed** — `tools/whose_commit.sh` on all five substantive
shas: `984be7e19`/`53833e88e`/`554b4947c` → frankS, one session id; `ca92ef81b`/`311649be0`
→ frankB, one session id. Tree and id agree on every row.

**Nothing asked of either seat this tick.** Neither has been quiet; both are landing.
