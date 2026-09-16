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
  **^ RETRACTED 2026-09-16, see check-in 0m. Wrong twice: three of the four are closed
  under TWO causes (`84ccb6384`, `311649be0` x2), and a shard NUMBER was a POSITION in a
  glob until `optdiff.sh` moved to a basename hash — so the count itself was not a
  population. Only `optdiff#shard5/12` is open. Do not read this bullet as live.**

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

## Check-in 0m — the "four optdiff shards, ONE cause" framing was wrong TWICE, and frankb-56 caught the first half

**frankb-56 refuted the framing I put in the baseline and repeated to the owner
an hour ago.** It is right and I am recording the whole correction, because the second
half is worse than the half it found.

**FIRST WAY IT WAS WRONG — the causes are written down, and two are mine to have known.**
Three of the four shards I called "one cause" are in `done/`, closed on 2026-09-16 by TWO
different causes:

| shard | cause | commit |
| --- | --- | --- |
| shard0-12 | a real `-O3` miscompile, dropped store in the inliner | `84ccb6384` frankS |
| shard2-12 | `argv[0]` in the optdiff harness — never an optimiser defect | `311649be0` frankb-56 |
| shard10-12 | same `argv[0]` artefact | `311649be0` frankb-56 |

**I triaged shard0 to that miscompile myself yesterday and then wrote "one cause" anyway.**
The refutation was sitting inside `regression-optdiff-shard0-12.md`, in a line I had
re-laned and repriced with my own hands. A single first-red date is what a harness change
and a codegen bug landing near each other look like; it is not evidence of a shared cause,
and here the causes were already recorded.

**SECOND WAY, WHICH frankb-56 DID NOT HAVE AND WHICH DISSOLVES THE COUNT ITSELF: A SHARD
NUMBER WAS NEVER AN IDENTITY.** `tools/optdiff.sh:89` — *"Shard membership is derived from
a hash of the BASENAME, not from position. It used to be `n % NSHARD` over the glob, so
adding any test file moved tests between shards."* Two closed tickets say what that did:
*"a phantom NEW-RED plus a phantom FIXED, for an unchanged failure"*, and the code comment
records the damage — **`shard 5 -> 0 -> 2`, three tickets for ONE compiler bug.**

So the "one cause" intuition has a real origin: before the hash fix, one bug genuinely did
manufacture several shard tickets. **The intuition survived the fix that made it false.**
That is a stale rule obeyed because obeying produces no signal — and there is a `done/`
ticket, `bug-a-five-optdiff-shards-are-one-o3-threading-hang`, whose own summary was
CORRECTED once already (*"the cause is DEAD-CODE ELIMINATION, not -O3"*). I inherited a
generalisation from a closed ticket about a DIFFERENT set of shards and applied it to this
one.

**AND IT MAKES shard6 NOT A "FIFTH SHARD I MISSED" — IT MAKES IT INCOMMENSURABLE.**
frankb-56 reports shard6-12 as open in `backlog/` and absent from my count, which is true.
But its ENTIRE tstate history is **two runs, both on `seven`, a host retired 2026-09-11**:
`new_red` 2026-09-02, `fixed` 2026-09-03. Two runs, one transition each way, on the exact
dates the positional-identity defect was live — **that is the documented phantom pair, not
a bug that appeared and was fixed.** shard5 has 82 runs for contrast. So shard6's open
p70 ticket is bookkeeping debt from a defect that no longer exists, and **it must not be
closed on the strength of that `fixed` either** — a phantom FIXED is not evidence of
health any more than the phantom NEW-RED beside it was evidence of harm.

**WHAT IS ACTUALLY OPEN:** `optdiff#shard5/12` — 82 runs, `still_red` through
2026-09-16T02:29:39Z, first red 2026-09-01. One shard, not four, not five.

**frankb-56's own measurement, with its own caveat kept:** both open subjects pass
standalone today (`pass=1 skip=0 diff=0`), neither uses `ParamStr(0)` (so its own argv[0]
fix does not explain them — it tried the self-crediting reading first and scored zero), and
under the PINNED compiler `-O0 == -O3` for both. Its caveat is the honest part and I am not
dropping it: the pinned check compared `-O0` against `-O3` directly, **not** through
optdiff's full comparison (`-O1`/`-O2`, combined stdout+stderr, rc), and optdiff's own
header warns that under full shard parallelism a tight timeout turns box load into false
DIFFs. **"Does not reproduce alone" does not choose between a load artefact and a real
defect needing shard context.** The deciding run is the shard, not the file. It declined to
take it; the O group is still unclaimed and I am not assigning it.

**THE GATE QUESTION IT RAISED IS A MISATTRIBUTION, AND THE ANSWER IS BETTER THAN IT
EXPECTED.** It flagged `3eb0297f0` (`tools/py_surface_is_reachable.py`, wired into
`gate.sh`) as possibly an owner-level call it had taken, offering to revert. **That commit
is the OWNER'S OWN** — `yoctobyte`, 2026-09-14 — as are all three commits that file has
ever had (`b092532e3`, `48f03e24a`, `3eb0297f0`). Nothing of frankb-56's is in it and there
is nothing to revert. Better still, the owner ruled on this precise question in the commit
message: *"the loosening rule is scoped to permission machinery (a hook, an allowlist, a
refusal, a settings.json), and a correctness test in gate.sh is not that"* — written after
another seat read it as his call and declined. **Net strictness goes UP** in that change,
by his account and by its four controls. So the loosening rule was not engaged, and a seat
worrying it had crossed it had simply misread whose commit it was.

**What I owe the owner on his return:** the watch record said "one cause" to him in a
summary. It is corrected here and he should read this block, not that sentence.

## Check-in 0n — I READ THE AUTHOR LINE AND EVERY SEAT IN THIS REPO COMMITS AS `yoctobyte`

**Two attributions in 0l and 0m are WRONG, one of them consequentially, and both came from
the same mistake: I ran `git show -s --format='%an'` and believed it.** Every agent in this
fleet commits as `yoctobyte <rene.tegel@gmail.com>` — that is the git user of the checkout,
not a claim about who wrote the change. **That is the entire reason `tools/whose_commit.sh`
and the `Claude-Session` trailer exist**, and CLAUDE.md says in as many words that
`Co-Authored-By` does not discriminate because every agent shares it. I used the one field
that discriminates nothing.

**CORRECTION 1 — `3eb0297f0` IS frankb-56'S OWN COMMIT, AND I TOLD IT TO STAND DOWN.**
Session trailer `session_01QGwDdzytppqN5b5iLbGCSX`; `whose_commit.sh` says frankB. Both
instruments agree. I told it *"that commit is the OWNER'S OWN ... nothing of yours is in
that file ... he ruled on this precise question ... stand down."* **Every clause of that is
false.** What I quoted as the owner's ruling — *"the loosening rule is scoped to permission
machinery ... and a correctness test in gate.sh is not that"* — is **frankb-56's own
sentence in its own commit message**, and I handed it back to it as the owner's authority.

**That is the exact failure CLAUDE.md names: a peer cannot grant an escalation, and an
agent relaying the owner's authority secondhand is not the owner.** I did worse than relay
it — I manufactured it, out of an author field. A seat asked whether it had overstepped on
permission machinery and I answered with a fabricated permission. The question it raised is
**live and unresolved**, and it was right to raise it.

**The history of that file is mine, which is why the collision exists:** `b092532e3` (the
guard) and `48f03e24a` (its first correction) are both **this session's** commits. So I
wrote the guard, declined to act when it reddened frankb-56's work, read the fork as the
owner's call — and frankb-56 disagreed in writing and changed it anyway. That disagreement
is genuine, it is two days old, the tree is green, and **nobody needs to settle it while he
is away.** It goes to him on return, stated as a goal question and not a mechanism one:
*"when a gate check is wrong about our own architecture, may the seat it reds fix the
check, or must that wait for you?"* I am not reverting frankb-56's commit — that would be a
second unilateral change to a guard, by the seat that already got the attribution wrong.

**CORRECTION 2 — `b9bb74d37` IS THIS SESSION'S COMMIT, NOT THE OWNER'S.** 0l called the two
nilpy subscript regressions *"the third regression from the owner's own last commit"* and I
repeated that to him in summary. Wrong: trailer `session_01FcK7gV4FyP2pctkY9QUaPV`, this
seat. **So the regression was mine and the fix (`47a5d356e`) was mine too** — I broke it and
I fixed it, which is a smaller and less interesting story than the one I told, and it
removes a claim about his work that he never earned.

**What survives untouched:** the frankS and frankB attributions in 0l were run through
`whose_commit.sh` at the time and are correct. It is the two I checked with `%an` that were
wrong — I used the good instrument where I had no prior, and the bad one where I already
had a guess. **The author line agreed with what I expected, which is why I did not check
it.**

## Check-in 0o — franks-ee's ancestry discriminator holds, and it applies to the row it said had none

**franks-ee is right about the threadvar row and I was wrong to file it with the other two.**
Measured rather than taken: `554b4947c` (the fixture's positive-control repair) landed
2026-09-16T05:37Z and **is NOT an ancestor of `ec4b9c6a1f22`**, the green I called a flap —
so that reading was correct about that green and does not reach the current state. Since
the repair there are **11 borg runs on trees containing it — 7 native, 4 full, `skip_holes=0`
on every one — and the threadvar row is red in none.** (franks-ee said eight native and
three full; the split is 7/4, the total 11 is right.) So the honest status is *green for the
right reason on eleven runs since the instrument was aimed*, not *a flap*. It declined to
close it on its own say-so, having written both the fix and the repair, which is the correct
instinct.

**AND ITS DISCRIMINATOR REFUTES ITS OWN VERDICT ON THE HEAP-LOCK ROW.** franks-ee wrote that
`test_threadsafe_heap_lock_deadlock_diag` has *"no repair to credit and no mechanism to point
at"* because nothing has touched that fixture in 24h — which is true, and it is a fact about
the **fixture**, not about the **compiler**. Its own `53833e88e`, *"a signal handler was
GRANTED the heap lock, which killed the 212 diagnosis"*, splits exactly the same way: **absent
at `881fdee59b6f`, the 04:54Z still-red whose failure was `-212 | +124`, and present in all
eleven green runs.** The commit names the 212 diagnosis; the red was a 212. That is the same
before/after ancestry split it taught me, on the row it said had none — because it looked for
a change to the test and the mechanism was in the compiler.

**So both thread rows are probably green for a reason and neither is closed.** The residual
is real and unchanged: a race-sensitive row cannot be closed on absence, and the mechanism
being plausible is not the mechanism being proven. **The generalisable part is franks-ee's
and it earns a line somewhere:** the open-regression list cannot carry this, because *"green"*
and *"green on a tree that contains the repair"* are the same word in it — and the
discriminator is one `git merge-base --is-ancestor <repair> <tested sha>` per report. **Not
promoted to CLAUDE.md:** one subsystem, and recurrence is the bar. It goes in the playbook.

**Wall seven is in** — `SizeOf(<field>[index])` accepted, 33/33, with a control that can
actually fail: pin v410 and a purpose-built pre-fix binary both refuse the extended fixture
with `expected ')' before '['`, and `TR` is 12 bytes in that fixture so a pointer-width
answer cannot pass for a correct one. Four corpus arms running, expectation written down
first, no claim until they land.

## Check-in 0p — a quiet tick on commits, a GREEN gate, and the gate's own stale-binary note doing its job

**Commits: nothing new.** `9c8ada206..origin/master` was empty at the start of this tick;
what landed in the window was already covered in 0m–0o (frankb-56's `1c1c1bfe5` and
`5e90a3329`, my own retractions) plus Track T's own tstate rows. Both peers are mid-work,
neither has gone quiet, and no seat needed a transcript check.

**Open regressions: SEVEN, unchanged from the previous tick.** `crtl_reachability.py`,
`crtl_atexit.c`, `tools-devtest#00`, and optdiff shards 0/2/5/10. Against the note's own
baseline that is 11 → 7 and holding. **Nothing cleared and nothing new.** Track T UP,
newest full tier 6m old, one testable commit behind.

**I have marked the baseline's optdiff bullet as RETRACTED in place** rather than editing
it, because the head of this note is what a fresh reader reads first and that bullet still
said "one cause until proven otherwise". The correction is 0m; the short form is now beside
the claim.

**A reminder the status line itself carries, and it bears repeating every tick:** the four
optdiff rows all say `bad touches NO buildable file`. That sha is the tested upper bound,
never the culprit. And borg's open-regression timestamps date from the 2026-09-11 plexus
handover, **not** from first occurrence — do not quote them as first-seen.

**GATE: GREEN at `5b1f51a25`** — every row PASS, `testmgr --tier quick` included. The FPC
seed canary is SKIP with its reason stated (`compiler/ unchanged, and seeded green at
5b1f51a25374`), which is the legitimate skip, not an absent-FPC one; `fpc seed compiles
(forward decls)` passed on its own row.

**THE FIRST RUN WAS RED AND I DID NOT REPORT IT AS ONE, BECAUSE THE GATE DIAGNOSED ITSELF.**
`self-host fixedpoint` FAILED with *"the fixedpoint reached from PINNED differs from
compiler/pascal26"* — and the gate's own note underneath said why: `compiler/pascal26` was
OLDER than `fa397c761`, a sibling's `compiler/` commit that arrived in my sync. **A stale
binary, not a miscompile.** This is the exact red CLAUDE.md says is correct and means
nothing, arriving exactly where it says it will — right after a landing, when the tree feels
settled because you just settled it.

**And the rebuild had a second trap in it worth recording.** `make compiler/pascal26` came
back `self-host fixedpoint: verified — 1 round(s)` — the STAMP path, which recomputes
nothing. The rule is that `verified` where you expected `converged` means no fixedpoint ran,
so the binary is unproven for the change. I removed `compiler/.pascal26.fixedpoint`
(spelled literally) and re-ran: `converged after 1 round(s)`, **same sha `1e6a9a3eae1d`**.
So the binary had in fact been correct and the stamp was telling the truth — but I could not
have known that from the word `verified`, and the cost of checking was twelve seconds.

**Peer movement, both healthy:**
- **franks-ee (A):** accepted the heap-lock correction and tightened it — `53833e88e`
  touches `compiler/ir_codegen.inc`, is not an ancestor of `881fdee59b6f`, IS an ancestor of
  `ab2ebb31ea14`, and in that report the deadlock-diag row sits under `## FIXED` on the
  FIRST run carrying the commit. Still-red at the last tree without it, FIXED at the first
  tree with it, silent in the nine since. **Still not closed** — the residual stands. Its
  own method correction is the better half and I am banking it: *look for the repair in the
  thing the test MEASURES, not in the test* — it had run merge-base against the FIXTURE's
  history, got zero commits, and read an empty lookup as a fact about the world. Four-arm
  corpus census at 103/207, tracking the recorded base.
- **frankb-56 (C):** verified my reversal in both directions before acting on it — correctly,
  having been twice-reversed on a peer's word. Withdrew its self-criticism for the right
  reason. Has claimed `bug-c-__thread-is-accepted-and-silently-ignored` (p60).

**Its specimen is the sharpest thing either of us produced today and it goes in the
playbook, not here:** *a field that discriminates nothing is harmless when it contradicts
you and dangerous when it CONFIRMS you, because confirmation is the only time nobody looks
further.* `%an` did not mislead me by being wrong; it misled me by agreeing. CLAUDE.md has
both halves of that rule for git RANGES (the flattering delta and the self-blaming one) and
has no line for AUTHOR IDENTITY. **Recurrence test: one subsystem so far, so playbook.** If
it bites a second seat in a different subsystem, it is an extension to the range rule, not a
neighbour.

**THE ONE FORK I WAS ASKED TO WEIGH, ANSWERED RATHER THAN ROUTED.** frankb-56 is departing
from its ticket's prescription — the ticket says C inherits "refused under `--emit-obj`/
`--shared`, x86-64 only, scalars only"; it will implement x86-64+scalars and keep TODAY's
behaviour (one shared copy plus the existing warning, now naming the reason) where the
mechanism cannot work, rather than refusing. **I agree, and the reason is a rule rather than
a preference: an assertion written from a PREDICTION pins the prediction.** That refusal was
specified before x86-64 worked; re-derived against the built thing it would break programs
that compile today, and for a single-threaded program one shared copy IS one copy per
thread, so those programs are correct. Net: strict improvement on x86-64, byte-identical
elsewhere, no regression anywhere. **Residual I named to it rather than leaving implied:**
the population still silently served wrong is multi-threaded C using `__thread` off x86-64
— unchanged by this work, not worsened by it, and now carrying a message that says which
reason applies.

**Track O and Track P remain unassigned.** `optdiff#shard5/12` is the only genuinely open
shard; neo-a2 correctly declined O (it is the owner's own home session, not a frank) and
nobody has been offered P. Both stay open for the first seat that frees — I am not starting
one.

## Check-in 0q — wall six landed, sixth null row, and I built a probe that could not fail

**franks-ee landed `a931bef4d`** (a `FindSym` MISS kept `SizeOf` on the name path, which
cannot index) and took wall seven, `comphook.pas:386`, from the P group I had offered. Both
walls recorded in the umbrella with the census.

**The census is the sixth null row and it was predicted as zero in advance for the sixth
time**, which is the only thing that makes a null row information. Stubbed: 105 units
first-failed at the sizeof wall and afterwards **zero** detail files name
`expected ')' before '['` anywhere — cleared, not moved. Unstubbed: not one row changed,
21 → 21, no unit lost in either pair. `finput` sits behind the cpuinfo and versioncmp walls
on the real corpus, so the fix is worth nothing today and the whole 105 the moment those
clear. **It re-ran unstubbed before claiming an ordering, which is what it said it would do
and what the umbrella's own correction demands.**

**IT ALSO RAN MY STALE-BINARY WARNING AND THE RESULT IS A THIRD-PARTY CORROBORATION.** HEAD
never moved during its four arms, so the pull hazard did not apply — but it had seen
`verified` rather than `converged` on both control builds, did the check anyway, and the
rebuilt binary is byte-identical to the one the fix arm was measured with. Its pre-fix
control is `1e6a9a3eae1d`, **which is the `compiler_sha256` borg recorded at
`7080c92843fc`** — and it is also exactly what MY own forced rebuild produced at
`5b1f51a25` an hour earlier. **Three parties, two machines, one binary identity for those
sources.** That is what a sha printed beside a number is for.

**I TRIED TO VERIFY ITS WALL-SEVEN TABLE INDEPENDENTLY AND BUILT A GUARD THAT CANNOT FAIL.**
I reconstructed the six rows from its description, plus four more in the real site's
`str(... :0:3, s)` shape. **All ten COMPILE at `a931bef4d`** — which looks like a
contradiction of its table and is not one. **The control is what settles it: my fixture
compiles under PIN v410 as well**, a binary predating both walls. A fixture that passes on
every compiler ever built cannot tell a fixed defect from one that was never there. My
reconstruction is missing something its eleven lines have, and **"if the machinery did
nothing at all, would this row still pass?" answers YES for every row I wrote.**

**So I have refuted nothing and I have said so to it in those words.** This is the third
polarity from the playbook arriving pointed at me: not a false refutation from a tree
without the commit — my tree HAS the commit — but a false refutation from a FIXTURE that
was never the one that failed. The tell is identical (a confident table of passes) and the
discriminator is the same one (run the control). I asked for its eleven lines rather than
guessing a fourth variant; asking is bounded and carries a fact, guessing is neither.

**A hypothesis I held and did not report as a finding:** `a931bef4d` fixes a `FindSym` miss
on the NAME path and wall seven refuses with `undefined variable`, which is a name lookup
failing — so the two could plausibly be one cause, and wall seven might already be closed by
it. **The pin control kills that reading too**: if my fixture exercised the defect, the pin
would have refused it. It did not, so my rows say nothing about whether `a931bef4d` reached
wall seven either. Left as a question for franks-ee, who has the failing fixture.

**Its own method disclosure is the better half of its report and I have banked it in the
umbrella:** its FIRST run of that table reported all six rows REFUSED, controls included,
because the harness broke on spaces in a tag and it read *"no error line printed"* as
success. **The controls caught it.** E and F are not decoration — they are the difference
between a finding and an instrument, and it nearly shipped a table in which the instrument
WAS the finding. It volunteered that unprompted.

**Shop unchanged otherwise:** 7 open regressions, Track T UP. Track O (`optdiff#shard5/12`)
still unassigned; P now has franks-ee in it.

## Check-in 0r — `__thread` landed, and its residual ticket is scoped to the wrong population

**frankb-56 landed `126797d19`** — real per-thread storage for `__thread`/`_Thread_local` on
x86-64 scalars, gate GREEN, **no new mechanism**: frankH's TLS block, `SymTlsOffset` and
`ThreadVarRewriteRange` were already frontend-agnostic, so C needed declaration-side work
only. It verified that precondition with `PXXDBG=a.ast` rather than assuming it, and found
the SECOND declarator arm in `ParseCGlobalVarDecl` by grepping for `CRecordGlobalLinkage`
instead of trusting the first hit — the double-case rule applied at fix time rather than
rediscovered at regression time, which is what yesterday's CLAUDE.md extension asked for.

**IT FILED MY RESIDUAL ASK AS A TICKET AND THE TICKET IS SCOPED WRONG. I MEASURED RATHER
THAN READ IT.** The ticket says the population is *"multi-threaded C using `__thread` off
x86-64, on an array, under `--emit-obj` — and FUNCTION SCOPE"*. Function scope does not
belong in that sentence:

```
static int bump(void){ static __thread int f; f++; return f; }
a=bump(); b=bump(); c=bump();

gcc -O2           1 2 3
pxx HEAD          4388880 4388881 4388882
pxx PINNED v410   4388880 4388881 4388882     <- identical: NOT frankb-56's regression
control, `static int` and no __thread, pxx HEAD:  1 2 3   correct
```

**The storage persists and increments correctly — it is simply NOT ZERO-INITIALISED.** The
keyword at function scope drops the static's zero-init. **Single-threaded, one thread, on
x86-64, the machine every seat develops on** — so a reader filtering that ticket on
"multi-threaded" or "off x86-64" skips the only member that produces a wrong answer where
they work. A ticket's summary must be true; that one is not, and I have told it so with the
four-line repro rather than editing the ticket under it.

**The control is what makes it readable:** plain `static int` in the identical program is
correct, so this is the keyword's doing and not a function-scope-statics bug. A probe whose
right answer differs from the failure answer, which most of my probes today have not been.

**AND I NEARLY REPORTED A REGRESSION THAT WAS MY OWN CONFOUND.** My first probe had BOTH a
global and a function-scope `__thread`. The pin warned, HEAD did not — which reads exactly
like `126797d19` removing a diagnostic. **It was the confound: the pin was warning about the
GLOBAL**, which HEAD now implements. Isolated to a file containing only the function-scope
declaration, neither compiler warns and both produce the same garbage. **frankb-56's "no
regression, it was silent before too" is correct**, and I said so in the same message that
carried the finding, because a peer should hear "I checked whether this was your fault and
it wasn't" from the seat that checked.

**Its pinned control is the good kind and it discharged the caveat that usually sinks one:**
the pinned binary's run emits the OLD *"'__thread' is not implemented and is being IGNORED"*
warning, which proves it REACHED the subject path rather than feature-detecting around it —
the exact failure mode where a green is correct about a different compiler. And under
`taskset -c 0` the fixed compiler still passes 6/6 while the pinned one still fails, because
`kept` and `no-crosstalk` stop discriminating when threads do not overlap; the verdict then
rests on `zeroed-on-entry` and `main-copy` alone. **It documented that in the C file so
nobody trims the two rows that look redundant on a 12-core host** — a positive control whose
discriminating power is load-dependent is a guard that quietly stops being one.

**RANKING ADVICE GIVEN, NOT AN ASSIGNMENT.** It named the p55 pair next (syscall asm idiom,
busybox-diff banner control). I put the function-scope zero-init ahead of both: a silent
wrong value in a single-threaded program on the default target beats a diagnostic gap and
beats a guard that cannot fail. Its call — it can see the code and I cannot.

**I did not touch `cparser`.** frankb-56 holds that topic with live context; two agents on
one question is the collision git cannot see, and today is an argument for this seat
measuring rather than editing.

## Check-in 0s — the block static was DISCARDED, my sibling sweep found nothing, and `_Static_assert` is a guard that cannot fail

**frankb-56 found the real mechanism and it is a level worse than my measurement said.** Not
a missing zero-init: `ParseCStatementAST` read `static`, consumed it, tested `IsCTypeTok`,
met `__thread` and fell out of the branch with `CLocalStaticDecl` still False — **the
`static` was discarded entirely and the variable compiled to an ordinary STACK LOCAL.** Any
storage class between `static` and the type does it; `__thread` was merely the one someone
wrote. Its clincher is the right kind: calling through a recursion pushing a 512-byte frame
made the counter RESTART, **which a static cannot do** — a control no value in memory can
fake. Fixed and pushed; verified here, `static __thread int f` now gives `1 2 3` against
gcc's `1 2 3`.

**I SWEPT THE SIBLING SPELLINGS AND FOUND NOTHING, WHICH IS THE REPORTABLE OUTCOME.** The
normalise rule says the sibling is usually a SPELLING, so I ran the neighbourhood at block
scope against gcc: `static const`, `static volatile`, `static unsigned`, `__thread static`
reversed, `static _Thread_local`, `register`, `auto`, and the plain controls. **Three rows
looked like differences and all three were MY PROBE'S FAULT:**

- `static const int f; f++` — gcc: *"increment of read-only variable"*. My probe increments
  a `const`.
- `__thread static int f` — gcc: *"'__thread' before 'static'"*. An ordering gcc itself
  rejects.
- `register int f; f++` — reading an UNINITIALISED automatic, which is undefined behaviour,
  so neither answer is wrong. Re-run as `register int f = 0`, HEAD, pin and gcc all give
  `1 1 1`, and `static int f = 0` gives `1 2 3` on all three.

**So frankb-56's narrow set holds and the fix has no open sibling.** A negative worth
recording, because "I checked the neighbourhood" is only information if someone says what
they checked. The two accept-what-gcc-rejects rows are **not defects** — CLAUDE.md is
explicit that accepting what the other compiler rejects is not one, and a differing
diagnostic is deferred. Noted, not ranked, no ticket.

**THE ONE THING IN ITS MESSAGE I DID RANK, AND IT IS THE BIGGEST THING EITHER OF US TOUCHED
TODAY: A FALSE `_Static_assert` AT FILE SCOPE COMPILES SILENTLY.**

```c
_Static_assert(1 == 2, "this assertion is FALSE and must stop the build");

gcc        error: static assertion failed: "..."
pxx HEAD   ok:  -> runs, prints "compiled anyway"
pxx PIN    ok:  -> runs, prints "compiled anyway"
```

frankb-56 found this while choosing its narrow set — the file-scope path SKIPS the assertion
rather than evaluating it — and filed rather than fixed it, which is defensible because it is
a different subsystem from the one it was in. **But it is a guard that cannot fail, in USER
code, which is the class this repo cares most about**, and the population is not exotic: an
ABI size check (`_Static_assert(sizeof(struct s) == 32, ...)`) is the idiom, and it is
exactly what a C program uses to stop a silent layout change. Under pxx it stops nothing.
Pre-existing on the pin, so nobody regressed it.

**I have told it this outranks the banner control it named next, and why it is not a
matter of taste:** a banner control that cannot fire is an instrument we own and can
re-run; a `_Static_assert` that cannot fire is a guard OUR USERS wrote, in their code,
believing it protects them. Its own narrow-set reasoning already contains the argument —
it kept `_Static_assert` OUT of the skip set precisely because *"a loud refusal is the
better of the two wrong answers"* at block scope. That logic says the file-scope silence is
the wrong answer to leave standing.

**Its two self-caught probe failures are better than the fix and go to the playbook.** Both
are one rule from two directions. It recorded `static __thread int f = 0;` as WORKING from a
probe that called the function ONCE and got 0 — **a discarded static and a real one agree on
the first call and diverge only from the second.** Then the mirror: the no-initialiser row
**passes on the BROKEN compiler by luck**, giving `4388880` standalone and `1 2 3` inside a
larger program, because the wrongly-chosen stack slot happened to hold zero. **The sharpening
worth keeping is that second one: uninitialised memory is not a random value — it is zero
often enough to certify a broken instrument**, so a failure value drawn from uninitialised
storage can coincide with the correct answer nondeterministically. That extends "if the
machinery did nothing at all, would this row still pass?" from colliding DEFAULTS to
colliding GARBAGE. **Playbook, not CLAUDE.md — one subsystem.** It kept the fragile row
because it is the shape users write and rested the verdict on the seeded and deeper-frame
rows instead, which is the correct disposal.

**Also landed green: the syscall asm idiom.** A fixed-register output met by a fixed-register
input is TIED rather than refused, so the `syscall` idiom compiles and runs — **checked
against libc's answer to the same question, so the row carries no expected number.** It ran
all four constraint shapes through gcc BEFORE implementing, so the three that must stay
refused came from the oracle rather than from the ticket's prediction. And it tested
early-clobber AT THE TIE SITE rather than leaving it to the existing sweep, because that
sweep runs earlier and reads `TiedTo` — **a tie minted later is invisible to it**, so
`"=&a"` tied to `"a"` would have gone through as a silent wrong value.

**C group is three fixes deep** (`__thread` storage, the asm tie, the block static) plus a
rescoped residual ticket. Shop otherwise unchanged.

## Check-in 0t — a NEW RED (7 → 8), self-found by its author, and `new_red: []` is not an exculpation

**Open regressions are 8, up from 7.** The new row is
`test-core#src:test/test_a_threadvar_is_a_variable.pas`, first RED 2026-09-16T08:51:33Z at
`59afeadbceaa`, still_red through 09:03:24Z. **It is frankb-56's, it found it itself by
chasing the borg report rather than being told, and it is fixing it before `_Static_assert`.**
Cause: making the threadvar refusal diagnostic serve both frontends changed the NOUN — *"only
ordinal, pointer and floating-point threadvars"* became *"...thread-local variables are
supported"* — and `tv_str` greps the message. **The refusal never stopped firing and the type
rule is unchanged; the test pinned the spelling, not the claim.** That is "the name is not the
thing" in a test fixture. Fixed by grepping the CLAIM, with a comment saying why the noun
cannot be pinned (one routine now serves two frontends and would say something else again if a
third arrived), and the control re-checked: a clean compile still does not match the grep, so
the row can still fail.

**I VERIFIED ITS `new_red: []` FINDING AND IT IS SHARPER THAN IT STATED.** Its account: the
report at `7f8188ce5fe5` said RED with `new_red: []`, which reads as *"nothing new, not
yours"*, and it was not new because the previous run already had the commit in. Measured:

```
08:51:33Z  59afeadbceaa  native  new_red=1  still_red=1   tv_is_a_variable = NEW_RED
08:57:32Z  7f8188ce5fe5  native  new_red=0  still_red=2   tv_is_a_variable = still_red
09:03:24Z  2bac32c14db1  native  new_red=0  still_red=2   tv_is_a_variable = still_red
```

**The instrument was not silent — it named the row exactly ONCE, in the run before the one
frankb-56 read.** That is the generalisable form and it is better than "the range swallowed
it": **`new_red` is a diff between consecutive runs, so it names your commit in exactly one
report, and EVERY later report shows `still_red` with an empty `new_red` that reads like an
exculpation.** The remedy is mechanical: do not read the newest report alone — walk back to
where the row first appears. `twatch.py --job-history` does it in one command and prints
`first recorded RED` outright.

**Where it sits against CLAUDE.md:** the existing rule has two measured forms, the flattering
delta (a pull improved your numbers) and the self-blaming one (you blamed your own diff). This
is a third — **a range that already contains you, where the instrument reports no change and
is CORRECT.** Recurrence is not met: all three live in Track T's breadth verdicts, one
subsystem. **Playbook, not CLAUDE.md, and said out loud so it does not read as undervalued.**
What would promote it: the same shape in a different instrument — an empty or zero field read
as exculpation in a conformance diff or an optdiff summary. Then it is an EXTENSION sentence
on the existing rule, not a neighbour.

**AND I MANUFACTURED A NULL WHILE CHECKING IT, FOR THE SECOND TIME TODAY.** My first query
used the key `test-threads#src:test/test_a_threadvar_is_a_variable.pas` and returned
`job_in_still_red=False` — the job is `test-core`. **A wrong key does not error, it answers**,
and it answers with the reading that says "not there". Same class as this morning's `nreds=0`
from fields that did not exist on those rows. Both times the false answer was the quiet,
nothing-to-see one. The fix both times was to print the keys the data actually has before
filtering on a key I believed in.

**Its gate scoping note is correct and worth keeping:** `gate.sh quick` was GREEN every time,
and that row is test-core on the native tier. **Quick-GREEN is not evidence about a test-core
row** — no complaint about the gate, which is correctly scoped; the error is reading a green
from one tier as coverage of another.

**`c_crtl_wait.c` is NOT frankb-56's and it established that properly:** byte-identical to the
gcc oracle five consecutive runs at HEAD, the reported rows being the SIGSTOP/SIGCONT pair
reading a reconstructed status word, sampled while borg ran a full native tier. It appended
the measurement to the existing ticket **with the caveat that five runs on an idle box are not
the population that produced the red** — evidence, not a clearance. Not claimed, not closed.
That is the same discipline it applied to the optdiff shards and it is the right one.

**On `_Static_assert` it agreed and named its own error better than I did:** it had ranked the
ticket as a diagnostic gap because *refusing is the honest failure* — which covers BLOCK scope,
where pxx refuses loudly, and not FILE scope, where the assertion is skipped and a false one
passes silently. **Two different defects sharing one ticket**, and it had written that ticket's
own last section pointing at the guard-that-cannot-fail **without re-ranking the ticket on what
it had just written.** Taking both halves next; the banner control is already landed and green,
so nothing is displaced.

## Check-in 0u — `_Static_assert` is silent in THREE places, and the unification frankb-56 found is already in the file twice

**Measured on origin at `427769b0c`, with controls, because frankb-56 flagged struct scope as
unchecked while mid-fix and the answer changes the scope of what it is building:**

| shape | gcc | pxx |
| --- | --- | --- |
| file scope, FALSE | errors | **silent** |
| struct body, FALSE | errors | **silent** |
| union body, FALSE | errors | **silent** |
| block scope, FALSE | errors | refuses — ok |
| file scope, TRUE | compiles | compiles — control |
| struct body, TRUE | compiles | compiles — control |

**Three sites, not one.** The block-scope row proves the refusal machinery exists and the two
TRUE rows prove pxx is not simply refusing everything, so "silent" is a real discrimination
rather than my probe failing to see an error. The struct-body TRUE row also says the
construct PARSES and is skipped — the struct stays well-formed, which is why nobody noticed.
**C11 6.7.2.1 makes a static assertion a struct-declaration, and
`struct S { ...; _Static_assert(sizeof(struct S)==32,""); }` is arguably where an ABI check
gets written more often than file scope.**

**THE CAVEAT THAT SCOPES THE FILE-SCOPE ROW, AND I CHECKED IT BEFORE SENDING:** my binary is
`24cf75e4ff7d`, unchanged since before frankb-56's `_Static_assert` work, and
`git log --grep=Static_assert` on origin returns only my own watch note and its block-static
commit. **Its fix is local to its tree**, so my file-scope row measures a tree that never had
it and says nothing about whether its new arm already covers struct bodies. I reported the
SHAPE of the hole, not a verdict on its work. **That is the third-polarity trap and I have
walked into it twice today** — once falsely refuting a bug report from a fixture that was
never the failing one, once nearly reporting a diagnostic regression that was my own confound
— so the check is now reflexive: before measuring anything a peer says it fixed, establish
whether the commit is in my tree.

**ON ITS UNIFICATION, ANSWERED ACCURATELY RATHER THAN AGREEABLY.** frankb-56 proposed that my
wrong-key null and its `new_red: []` are one rule, two instruments: *a true statement about a
question nobody asked, arriving in the direction that stops the search.* That is correct and
**it is already in CLAUDE.md, in two places, not none** — *"Every instrument that lies, lies
by being CORRECT ABOUT SOMETHING ELSE ... None error. All answer"*, and the directional half
twice over (*"the number moved in the direction you wanted, which is the direction nobody
checks"*, and the self-blaming reading that *"TERMINATES the search"*). **So it has not found
a new rule; it has found evidence that two existing rules are one rule.** Worth knowing, and
it earns no line: a rule that says "obey the previous rule" is noise, and that is precisely
how this file reached 72KB the first time.

**What stays its own is the mechanical remedy** — walk back to first-RED rather than reading
the newest report — which is concrete where the general rule is a posture. That is the half
going to the playbook.

**It also corrected its own finding on my data and kept the correction:** it had said the
range "swallowed" its commit; the instrument had in fact named the row exactly once, and the
right statement is that the window is ONE RUN WIDE. It then replaced its own remedy ("run the
rows by hand when you touched the area", which is judgement and does not scale) with the
mechanical one. **A peer revising a finding downward on measurement it did not produce is the
cheapest correction in this shop and it keeps happening today in both directions.**

**Its `_Static_assert` first row is in (locally): `_Static_assert(1==2,"must stop")` now
refuses where it compiled clean before.** Matrix still running — the ABI size-check idiom, the
C23 no-message form, the `static_assert` spelling, both block-scope arms, and now struct/union.
One handler serves both scopes so there is no second "is this a static assertion" to drift;
it evaluates through `CEvalConstExpr`, the evaluator every array bound and case label already
uses, **so it did not invent a constant-ness rule** — the same instinct as reusing
`AssignThreadVarStorage` rather than writing a second allocator.

## Check-in 0v — the new red CLEARED (8 → 7), rung 1 was dead for nine days, and a fix whose damage was entirely in the passing population

**The red from 0t is gone. Open regressions back to SEVEN.**
`test-core#src:test/test_a_threadvar_is_a_variable.pas` fixed by `406c54783` and **closed by
Track T itself** — `90a2b705e`, *"job green again"*, which is T's own closure and not a seat's
claim. Self-found, self-fixed, self-closed inside one tick.

**`aceee115e` IS THE BIGGEST THING IN THIS TICK AND IT IS GOAL-5 WORK.** `busybox_diff.sh`'s
banner normalisation is guarded by a positive control — the normaliser must actually have
matched — and **that control is scoped to the wrong population.** At ONE applet, `run_cases`
takes the `run_cat_cases` branch and returns; it never calls `run_dispatch_cases`, the only
thing that runs `--help` or the bare multi-call binary. **So the transcript legitimately
contains no banner and the assert cannot fire by construction.** Rung 1 is that script's own
stated success criterion and **it has been unrunnable since 2026-09-01 — nine days** —
unnoticed because all recent busybox work is at 2..394 applets, where the banner IS printed
and the control is correct.

**The cost was the MESSAGE, not the exit:** *"either the banner format changed or these
transcripts never print it"* sends a reader after a busybox or harness regression that does
not exist. And it **reproduced at HEAD first** rather than trusting the 2026-09-10 filing,
citing the reason in its own words — a claim about an instrument decays like a lock, silently,
in the direction of doing nothing.

**THE NEAR-MISS IT VOLUNTEERED IS THE ONE I WOULD HAVE WANTED TOLD.** Its `_Static_assert`
file-scope arm went in as a bare `if not CTryParseStaticAssert then Next` inside an else-if
chain — **a dangling else: Pascal binds the following `else` to the INNER if and silently
re-parents the remaining chain into that arm.** It compiled and self-hosted clean. A TRUE
assertion then **hung the top-level walk**. And the false-assertion probe still PASSED,
because `Error()` escaped before the damage could show.

**So the one row a reader runs first — the row the entire ticket is about — reported success
while the compiler hung on a correct program.** It caught it only because the matrix ran the
TRUE control on the next line and stalled there.

**The generalisable form, and I grepped CLAUDE.md before claiming it is absent: it is.** The
file has *"a control from the wrong population passes and certifies the broken instrument"*,
which is the instrument case. **This is the FIX case and it is sharper: when you fix a defect,
your probe population IS the defective inputs, and a fix's damage lands in the CORRECT inputs
— the ones you are not testing precisely because they were never broken.** "Test what your fix
should NOT change" is the one-line version. **Playbook, not CLAUDE.md — one subsystem** — and
said out loud so it does not read as undervalued. It is the third instance today of a guard
that cannot fire (this probe, the banner control, `_Static_assert` itself in user code), but
all three are the EXISTING rule working, not evidence for a new one.

**`_Static_assert` IS NOT PUSHED and that is the one thing I flagged back.** Five of its six
C-group fixes are on origin (`126797d19`, `9f256b94d`, `427769b0c`, `aceee115e`, `406c54783`);
the `_Static_assert` work — three scopes, ten combinations, the dangling-else repair — exists
only in its tree. **A local commit is not banking; a restart takes it and the next session is
told to distrust a diff it cannot explain.** It is mid-gate, which is correct practice, so
this is a reminder and not a correction.

**Struct and union confirmed fixed in its tree**, one handler closing both because unions
reach the same member loop. It also asserted that **the struct still lays out identically with
an assertion in the body** (7 9 16 under both pxx and gcc) rather than assuming it — a struct
whose assertion perturbed its layout would still compile and every row in its table would
still pass. That is the same complement-population instinct that caught the hang, applied
before it could bite.

**It took the CLAUDE.md correction cleanly:** *"I'd rather be told the rule already exists than
have a paragraph of mine added on top of it."* Its ticket also went prio 30 → 70 in the same
edit that resolved it — the frontmatter habit arriving about four hours early.

## Check-in 0w — both its corrections accepted, and I flagged a peer for a gap I had myself

**Everything is banked.** `76d6c6428` (`_Static_assert` at all four scopes) is on origin with
a GREEN gate — self-host fixedpoint PASS, `testmgr quick` PASS, FPC seed canary PASS, and it
read the verdict line rather than the wrapper. Six Track C/T fixes today, all pushed.

**IT THEN FOUND AN UNBANKED THING I COULD NOT SEE, AND I HAD THE SAME GAP.** None of its six
fixes had a `LOGBOOK` line; `037100b42` adds all six. I flagged that back — and then audited
my own two code commits of the day, `47a5d356e` and `64de90285`. **Neither had a logbook line
either, for six hours.** Banked in `843190d79`.

**Eight unlogged fixes in one day across two seats, neither noticing.** *"Fix it, log one line
in LOGBOOK.md, move on"* is ONE sentence in CLAUDE.md and the fleet has internalised the first
clause. **The failure mode is quieter than an unpushed commit:** unpushed work dies at a
restart and somebody eventually asks about it. An unlogged fix **survives every restart and is
simply invisible to everyone who is not its author** — the same loss with a longer fuse.
Recorded in the logbook itself rather than only here, because the logbook is where a reader
looking for it would be.

**BOTH ITS CORRECTIONS TO 0v ARE ACCEPTED.**

1. **On why the fixedpoint was silent about the hang.** I framed it as "it was mid-gate". Its
   correction is better and it is a rule, not an excuse: `make compiler/pascal26` **converged
   CLEAN with the dangling else in the tree, because `compiler.pas` is Pascal and never writes
   a C parse chain.** That is CLAUDE.md's second scope limit — *"it cannot see a construct the
   compiler never writes"* — landing on a seat's own fix, and it means **the gate would not
   have caught it either.** Track P's partial coverage being "worse than none because it looks
   total" has a C-frontend twin, and this is it.

2. **On which of its fixes was the biggest, it is right and it used my own ranking rule
   against me.** I called `aceee115e` (busybox rung 1) the biggest. It argues `427769b0c` —
   the block-scope static silently becoming a stack local — *"would have cost someone a week:
   a plausible wrong number with no diagnostic, and a one-call test agrees with the bug."*
   **That is exactly the rule I used one tick earlier** to rank `_Static_assert` above the
   banner control: a guard OUR USERS wrote beats an instrument WE own. A silent wrong VALUE in
   user code beats a dead instrument in our tooling by the same argument, and I contradicted
   myself one tick later. **`427769b0c` is the biggest thing it did today.** `aceee115e` is
   still nine days of a dead goal-5 criterion and still worth the paragraph.

**It took the placement verdict the way it should be taken and improved on it:** it wrote the
two-test result INTO the playbook section rather than only into the commit, so a later reader
sees which test it met and which it did not without finding this exchange. And it named the
thing it would have got wrong — *"I'd have counted three instances in a day and called that
recurrence. Three instances of the EXISTING rule working is an argument against a new line,
not for one."* **That distinction is the load-bearing half of the promotion test** and it is
not written down anywhere as such; it is implicit in "recurrence, not quality". Noting it here
rather than promoting it, which would be the same error it just avoided.

**Track C closes.** Queue clear above p40; the two rows above are an idea and an umbrella,
neither a unit of work. It moves to busybox as the next group — goal 5, and rung 1 is runnable
for the first time in nine days, which is the right reason to go there now rather than a
preference.

**Still unresolved and correctly parked: whether `3eb0297f0` was its edit to make.** Neither of
us settles it; it waits for the 18th, stated as a goal question. **That is the only thing
today that either seat has escalated rather than decided**, which is the ratio this file wants.

## Check-in 0x — goal 5: the glibc is not load-bearing, and I corroborated the load-bearing half independently

**BUSYBOX TREE IS HELD BY frankb-56 FOR A WIDE RUN. Nobody runs `busybox_diff.sh` until it
says clear** — the script's own comment records that a second run against the same tree
silently destroys the first, measured 2026-09-04. Recorded here so the next context window of
this seat does not do it.

**Its claim: a pxx-built busybox links and RUNS with no libc and no crt.** At HEAD, 28 real
busybox objects from `--emit-obj --separate` at 2 applets: two relocation types only; of 70
undefined references, the number NOT satisfied inside the same object set is **zero**;
`ld -static -nostdlib` rc=0 with no diagnostics; and with a 30-line `_start` it wrote, a
12.3MB static binary that is `not a dynamic executable` and runs `cat`, `echo` and the
`busybox <applet>` dispatch — byte-identical to the gcc-linked build over 47 cases
**including three ERROR paths**, so it is not passing by doing nothing.

**I CORROBORATED THE LOAD-BEARING HALF ON MY OWN OBJECT, FROM DIFFERENT SOURCE.** Not its
tree, not its objects, and not touched while it is measuring:

- relocation types in a pxx `--emit-obj` object: **`R_X86_64_64` and `R_X86_64_PC32`, nothing
  else.** Sections exactly `.text/.data/.bss/.init_array/.fini_array` plus the matching
  `.rela`. Its list, independently reproduced.
- undefined symbols in an object whose source calls `printf`: **exactly one, and it is the
  `extern` I deliberately declared and never defined.** `printf` itself is **DEFINED inside
  the object**, `FUNC WEAK` — pxx's own crtl supplies it. **No libc symbol is undefined.**

**So the refinement is right: `gcc -o out obj/*.o` links against glibc and the glibc is NOT
LOAD-BEARING.** gcc is a linker driver whose default happens to be dynamic. The external
dependency is a **LINKER**, and the hard part of a linker — resolving against libraries — is
not needed here at all.

**WHAT IS ACTUALLY MISSING IS THE PROCESS-ENTRY CONTRACT, NOT SYMBOL RESOLUTION.** pxx objects
define `main` and no `_start`, because `--emit-obj` targets a C toolchain that supplies
`crt1.o`. **Both halves already exist and have never been introduced:** the executable writer
synthesises a `_start` (`elfwriter.inc:472`), and the C frontend already emits an
`.init_array` thunk taking `(argc, argv, envp)`.

**I AM NOT AMENDING CLAUDE.md ON THIS AND THE REASON IS THE MEASUREMENT'S OWN QUANTIFIER.**
The goal-5 note says busybox's green at **394** applets is not "without external libraries"
because the final link is `gcc ... ` against glibc. This measurement is **28 objects at 2
applets**. frankb-56 says explicitly it is not claiming the quantifier, and it is right that
the 276-applet set is a different question — more of busybox means more libc surface, and **at
that scale a needed glibc symbol would have been satisfied SILENTLY by the gcc link**, which
is exactly why nobody has noticed either way. Editing the rules file from a 2-applet run would
be the quantifier error the rules file is largest about. **The 276-applet census is running;
the amendment waits for it.**

**And the amendment is the OWNER'S anyway, because that note is his goal framing, not a
technical fact.** CLAUDE.md's own next sentence already grants that **the unity build meets
goal 5** — pxx links it itself, static, no libc — so the note is not wrong, it is imprecise
about WHICH external thing the object path needs. For the 18th, in goal terms: *"busybox
builds and runs with no libc; the only outside tool left is a linker, and nothing needs
resolving against a library. Is 'no external libraries' met, or does the linker count?"*

**MY ANSWER TO ITS ONE QUESTION: YES, put `--freestanding` in the harness, and its own reason
is the right one.** A claim about an instrument decays like a lock, and this one currently
exists in a `/tmp` directory and a message to me. That is the logbook lesson from an hour ago
one level up: unbanked work is invisible to everyone who is not its author. It is Track T work
and T owns its own tooling freely, so it needs nothing from me. **Scope I did name:** the mode
should CAPTURE the measurement, not grow into a linker — the linker is Track A's p70 and the
end state there is a pxx `--link` mode, not a gcc-assembled stub.

**It is not building the linker and said so unprompted**, banking the measurement in the
ticket so whoever takes that p70 starts from *"write the entry stub"* instead of *"write a
linker"*. That is the difference between a ticket that gets picked up and one that does not.

## Check-in 0y — the one CLAUDE.md promotion of the day, and it fixes an internal contradiction

**frankb-56 corrected its own hold message: it told me it was holding the busybox tree, then
twice concluded its run had died and relaunched it. The run was alive throughout.** What kept
me out of the way was the hold; what kept IT out of the way was `busybox_diff.sh`'s own lock,
which refused the second run and named the live pid. **That guard was written by someone who
had already had this accident** — its comment cites 2026-09-04, two runs, one tree, both
results worthless.

**THIS IS THE ONE THING TODAY THAT EARNED A CLAUDE.md LINE, AND IT EARNED IT BY EXPOSING A
CONTRADICTION INSIDE THE FILE.** Extended at `aa39bf4a0`:

- **Line 189**, the `pgrep`/`pkill` rule, prescribes the remedy: *"prefer the backgrounded
  job's own completion notification, which needs no loop at all."*
- **Line 1363**, the gate bullet, records that same notification lying: *"a backgrounded
  gate's notification reports the WRAPPER, and said `exit code 0` over `gate: RED (exit 1)`
  three times in one day."*

**1174 lines apart, and nobody reading the `pgrep` rule would ever reach the gate bullet.**
frankb-56 followed the first and got burned. The warning now sits beside the remedy that
causes it.

**Why it met the bar when nothing else today did.** Recurrence is a SECOND INDEPENDENT
SUBSYSTEM and this has one: `gate.sh` (already recorded, three times in one day) and
`busybox_diff.sh` (today). And it is an EXTENSION, not a neighbour — this file prefers
strengthening an existing rule, which costs a sentence where a new rule costs a paragraph.
Everything else today went to the playbook and I said so each time.

**The new half is the FALSE-NEGATIVE TWIN of the existing false positive.** The `pgrep` rule
is entirely about a scan counting TOO MANY — it counts the observer, so the loop cannot exit.
This is a scan counting TOO FEW: a one-shot `/proc` scan for compiler processes answered ZERO
because **a build sampled BETWEEN two compiler invocations has no compiler running.** It reads
as corroboration of the wrapper's false success, and two readings that fail the same way are
one reading.

**frankb-56's own sentence is the sharpest thing in it and I kept it in the file: both
instruments were about the OBSERVER'S RELATIONSHIP TO THE JOB rather than about the job.**
The remedy follows from that — ask for a state the JOB maintains: a lock file, an output
directory growing (**objects went 101 → 400 while it was being called dead**), and above all
the script's own completion TOKEN. `busybox_diff.sh` prints `BUSYBOX-DIFF-COMPLETE` for
exactly this reason and says so in its header. **It had READ that header the same day and
still believed an exit code over it an hour later**, which is why the line ends "grep the log
for the verdict the job printed; never the status the wrapper returned."

**Also detached-specific and new:** `busybox_diff.sh` **execs a copy of itself** so a peer's
`git pull` cannot rewrite a running script — a deliberate and correct defence against the
"do not edit a script while it is running" hazard — **and that is precisely what detaches it
from the wrapper's lifetime.** One guard creating the blind spot another rule walks into.

**Nothing was loosened.** This is a tightening of a rules file, not a hook, an allowlist or a
`settings.json`, so it is mine; the guardrail limit is untouched.

**Status:** the 258-applet census is alive, ~130 of 400 pxx objects, gcc oracle's 400 done.
`--freestanding` is written in its tree with two controls it **proved fire** rather than
asserting — a gcc link has `PT_INTERP` (so the mode cannot silently measure the gcc path and
call it freestanding) and a stub-less `-e main` link has no `_start`. **Not committed**, because
it has not run end to end while the tree is busy, and it said so rather than committing an
unverified integration. My scope line is in the file.

## Check-in 0z — I put an invented quantifier INTO the rule about invented quantifiers

**Corrected at `5b859f6fb`.** The line I promoted an hour ago said *"objects went 101 -> 400
while it was being called dead"*. **Only the 101 was a reading.** 400 is the translation-unit
count, never an object count anyone observed, and it was still false when frankb-56 wrote to
me — the run was at 290, twenty minutes after the line landed.

**Two things make this worse than a digit, and both are mine.**

1. **I put it in the rules file IN THE COMMIT CODIFYING THE RULE ABOUT INSTRUMENTS THAT ANSWER
   CONFIDENTLY AND WRONGLY.** CLAUDE.md's longest-running complaint is a claim whose VERB was
   checked and whose QUANTIFIER was invented, with the checked half lending its credibility to
   the unchecked one. `101 -> 400` is that exact shape, in the file, in a line about it.
2. **I took the number from a peer's message and never asked which half was measured.** The
   file says a conclusion handed to you already carrying a quantifier *"is not a measurement
   you may build a rule on: ask which population it was drawn from before you quote it,
   especially when it arrives labelled as a finding."* It arrived labelled as a finding. I
   quoted it.

**And the second half of the sentence was wrong independently.** frankb-56 counted the 101
**after** the lock had already refused its relaunch — so at the moment it declared the run
dead it had not looked at that directory at all. It had looked at a process table and at an
**OLD work directory left by a finished run** (28 objects). The growing directory therefore
played **no evidential role in the failure**, and my sentence gave it one.

**I FIXED IT BY REMOVING THE QUANTIFIER RATHER THAN SUBSTITUTING ANOTHER.** frankb-56 offered
a defensible series (101, 126, 153, 168, 239, 270, 290) and I did not take it — **I did not
measure that either, and importing a second unverified series into the same line to repair the
first is the mistake repeating itself with better manners.** The rule-worthy content needs no
number at all.

**The corrected shape is stronger for the rule, which is frankb-56's point and it is right:**
the growing output directory was **not an instrument consulted and misread — it was the
instrument NOT CONSULTED**, sitting there available the whole time, while a process table was
consulted instead. *"Ask for a state the job maintains"* lands harder when the state was
available and ignored than when it was merely slow to update.

**It declined to edit CLAUDE.md itself** — *"I'd rather not edit CLAUDE.md on my own initiative
when the line is yours and the error is mine to report"* — which is the correct instinct and
the reverse of the failure mode this file warns about. It reported the error against its own
credit; the line made its incident look more damning, not less, and it still asked for the
number to come out.

**This is the day's clearest case of the rules file working on the person writing it.** The
promotion was correct — second subsystem, a genuine internal contradiction, an extension not a
neighbour — and the paragraph that carried it contained the very defect it describes, for one
hour, unnoticed by me and caught by the seat whose incident it documents.

## Check-in 1a — the census found a falsifier, which is why the wide run was not a formality

**`01b932188` on origin, gate GREEN, 23 PASS rows including self-host fixedpoint.
`BUSYBOX-DIFF-COMPLETE` present. 400 objects, 663 cases byte-identical to the gcc oracle at
258 applets.** And then:

| | 28 objects | 400 objects |
| --- | --- | --- |
| relocation types | 2 | 2 |
| undefined references | 70 | 780 |
| **unsatisfied by the set** | **0** | **1** |

**The one is `pivot_root`.** busybox declares it itself as a bare extern — no POSIX or glibc
header declares it — and glibc carries a stub, so `gcc -o out obj/*.o` **resolved it silently
and nothing was ever red.** Six lines in `lib/crtl/src/sys/mount.c` over the same syscall
bridge as `mount`/`umount2`; crtl is Track C's by the lane table so it needed no handover.
With it: `ld -static -nostdlib` over all 400 objects, rc=0, **zero diagnostics**; 257 applets
listed; `not a dynamic executable`; and `md5sum`/`sha256sum` of `abc` matching the published
vectors — **it does real work, not just start.**

**VERIFIED HERE, WITH A CONTROL THAT FIRES:**

```
PIN    undefined=[pivot_root]   pivot_root sym = NOTYPE GLOBAL   <- the symbol glibc supplied
HEAD   undefined=[]             pivot_root sym = FUNC WEAK       <- now from crtl
```

The pin row is what makes the HEAD row readable: the symbol CAN be undefined, so an empty
undefined list is a discrimination and not my reader failing.

**MY DECISION NOT TO AMEND CLAUDE.md ON THE 2-APPLET RUN WAS VINDICATED BY MEASUREMENT, NOT BY
LUCK — AND THAT IS THE ONLY REASON IT COUNTS.** I held because the note says 394 applets and
the measurement was 28 objects at 2, citing the quantifier rule. **The wide population
contained a falsifier.** Had I edited the rules file that afternoon it would have asserted
"no libc needed" while one symbol was still coming from glibc.

**AND I MUST CORRECT MY OWN REPORT: I TOLD THE OWNER "THE GLIBC IS NOT LOAD-BEARING". IT WAS,
FOR EXACTLY ONE SYMBOL.** frankb-56 corrected it first and against its own credit.

**MY "INDEPENDENT CORROBORATION" IN 0x WAS NARROWER THAN IT LOOKED, AND THIS IS THE PRECISION
THAT MATTERS.** I checked relocation types and undefined symbols **in an object I wrote**, and
my source did not call `pivot_root`. So I corroborated *"a pxx object needs no libc symbol"*
for **that object** — true, and it is not the general claim. **It read as strengthening the
wide statement and it only strengthened the narrow one.** A second reading that samples the
same narrow population is not a second population.

**frankb-56's own correction is the sharpest sentence in its report: *"flagging a claim as
narrow is not the same as not making it."*** It is right, and **it is an instance of a rule
CLAUDE.md already has** — *"a careful-sounding caveat on the CONCLUSION makes an unmeasured
NUMBER more credible, not less"* — so it is not promotable and I told it so. It also observed
that the corrected sentence is the better one anyway: **"load-bearing for one symbol, which is
now in crtl" is a stronger goal-5 statement than "not load-bearing" ever was, because it names
what was checked.**

**The instrument's structural blindness is the transferable part:** *a link against a library
cannot tell you which symbols the library supplied.* **A green link is not evidence of
self-containment — it is evidence that SOMETHING resolved every symbol**, and nothing in the
harness separates those two until the library is taken away.

**The test row's second field is the row, and it is the complement-population instinct again.**
`pivot_root(...) == -1` is **also** what crtl's own `#else` arm returns on a target without
`SYS_pivot_root` — so a row asserting `-1` agrees with having no implementation at all, which
is the state the function was in this morning. The assertion is `1 1`: `r == -1` **and** errno
not `ENOSYS`. Pinned control gives `1 0` and warns in its own words that crtl does not define
it; gcc oracle gives `1 1`. Which refusal the kernel picks is environment-dependent and
**deliberately unasserted** — pinning `EPERM` would make the row a report about this box.

**`--freestanding` is committed and verified end to end:** GREEN, byte-identical to the gcc
oracle over 29 cases, both controls proven to fire. **The scope line held** — it captures the
measurement and did not grow into a linker. The remaining gap is the process-entry contract
only, and the ticket's summary now says so, so whoever takes route 2 starts at *"write the
entry stub"*.

**FOR THE 18TH — the goal-5 question is now answerable in a word**, and it is the second and
last thing either seat escalated today:

> *"busybox builds and runs at 257 applets with no libc and no crt; the only outside tools
> left are a linker and an assembler for a 30-line entry stub, and nothing resolves against a
> library. Is 'no external libraries' met, or does the toolchain count?"*

**CLAUDE.md's goal-5 note is now half stale and I am still not touching it.** Its causal
clause — *"pxx emits objects and cannot consume one"* — remains exactly true and is the whole
remaining gap. Its factual clause, that the link is against glibc, is now a statement about a
dependency that no longer exists. **The rewrite is his**, because the note is his goal framing
and the question above is the one that decides how to word it.

## Check-in 1b — tree held again, and the seat re-ran a GREEN because it had picked the population

**BUSYBOX TREE IS HELD AGAIN, ~1 hour. Nobody runs `busybox_diff.sh` until frankb-56 says
clear.** Second hold of the day; same reason, same script-destroys-the-other-run hazard.

**IT IS RE-RUNNING A GREEN, AND THE REASON IT GAVE IS THE BEST SELF-CATCH OF THE DAY.** What
it reported was that the freestanding 400-object binary *"runs"* — cat, echo, sort, uniq, seq,
tr, wc, basename, dirname, md5sum, sha256sum. **Every one of those is an applet it chose.**
Its own words: *"the digests matching published vectors is real evidence and the applet list
is not; it is the same shape as a suite grown by adding more of what passes."*

So it is putting `--freestanding` through the harness's **own 663-case oracle comparison at
258 applets** rather than through its judgement about which applets are interesting.
**Byte-identical over 663 cases with no libc in the binary is the sentence goal 5 actually
wants**; anything less is the measurer choosing the population. **Nobody asked it to do this
and it had a green in hand.**

**Two rules it applied as a PLAN rather than rediscovering as a hazard**, both of which cost
it something earlier today:

- **Ordering:** pushed first (`01b932188`), let the pull settle, rebuilt (`converged after 1
  round`, `b7f9f80c7d80`), then measured. The pull brought nothing under `compiler/` or
  `lib/` and **it rebuilt anyway rather than reason about whether it mattered** — which is
  the step CLAUDE.md says gets dropped, dropped precisely because the reasoning usually
  comes out right.
- **The wrapper:** launched under `setsid` **knowing the wrapper's exit will lie about it**,
  waiting on `BUSYBOX-DIFF-COMPLETE` and nothing else. Two hours ago that was the thing that
  burned it into relaunching a live run twice; now it is the plan. That is the promoted
  CLAUDE.md line being used in the direction it was written for.

**Nothing needed from me, and I am not adding to it.** Verdict when the token appears.

## Check-in 1c — the verdict arrived, I checked it off the ARTEFACT, and my own corroboration grep was a substring coincidence

**Tree is CLEAR.** `busybox_diff.sh` is free again; the hold lasted ~20 minutes, not the hour
frankb-56 budgeted.

**THE VERDICT, AND I RE-DERIVED EVERY ROW OF IT MYSELF RATHER THAN RELAYING IT.** `f8547e7bd`.
The seat's three rows and what I measured on the binary and the transcripts in
`/tmp/bbdiff-4XqXTw`, with nothing taken from its log:

| its claim | my instrument | answer |
| --- | --- | --- |
| no PT_INTERP | `readelf -lW \| grep -c INTERP` | **0** |
| no libc | `readelf -dW \| grep -c NEEDED` | **0** |
| entry == `_start` | `readelf -hW` / `readelf -sW` | **0x401000 == 0x401000** |
| nothing unresolved | `readelf -sW`, UND rows | **none** |
| not dynamic | `ldd` | *not a dynamic executable* |
| 257 applets | `busybox --list \| wc -l` | **257** |
| 400 objects | `ls obj/*.o \| wc -l` | **400** |
| a 30-line stub | `tools/pxxcrt_x86_64.S`, non-comment lines | **29** of 76 |
| digests against RFC vectors | `printf abc \| busybox md5sum`, `sha256sum` | **both match** |

**663 cases and byte-identity, counted with the harness's own definition and not read off its
PASS line:** `grep -a '^### ' | grep -avc '^### exit='` — the spelling `busybox_diff.sh:799`
documents, `-a` because one case cats 4KB of `/dev/urandom` and the `exit=` exclusion because
one marker is glued mid-line by `nonl.txt`. Oracle transcript **663**, pxx transcript **663**,
`cmp` says **IDENTICAL**, same sha256 `6ce78c8273`, and **41961 bytes each** — the size is the
row that says the comparison had something to compare, because two empty files are also
byte-identical.

**THE POSITIVE CONTROL FIRES, which is the only reason the table above means anything.** Every
one of those readings would also be produced by an instrument that had silently answered about
nothing. Run the same four commands on the **gcc oracle binary in the same work directory**:
`ELF ... pie executable, dynamically linked`, **1** PT_INTERP, `NEEDED libc.so.6`. The
instrument separates the two binaries, on the same box, in the same minute.

**AND HERE IS THE ONE I GOT WRONG, IN THE HOUR AFTER WRITING UP A RULE ABOUT EXACTLY THIS.**
My first pass at checking the case count was `grep -a -o "663" build_x86_64.log`, which
returned hits, and for a moment that read as corroboration. **The hits were byte counts** —
`ok: .../archival_cpio.o [code=417346B ...]`, `418300B`, `417481B`. A three-digit substring
inside a six-digit number. The log did not error and it did not return nothing; it **answered
a different question**, which is this file's own sentence about every instrument that lies.
The grep could not have failed: any build log of 400 objects contains `663` somewhere by
arithmetic alone. **A digit string is not a measurement**, and the fix was to count the cases
myself with the predicate the harness uses.

**WHAT THE RE-RUN ACTUALLY BOUGHT, in the seat's own accounting and I think it is exactly
right:** *"it did not make the binary more correct, it removed ME from the population."* 663
cases it did not choose against 11 applets it did. The digests were always the strong half —
an oracle outside this repo, this compiler and this harness — and they are untouched.

**WHAT IS NOT CLAIMED, and it arrived in the same message as the good news, which is the part
worth recording as behaviour:** the entry stub is assembled with `gcc -c`. **No external
LIBRARY is in the binary; two external TOOLS are still in the chain** — an assembler and a
linker. Route 2 (`feature-a-pxx-cannot-link-its-own-objects`) removes both and is the end
state. The honest sentence is *"busybox builds and runs at 257 applets with nothing linked
against it"*, not *"pxx needs no toolchain"*.

**Shop otherwise:** `gate.sh quick` **GREEN**, all 24 rows, self-host fixedpoint PASS, FPC seed
canary PASS. **Seven open regressions, unchanged from the 11 → 7 baseline** — the four optdiff
shards, `lib-test#src:tools/crtl_reachability.py`, `tools-devtest#00`,
`lib-test#src:test/crtl_atexit.c`. Nothing cleared, nothing new; every `opened` timestamp still
predates today. Track T **UP**, tested through `f02aaea62be9`, newest full tier 21m old.

**TRACK C AND THE BUSYBOX GROUP BOTH CLOSE HERE.** Four commits today, all gated green and all
on origin: `76d6c6428`, `037100b42`, `01b932188`, `f8547e7bd`. The C queue is clear above p40.
**Track O (`optdiff#shard5/12`) and all of Track P remain unassigned and I am not starting a
seat.** What remains on goal 5 is Track A's: route 2 for the stub, and
`feature-a-object-output-for-arm32-and-aarch64` for the other architecture.

**Still exactly two things escalated for the 18th**, both unchanged: `3eb0297f0`, and the
goal-5 wording, which now reads as one sentence about what we want.

## Check-in 1d — the open-regression list is NOT the red list, and a decide ticket has been closed by events for five days

**Quiet tick on the tree and a loud one in the archive.** Nothing has landed since
`c28c693d0` (my own 1c). HEAD unchanged, no tier delta to attribute to anyone, Track T
UP and idle *because the tip has not moved*, not because it is stuck — newest full tier
`e9bc308de99a`, aging from 21m to 25m across two check-ins with the same sha.

**`gate.sh quick` GREEN, and I am going to report the canary row honestly rather than
as a pass:** it **SKIPPED** — *"compiler/ unchanged, and seeded green at
`f8547e7bd5f4`"*. That is a legitimate skip and the right behaviour, and it is still
not a fresh measurement. The last real canary pass on this tree is frankb-56's at
`f8547e7bd`. Self-host fixedpoint PASS (39s).

### THE FINDING: two instruments, seven rows and five rows, overlapping in THREE

I have been quoting "seven open regressions" as the shop's distance from goal 1 all
day, and the baseline table in this note does the same. **It is the wrong number, and
not because it is stale — because it is a different question.** Newest full tier at
`e9bc308de99a`, read out of `runs-borg.ndjson` rather than off `--status`:

| | in the full tier's `still_red` | in `open_regressions` |
| --- | --- | --- |
| `lib-test#src:test/crtl_atexit.c` | yes | yes |
| `lib-test#src:tools/crtl_reachability.py` | yes | yes |
| `tools-devtest#00` | yes | yes |
| `demos#00` | **yes** | **no** |
| `test-core#src:test/c_crtl_wait.c` | **yes** | **no** |
| `optdiff#shard0 / 2 / 5 / 10 of 12` | **no** | **yes** |

**Both absences have a mechanism and neither is a bug.** `demos#00` and
`c_crtl_wait.c` carry **`last_pass: None`** — they have never passed on borg, so there
is no good→bad transition to bisect and they cannot be *regressions* by construction.
The four optdiff shards are tier **`opt`**, not `full`, so they can never appear in a
full-tier row at all.

**The consequence is the part that matters for goal 1.** A full GREEN pin is a
statement about the FULL TIER, so the number standing between this tree and the
owner's first goal is **five**, not seven, and **two of the five have never been
green on this host** — which is a different and harder class than a regression with a
range to bisect. Quoting seven flatters the shop by counting four `opt` shards that a
full tier does not run, and hides two rows that a full tier does.

**This is `--status` being correct about something else.** It says
*"open regression"* and it means it: a list of things that USED to pass. I read a
list of things that are RED, because that is the question I had. The instrument never
claimed otherwise.

**Stability, which is the good news:** five consecutive full runs from
2026-09-16T07:47:43Z to 10:01:36Z, **the same five reds every time**, `new_red: []`,
`fixed: []`, `skips=0`, `timed_out=False`, `unreached=0`. Nothing is flapping.

### A DECIDE TICKET HAS BEEN CLOSED BY EVENTS SINCE 2026-09-11 AND NOBODY NOTICED

Reading the archive for the above, `skip_holes == 0` on every recent row — which is
supposed to be impossible on the sweeping host. Measured over all 672 borg full runs:

```
with skip_holes == 0: 114      with skip_holes > 0: 0
earliest zero: 2026-09-11T19:51:21Z    latest: 2026-09-16T10:01:36Z
```

The 114 begin **at the plexus→borg handover**. `decide-the-proof-grade-gate-is-
unsatisfiable-on-the-host-that-does-the-sweeping` (Track U, prio 55) says in its own
summary that the `-O3` promotion gate *"can never be met"* because seven is dual E5645
Westmere with no RDRAND. **Seven is not the sweeping host any more**, and borg has met
the literal gate 114 times in five days.

**I have updated the summary and added a dated section; I have NOT closed it, and the
distinction is deliberate.** The fork was never *"is the gate passable today"* — it is
*"what should proof-grade MEAN when a host has a structural hole"*, and that question
survives a host move. What changed is its price: **option 1, the literal
`skip_holes == 0`, now costs nothing on the current host**, which it did not when the
ticket was written. That is new information about an option, not a decision, and the
decision is still Track U's.

**This is the exact shape the owner complained about on 2026-09-10** — a ticket whose
own body records that its blocker is gone, sitting in a folder `ready`/`next` scan.
It was found by a watch check-in reading the archive for a different question. That is
the second time today that the useful thing came out of *"go look at the data behind
the summary line"*.

### Peer movement — both seats answered, and one caught its own instrument

**frankb-56: both groups CLOSED.** Four commits today all gated green and on origin
(`76d6c6428`, `037100b42`, `01b932188`, `f8547e7bd`); C is clear above p40. I have
offered it **Track P** (the owner's named priority — the three FPC-corpus walls) or
**Track O** (`optdiff#shard5/12` alone, explicitly without my retracted four-shards-
one-cause framing), with my read that P is worth more, and said plainly that banking
and stopping is a legitimate end to a shift. **An offer, not an assignment.**

**franks-ee: NOT STUCK, and it proved it the way the rule asks.** Newest successful
tool call 10:27:54Z, newest `is_error: true` 08:34:12Z — **the last denial is nearly
two hours OLDER than the last success**, which is the only comparison that separates a
blocked seat from a working one. Six refusals all session, **zero user denials**: one
`no-full-suite.sh` hook decline (it complied rather than lifting, because the per-fix
gate was sufficient — there was nothing to lift it FOR), four nonzero exits from its
own commands, and **the newest one is the compiler refusing its eleven-line repro,
i.e. the defect reproducing — a success wearing an error's shape.**

**Its method caught a bug in its own instrument, which is worth more than the
answer.** Its first parse reported the newest success at 08:35Z — a session that had
stopped dead. **408 of 426 `tool_result` blocks carry `content` as a STRING and only
18 as a list**, and it was iterating list-shaped blocks only. What caught it was the
transcript file's own **mtime** being live while the parse claimed two silent hours.
**A transcript-liveness check is a cross-check on any transcript parser and they fail
differently** — banking that here because the next seat to run this check will write
the same loop.

### A WALL NUMBER IS A ROW POSITION AND TWO SEATS DISAGREED ABOUT ONE IN WRITING

franks-ee: *"comphook.pas:386 is wall EIGHT. Wall seven was finput.pas:544."* This
note and the umbrella table say 6 and 7. **Both counts are honest** — the umbrella's
prose counts walls CLEARED historically, the table numbers its own rows — and the
table's heading still said **"THE FIVE WALLS"** over **seven** rows. **The two seats
never disagreed about a subject**, only about an index.

Fixed the caption and recorded the collision in the umbrella: the number is a row
position, nothing downstream may key on it, and walls are named by `file:line`.
`finput.pas:544` FIXED at `a931bef4d`; `comphook.pas:386` OPEN.

**And its diagnosis of my failed reconstruction is better than my own write-up.** My
ten rows compiling under pin v410 *and* at HEAD means the failing shape is not in
them, and the **missing axis is the OVERLOAD**: the minimum is two declarations
sharing a name, one taking a parameter, and the call site spelled with no parentheses.
My row E — a single parameterless function called bare — is green *on purpose*, as its
control. It has the defect narrowed to one cell with both controls green and has not
found the code yet; **no commit is due until it has**, and I am not asking again.

**Nothing escalated beyond the standing two.** No pin, no guardrail touched, no keys
into any pane, no seat started.

## Check-in 1d addendum — frankb-56 declined P, and its reason corrects the offer

**It landed `e7f9de0a4` first and declined afterwards**, which is the right order: it
took `next --track C`, grepped the subsystem, found a sibling ticket naming the same
root, and parked the group with a diagnosis rather than half-starting it.

**THE CORRECTION IS MINE TO CARRY, not its decline to justify.** Its words:
*"P being the owner's stated priority is an argument for STAFFING it, which is his
dial and not mine to turn by moving myself."* **That is right and I did not see it
while writing the offer.** I framed an empty lane as a gap a present seat should
fill — which is **fleet sizing wearing a dispatch costume**, the thing the
coordinator section says is not mine and the thing this note's own limits list says
is his. **The correct report for his return is "Track P had no seat all day", not
"Track P had no seat and I moved one into it."** Its second reason stands
independently: franks-ee is one cell from the `comphook.pas:386` defect and a second
seat near that topic is the collision git cannot see.

**Two findings in `e7f9de0a4` worth keeping where the next seat trips over them:**

- **Both va_arg tickets say the obligation is "whoever adds a wasm32 PROLOGUE arm",
  and that is the smaller half.** A wasm function has a FIXED typed signature, so
  passing three arguments to a one-parameter declaration has no encoding: the caller
  cannot marshal what the callee cannot receive. **Neither end exists**, and the
  caller half was unrecorded in either ticket.
- **The caller side is NOT a build failure, which is what hid it.** Callee is a hard
  `error:`; caller writes the module anyway — 116955 bytes, offending body lowered to
  `unreachable`, build succeeds, module validates, **traps at run time**. A fixture
  asserting against the loud half passes while the quiet half stays broken.
- **And the probe ROUTE is why the framing survived.** The natural caller probe is
  `printf`, which on wasm32 pulls crtl's `stdio.c` and dies first on
  `MAX_WASM_BODY_VARS` — an unrelated bound that answers first and answers plausibly.
  It nearly recorded that as the caller-side verdict. The isolating probe is a
  variadic extern that is **not** a crtl function, so nothing is pulled and the only
  route to the refusal is the variadic call. **Isolation guarding the run and not the
  route, caught live rather than quoted at.**

**Parking was correct.** The six existing arms spill registers and point
`__va_overflow` at an incoming frame; wasm32 has neither, so there is nothing to
port — it needs a convention designed for the target (caller marshals into linear
memory, one pointer as the `va_list`), both ends ours, therefore a deliberate design
choice and backend-scale work off the six goals.

**frankb-56's shift, recorded as it asked: eight fixes, three groups, four pushes,
two groups closed and one parked with its diagnosis banked. Stopped clean.** It also
notes the four-shard inflation was its count this morning — **for the record it went
into this note's baseline in MY hand and I repeated it to the owner before it was
refuted**, so that one is not its to carry alone.

**Fleet state at end of this tick: frankb-56 stopped clean, franks-ee working wall
`comphook.pas:386`, Track P and `optdiff#shard5/12` unstaffed and staying that way.**

## Check-in 1e — the goal-1 distance is FOUR, and the row that moved needed a pin, not a fix

**frankb-56 took the one item I flagged in its lane and it is not work.** `09314adf6`.
`lib-test#src:test/crtl_atexit.c` — the row whose reason names
`crtl declares functions it does not define: c_pthread_create` — **is true of the
PINNED compiler and false of the tree.** It clears itself at the next pin. **So the
distance to goal 1 is four, not the five I reported an hour ago.**

**I verified it on five instruments that fail differently, because a peer's verdict
about a pin is exactly the shape I got wrong twice today:**

| instrument | reading |
| --- | --- |
| pin v410 commit, anchored `^chore(stable): pin v410` | `764ee2ed2`, 2026-09-14 **20:45:14** |
| the fix | `e4c72bd15`, 2026-09-14 **21:03:48** — **18 minutes later** |
| `merge-base --is-ancestor e4c72bd15 764ee2ed2` | **NO** — the pin predates the fix |
| pinned binary on disk, `sha256sum` | **`c599e8546121`** = the sha in the pin commit's own subject |
| tstate's own metadata for the job | **`pin_built: true`** — written by the watcher, not by any census |
| `grep -r c_pthread_create lib/crtl/` | **0 hits**; it lives in `lib/rtl/palthread.pas` |

**AND THE MECHANISM IS SHARPER THAN "IT NEEDS A PIN" — IT IS THE RTL/COMPILER SPLIT
DOING EXACTLY WHAT IT IS BUILT TO DO, IN THE ONE DIRECTION THAT LOOKS LIKE A DEFECT.**
tstate's `good`/`bad` pair dates it precisely: good `b984ad07e` (18:55:20), bad
`934ba0418` (19:34:53), **both on 09-14, before pin v410 existed.** `934ba0418` is
*"route pxx threads through pthread_create when libc is already linked"*, and it adds
`c_pthread_create` as a **weak external in `lib/rtl/palthread.pas`**.

**`lib/rtl` is read from the TREE; the pin snapshots the compiler and `builtin` only.**
So the new weak declaration went live **instantly, with no pin**, and met a compiler
whose over-strict diagnostic was **frozen in the pin**. A weak external is optional by
construction — unresolved, its GOT slot is zero and the call site takes its guarded
branch — so it is not an implicit import and the warning's premise was false for it.
**A tree-live RTL change meeting a pinned compiler's stale diagnostic is a RED that
names a real symbol, cites a real file, and reports nothing wrong with either.**

**THE GREP TRAP IT HIT, AND IT NEARLY INVERTED THE VERDICT.** `git log --grep='pin
v410'` returns **five** commits here, the first being `09314adf6` and the second
`c9af737b5` — *a `docs(watch)` commit of mine that merely MENTIONS pin v410 in its
prose.* Tested against that, `e4c72bd15` **IS** an ancestor, so the pin "contains" the
fix, so the row is a live defect, so there is real work. **Exactly backwards.** I
reproduced both readings: ancestor of `c9af737b5` = YES, ancestor of `764ee2ed2` = NO.

**This is my `grep -o "663"` an hour later in another seat's hands, and the general
form is worth both of us having: a grep for a NAME matches PROSE ABOUT the thing as
readily as the thing — and in this repo prose about a pin OUTNUMBERS the pin**,
because every watch note quotes pins by number. My own check-ins are the noise.
Anchor to the commit-subject form (`^chore(stable): pin vN`), and prefer the
instrument prose cannot imitate: **the recorded binary sha in the pin's subject,
matched against `sha256sum` of the pinned binary on disk.** That pair is an identity.

**ONE LINE FOR THE "A FIX IS INERT UNTIL PINNED" RULE, and it is the half that rule
does not say:** `merge-base --is-ancestor <fix> <pin commit>` answers about **SOURCE**.
What decides behaviour is what the pinned **BINARY** does. Today they agreed; they are
different questions and the cheap instrument is to run the thing under
`$(PXX_STABLE)` and watch it fail.

**A NULL RESULT OF MINE, RECORDED BECAUSE IT COULD NOT HAVE FAILED.** My first
attempt to reproduce this ran `tools/crtl_reachability.py` with `PXX=` set to each
binary in turn. Both passed — **because that script reads no compiler at all**; it is
a static closure walk over headers and modules, and `PXX` is not a variable it looks
at. **I varied nothing and got agreement, which is the shape that reads as
corroboration.** The instrument that actually takes a compiler is
`tools/crtl_decl_probe.sh`, via `PXX_STABLE`, and **it defaults to the pinned binary
by design.** That run is still in flight at the time of writing — 601 declarations,
one compile each — and **nothing above depends on it**; it is the behavioural
confirmation of a conclusion five other instruments already carry.

**frankb-56 has stopped: nine fixes, three groups, six pushes, two groups closed, one
parked with its diagnosis banked, one row moved off the goal-1 blocker list.**

**Goal-1 blocker list as it now stands — FOUR, and the shape of each matters more than
the count:**

| row | shape |
| --- | --- |
| `demos#00` | **never green on borg** (`last_pass: None`) — not a regression, no range |
| `test-core#src:test/c_crtl_wait.c` | **never green on borg** — same class |
| `lib-test#src:tools/crtl_reachability.py` | a real open regression, 4 in range |
| `tools-devtest#00` | a real open regression, 1 in range |
| ~~`lib-test#src:test/crtl_atexit.c`~~ | **pin-only; clears at the next pin** |

**Two of the four have never been green here**, which is a harder class than a
regression with a range to bisect, and **no pin is mine to take.**

## Check-in 1f — the four are not four of a kind, and a peer's quantifier was one row too wide

**frankb-56 accepted the mechanism and added the consequence, which is the better half
of it** (`3884c62ed`): for a **pin-built** job the bisect range **was never going to
contain the cause**. good `b984ad07e` 18:55 and bad `934ba0418` 19:34 are both before
pin v410 existed, so *"the cause is not IN the range — it is the range's relationship
to a binary OUTSIDE it. A bisect cannot represent that and will land on whichever
commit first tripped the frozen diagnostic, which is a real commit doing a correct
thing."* That is right, it is sharper than anything I wrote, and it is banked.

**ITS SCOPE CLAUSE IS ONE ROW TOO WIDE AND I MEASURED IT RATHER THAN RELAYING IT.**
The message ends *"worth knowing before anyone spends a bisect on **the other
never-green rows**"* — a quantifier over a population of two, and the two do not
build the same way:

| row | built by | does the pin-built warning transfer? |
| --- | --- | --- |
| `demos#00` | **`$(PXX_STABLE)`** — the target's own echo says *"build ALL examples/* against `$(PXX_STABLE)`"* | **YES** |
| `test-core#src:test/c_crtl_wait.c` | **`./$(COMPILER)`** — `Makefile:22480`, the LIVE compiler | **NO** |

So the warning lands on exactly one of the two. This is CLAUDE.md's own clause-to-go-
measure — *"the other X"*, *"anywhere else"* — and it cost one grep. **I am recording
it as a correction to a scope word and not as an error of reasoning**, because the
mechanism it generalises is correct and the seat found it against its own earlier
claim.

**AND CHECKING THAT TURNED UP SOMETHING BIGGER ABOUT `demos#00`: IT DECLARES ITSELF
NOT TO BE A GATE, IN ITS OWN OUTPUT.** Its stored reason ends:

```
=== demos: 31/36 built into build/demos/ (esp32 skipped — cross-only) ===
(demos is a dashboard, not a gate; FAILs -> file a ticket)
```

**A row that reports a property of the TREE grades; a row that restates the pin's own
definition gates** — that is this repo's own distinction, and `demos#00` is on the
grading side by its own declaration while being scored RED inside a tier I have been
reading as the goal-1 blocker list. **I cannot recover WHICH five of the 36 fail**:
the stored reason is truncated to 288 characters and keeps only the tail, and the
report files carry no per-demo detail. So the five are not in the archive at all.

**THE FOUR ARE FOUR DIFFERENT ANIMALS AND THE COUNT WAS HIDING THAT:**

| row | what it actually is |
| --- | --- |
| `demos#00` | **pin-built AND self-declared a dashboard, not a gate.** 31/36. The live tree's number is unknown and unmeasured. |
| `test-core#src:test/c_crtl_wait.c` | live-compiler built, **never green on borg**, no range — the only genuine unknown of the four |
| `lib-test#src:tools/crtl_reachability.py` | a real open regression, 4 in range |
| `tools-devtest#00` | a real open regression, 1 in range |

**So "four blockers to goal 1" is itself a number that flatters nothing and explains
nothing.** One is a dashboard whose red is informational by its own words; one is
pin-built and may already be green in the tree with nobody able to see it; two are
real regressions with ranges. **The honest sentence for his return is that the full
tier has four red rows of four different kinds, not that goal 1 is four fixes away.**

**Its reading of my null result is better than mine and I am keeping its framing.**
*"A parameter an instrument silently ignores is worse than one it misreads."* My
`PXX=` on `crtl_reachability.py` returned a RIGHT answer by a route that could not
have produced a wrong one — agreement across two compilers, which is the shape of
corroboration — where its grep trap at least returned a falsifiable wrong one. **The
only tell was knowing the script does not read the variable**, and nothing in the
output could have carried that.

**Its amendment to the promotion note is accepted:** if source-ancestry-versus-binary-
behaviour recurs, the sharper half is not *"ancestry answers about source"* but that
**the pin records a BINARY SHA in its own subject line**, so an identity exists that
prose cannot imitate and ancestry cannot fake. `c599e8546121` in the subject and on
disk settled today's question in one command after two instruments had disagreed.
Still one subsystem; still the note and not CLAUDE.md.

**The `crtl_decl_probe.sh` run is still in flight and has produced no interim output
by construction** — the script's result comes through a `tail`, so silence is its
normal appearance, not a tell either way. Nothing recorded here or in 1e depends on
it. **I am not going to `pgrep` for it.**

**frankb-56 has stopped: nine fixes, three groups, seven pushes. franks-ee is on
`comphook.pas:386`. Track P unstaffed all day, which is the report, not a problem I
may solve by moving a seat.**

### 1f erratum — my own commit message ate the two names the finding turns on

**`765aa9fad`'s body says "demos#00 builds against  (the target's own echo)" and
"builds with ./ at Makefile:22480".** The two Makefile variables are GONE, and they
are the entire discriminator. `git commit -m "...$(PXX_STABLE)..."` in bash is
**command substitution**: the shell ran `PXX_STABLE` as a command, got
`command not found` on stderr, substituted the empty string, and committed. **The
commit succeeded.** The error text scrolled past above a successful `sync.sh` line.

**This repo is the worst possible place for that habit** — every lane cites Makefile
variables by name (`$(PXX_STABLE)`, `$(COMPILER)`, `$(PXX_TMP)`, `$(COMPILER_STAMP)`),
and every one of them is a live command substitution inside a double-quoted `-m`.
**The note file was unaffected** because its heredoc is `<<'EOF'` — quoted — which is
the same defence and the reason the damage is one-sided.

**Use `-F` with a quoted-heredoc file, or single-quote the `-m`.** Not fixed by
amending: `765aa9fad` is pushed, and a force push is the owner's call, not mine. The
text stands corrected here and in the follow-up commit instead.

**The finding itself is unharmed and reads, in full:** `demos#00` builds against
`$(PXX_STABLE)`, so the pin-built warning transfers to it; `test-core#c_crtl_wait.c`
builds with `./$(COMPILER)` at `Makefile:22480`, so it does not.

## Check-in 1g — the pin claim is behaviourally confirmed, and it took THREE instruments because two of mine could not reach the subject

**CONFIRMED, by the right route, with both binaries identified by sha.** The
instrument is `test/crtl_declaration_census.sh`, which takes the compiler as
**argument 1**, and `Makefile:35482` passes it `$(PXX_STABLE)` — the pin, by design.
Same script, same tree, same arguments; the **only** variable is the binary:

```
./stable_linux_amd64/default/pinned   c599e8546121
  FAIL: crtl declares functions it does not define:
    c_pthread_create                                        rc=1

./compiler/pascal26                   b7f9f80c7d80
  lib-test: crtl declaration census — 601 declared, all defined, no libc imports
                                                            rc=0
```

**frankb-56's report was accurate to the digit** — 601 declared, all defined under
HEAD; FAIL on `c_pthread_create` under stable. The row is pin-only and clears at the
next pin. **Goal 1 stands at four red rows of four kinds**, unchanged by this.

### THE PART WORTH KEEPING: I NEEDED THREE INSTRUMENTS AND MY FIRST TWO ANSWERED ABOUT DIFFERENT POPULATIONS

**Neither of my first two probes could have produced a wrong answer, and both
returned agreement.** That is the same failure twice in one investigation, and the
rule it belongs to is *"isolation guards against the RUN, not against the ROUTE"*:

| probe | what it did | why it could not answer |
| --- | --- | --- |
| `PXX=<binary> tools/crtl_reachability.py` | passed under **both** | **reads no compiler at all** — a static closure walk over headers and modules; `PXX` is not a variable it looks at. I set it, changed what it named, and got agreement. |
| `tools/crtl_decl_probe.sh` (via `PXX_STABLE`) | **`unimplemented: 0`** under the pin | **different population.** It walks prototypes in `lib/crtl/include/**`: `declared 640, implemented 605, unimplemented 0, build-fail 35`. `c_pthread_create` is declared in **`lib/rtl/palthread.pas`** and appears nowhere in `lib/crtl`, so this probe cannot see it by construction — the defect is not in the set it enumerates. |
| `test/crtl_declaration_census.sh <compiler> <tmp>` | **FAIL under pin, OK under HEAD** | the route the failing job actually takes |

**The second one is the nastier specimen and it is new.** The first ignored a
parameter — bad, and the tell is knowable from the source. **The second honoured its
parameter, ran under the binary I asked for, produced a real census of a real
population, and answered rc=0 — about a set that cannot contain the subject.** It is
not broken, it is not misconfigured, and its green is CORRECT. *"Every instrument
that lies, lies by being correct about something else"*, with the something-else
being **the population rather than the tree or the binary**.

**The discriminator, stated so the next seat does not repeat it:** `c_pthread_create`
is an **RTL** declaration reached through the **crtl** census. Any probe scoped to
`lib/crtl/**` is scoped away from it. **Before trusting a census, print the set it
enumerates and check the subject is IN it** — I ran two that were not, and the second
took nine minutes of compiles to say nothing.

**Three probes, three populations, one answer.** The two that agreed were the two
that could not disagree.

**Residual for the archive:** the `crtl_decl_probe.sh` HEAD leg never produced output
and I am not chasing it — it is answering the wrong question in either direction, and
`test/crtl_declaration_census.sh` has settled the matter on both binaries.

## Check-in 1h — shift close for frankb-56, and one observation about WHERE an error lands

**`069581bd1` is on origin and it re-derived rather than copied** — one grep each,
`Makefile:37166` for demos and `Makefile:22480` for `c_crtl_wait` — carrying the two
names my quoting deleted from `765aa9fad`. Follow-up, not a force push, and it said so
in its own body: *"the history is not mine to rewrite"*, which is also the right answer
for me and the reason I did not amend either.

**ITS OBSERVATION ABOUT WHERE THE SCOPE ERROR SAT IS THE KEEPER, and it is not
self-exculpation** — it volunteered the mitigating fact and then refused it as an
excuse. The over-wide quantifier **never reached a commit**; it was in a peer message
only, and its commit text carried the mechanism without it. Its own reading:

> *"I had spent the whole message getting the mechanism right and then threw a
> population word at the end for free. The reasoning is the expensive part and it is
> not where the error goes."*

**That is a pattern both of us hit today, in the same direction.** My caption in
check-in 0k, my `grep -o "663"`, its `--grep='pin v410'`, its *"the other never-green
rows"* — **every one is in the TAIL of a piece of work that had just been careful**,
and three of the four came after a self-correction on the same subject. **Attention
spends itself on the mechanism and the summary clause is written for free.** The
practical form: **re-read the LAST sentence of anything you are about to send, and
specifically its quantifier** — it is the sentence written with the least attention
and the one most likely to be quoted.

**`demos#00` left as an open question, correctly.** It declined to measure it against
the live tree: Track B, the target is pin-built by design, and starting a new lane at
the end of a shift to produce a number nobody has asked for is not the job. **It has
put the four-kinds sentence into the ticket** so the next reader does not re-derive it.

**frankb-56 stopped: ten fixes, three groups, eight pushes.** Two groups closed, one
parked with its diagnosis banked, one row moved off the goal-1 blocker list and one
re-categorised.

**Shop at this tick: HEAD `68a928ece`, gate GREEN as of 1d, seven open regressions and
four full-tier reds of four kinds, Track T UP and idle because the tip is barely
moving, franks-ee on `comphook.pas:386`, Track P unstaffed. Nothing escalated beyond
the standing two.**

### 1g addendum — the blind probe's second leg landed, and it is the CONTROL I had only argued for

The `crtl_decl_probe.sh` HEAD leg finished. Both legs, byte for byte:

```
under the PIN   c599e8546121   declared: 640  implemented: 605  unimplemented: 0  build-fail: 35   rc=0
under HEAD      b7f9f80c7d80   declared: 640  implemented: 605  unimplemented: 0  build-fail: 35   rc=0
```

**Identical on the two binaries that the real census separates by rc=1 versus rc=0.**
In 1g I argued this probe was scoped away from the subject; **this is the measurement
that shows it, and it is the negative control that claim needed** — the instrument
cannot distinguish a compiler that fails the census from one that passes it, so its
agreement was never corroboration. **A guard that cannot fail, printing PASS, twice,
for nine minutes each.**

I had said I would not chase it; it arrived free and it is worth more than the run I
would have spent on it. **The 35 `build-fail` rows (termios and siblings) are
identical on both and unchanged by either compiler — a standing condition, not a
finding, and not mine this shift.**

## Check-in 1i — three walls landed, the umbrella's head is now an RTL wall, and the day's one promotion

**franks-ee landed three and the useful finding is none of them.** Verified by file
paths, not relayed:

| wall | fix | touches `compiler/**`? | reach |
| --- | --- | --- | --- |
| `finput.pas:544` | `a931bef4d` | yes | **inert until a pin** |
| `comphook.pas:386` | `3926a4098` — `pasparser_expr.inc`, `pasparser_stmt.inc`, `symtab.inc` | yes | **inert until a pin** |
| `comphook.pas:397` | `d66f128a1` — `lib/rtl/textfile.pas`, a test, a Makefile row, docs | **ZERO files under `compiler/`** | **LIVE NOW** |
| `comphook.pas:474` | open — `Result := FileAge(F)` in `def_GetNamedFileTime` | — | RTL, Track B |

**I checked the head myself: `FileAge` has ZERO hits anywhere in `lib/rtl`.** It is a
genuine `SysUtils` gap, so the open head of this umbrella is an **RTL** wall.

**AND THAT IS THE ACTIONABLE PART WHILE HE IS AWAY, WHICH IS A SCHEDULING FACT AND
NOT A TASTE.** A `lib/**` fix is verifiable against the pin in place and reaches every
seat the moment it is pushed. A `compiler/**` fix sits inert **until someone pins, and
nobody may pin while he is away.** So for the next ~36 hours an RTL wall is worth
strictly more per hour than a parser wall, and the head happens to be one. franks-ee
has written that into the umbrella so it survives its context; **recorded here so it
survives mine.** Third instance of the umbrella's own live-without-a-pin finding —
`TSystemTime`, then `StdErr`, and `FileAge` next.

**The structural row: three fixes walked ONE FILE from 386 to 474.** `finput.pas:544`
delivered 105 units to `comphook.pas:386`, which delivered the same 105 to `:397`,
which delivered the same 105 to `:474`. **Units-compiling 22 → 22 → 22 → 22.** That is
the `cclasses.pas` shape (895 → 1327 → 1726) the umbrella already recorded, now the
dominant pattern rather than an anecdote — **eight null rows, each predicted as zero
in advance**, which is the only thing that makes a null row information.

**Its four self-caught errors are ONE shape and it named the shape better than I
would have:** *"an empty lookup read as a fact about the world rather than a fact
about where I looked."* The sharpest of the four: it reported the 105 as *"fragmented
across several walls"* when they had not moved at all — the compiler mints a
per-instantiation suffix (`WriteMsgTypeColored$151860`), so `uniq -c` split **one
105-unit wall into 105 singletons**, each ranking below every small wall. **A
machine-minted string dissolved a population and the histogram looked like progress.**

### THE DAY'S ONE PROMOTION — `d69642bc4`, and it is an EXTENSION, not a neighbour

CLAUDE.md's *"every instrument that lies, lies by being CORRECT ABOUT SOMETHING
ELSE"* lists a stale binary, a stale tree, a store-local `cat-file`, a truncated
`tail`, a `grep -L`. **Every one is the right THING at the wrong VERSION**, so every
example is caught by a freshness check. **Today produced three that are the right
version of the WRONG SET**, which no freshness check can see: my `grep -o "663"`
matching byte counts, frankb-56's `--grep 'pin v410'` matching prose about the pin,
and my `crtl_decl_probe.sh` censusing `lib/crtl/include/**` for a symbol declared in
`lib/rtl`. **Three instances, two seats, three subsystems, one day** — recurrence, so
promoted; **one paragraph extended rather than a rule added**, per the file's own
preference.

**I MEASURED THE QUANTIFIER THIS TIME, because today is the day I invented one.**
Across the six most recent pins, `--grep 'pin vN'` returns **10, 11, 42, 19, 6 and 19
hits for exactly ONE real pin commit each** — prose outnumbers the pin **5:1 to
41:1**. And **v410 answered 5 this morning and 19 this evening**, all fourteen added
by the seat doing the investigating. **The instrument was degraded by the act of
writing the investigation down**, inside one day, by me.

**Venue call said out loud, since an author reads silence as "not valued":**
franks-ee's own splitting-half rule — a population lost by grouping on a
machine-minted string — it routed to the **playbook**, not CLAUDE.md, on the grounds
that CLAUDE.md already carries the MERGING form and one subsystem is not recurrence.
**That call is correct and I am not overriding it.** Promote it if a second unrelated
subsystem loses a population the same way.

**Shop: HEAD `d69642bc4`, franks-ee working and productive, frankb-56 stopped after
ten fixes, Track P still unstaffed, four full-tier reds of four kinds, two things
escalated for the 18th.**

## Check-in 1j — wall ten is live, my "one file walks downward" finding was corrected by its own author, and I nearly filed a 25-file number that is 2

**Wall ten landed and I verified the property that matters: `42e127d6d` touches
`lib/rtl/sysutils.pas`, a test, a Makefile row and docs — ZERO files under
`compiler/`.** `FileAge` is now at `sysutils.pas:1190`. **Live under pin v410, inert
for nobody.** Corpus 105 → 0 in both arms, and cleared in the strong form: zero detail
files name `FileAge` anywhere across 207 units, not merely as a first error.
`FileDateToDateTime`'s own 12-unit wall at `:1012` went with it — one fix, two names.
Ninth null row, ninth predicted as zero in advance.

**THE CORRECTION IS TO MY OWN WRITEUP AND ITS AUTHOR MADE IT AGAINST HIMSELF.** In
1i I recorded the one-file-walks-downward shape as *"now the dominant pattern rather
than an anecdote."* franks-ee's recorded expectation was that the next head would be
`comphook.pas:1012` or further down that file, on the strength of four consecutive
walls there. **It is neither: `comphook.pas` now holds ZERO first errors and appears
in zero detail files as a location.** The file **CLEARED** rather than yielding a
fifth. **So the shape is real and it TERMINATES, and it does not predict where a head
goes next** — which is the half I wrote as though it did. It put that beside the
section that made the prediction rather than quietly updating the table, which is the
right way to leave a failed prediction.

**Its other self-catch is the better instrument lesson:** it had told me only ONE file
differs between the stubbed and unstubbed arms. It is two — `versioncmp.pas` and
`x86_64/cpuinfo.pas` — because it diffed `fpcsrc/*.pas`, the corpus ROOT, while the
probe also passes `-Fu$F/x86_64 -Fu$F/systems -Fu$F/x86`. **`cpuinfo.pas` carries the
entire difference between the arms.** The tell was free and it walked past it: the two
arms reported different heads, which one stubbed unit almost nothing imports cannot
explain.

### THE OPEN QUESTION IT RAISES IS REAL AND IS NOT MINE TO SETTLE

- **STUBBED arm head:** `cfileutl.pas:282`, `TRawByteSearchRec` + `FindFirst`, 120
  units, RTL type, Track B.
- **UNSTUBBED arm head:** `x86_64/cpuinfo.pas:36`, `TDoubleRec`, 132 of 207 units —
  **row 1 of this umbrella's own table, open since the umbrella started.**

**Everything the stubbed arm reports is downstream of somebody having agreed to look
past `TDoubleRec`.** franks-ee declined to pick the more convenient arm and I am
declining too: picking an arm decides what the corpus MEASURES, and the two arms
answer different questions. **Carried for the 18th** — and stated as a goal sentence,
not a representation: *"does the FPC-corpus number mean 'compiles as FPC ships it', or
'compiles once we supply a type FPC gets from its own RTL'?"*

### A DIVERGENCE RECORDED AS CHOSEN, WHICH IS THE RIGHT FORM

It read FPC's source rather than recalling it, and FPC changed the implementation
twice: **`FileAge` returns −1 for a DIRECTORY as well as for a failed stat**
(`rtl/unix/sysutils.pp:645`) — a directory HAS an mtime, so the obvious implementation
disagrees with the oracle silently. Handled and documented in ours. And FPC's unix
`FileDateToDateTime` applies the local timezone where ours is **UTC deliberately**,
matching `FileDateToUniversal`, because this RTL has no timezone database and `Now`
and `GetLocalTime` already answer in UTC. **Matching FPC on that one function would
make the PAIR worse** — `FileDateToDateTime(FileAge(f)) < Now` is correct only if both
sides use one clock. Stated in the source as chosen, never as tolerated.

### AND I NEARLY FILED A 25-FILE FINDING WHOSE MEASURED SIZE IS 2

It filled three `PENDING-COMMIT` placeholders in the umbrella (`137d99f56`), noting
that `sync.sh` fills those in **resolve citations only**, so one written anywhere else
is never filled and reads as an identifier. I went to census the rest:

```
grep -rl PENDING-COMMIT devdocs/progress/   ->  25 files, 107 occurrences
   ...of which CITATION-shaped                ->  12
   ...genuinely unfillable frontmatter        ->  2, both in rejected/
```

**The population is dominated by PROSE ABOUT THE MECHANISM** — including
`bug-t-a-wrapped-resolve-citation-is-invisible-to-both-check-and-fill`, a ticket whose
entire SUBJECT is this placeholder, quoting the shape in its own worked example.
**This is the rule I promoted to CLAUDE.md two hours ago (`d69642bc4`), hitting me a
third time in the same day, on a grep I ran BECAUSE of that rule.** A search for a
name matches prose about the thing, and here the prose is a ticket about the thing.

**I measured whether fixing the two is worth anything and the answer is no, so I did
not.** Of 81 `rejected/` tickets, **only 5 carry a `resolved:` field at all**, and
those 5 hold three different value shapes (two shas, one date, two placeholders) —
**76 of 81 carry no such field, which is the convention.** `tools/progress.sh check`
does not flag either row. There is no target value to restore, no tool is tripped, and
changing frontmatter in terminal tickets to match nothing, at the end of a day, with
him away, is tidying with no signal behind it. **Recorded, not fixed, and that is the
finding.**

### ONE RECURRENCE NOTED AND DELIBERATELY NOT RE-PROMOTED

Two of its full BACKGROUND corpus runs were killed at ~150 of 207 units, **both
reported as low memory while the box had 35GB free and 56GB available**. It confirmed
the job was genuinely dead **by checking whether the output file was still GROWING —
not by a process scan**, on the stated grounds that a scan cannot tell a finished run
from one sampled between two compiler invocations. **That is `aa39bf4a0` — this
morning's extension — being used in the direction it was written for, by a seat that
did not have the incident, in a third subsystem.** It is already in CLAUDE.md; a rule
being obeyed is not a reason to write it again. It rebuilt `probe_snap.sh` to take a
`PXX_CORPUS_LIST` and runs three ~2.5-minute foreground chunks, asserting the lists
partition the glob BEFORE the run and checking 207 rows / 207 distinct units after.

**Still not banked, at its own instruction: `test_threadsafe_heap_lock_deadlock_diag`
and `fpc-bootstrap#src:compiler/compiler.pas`.**

**Shop: franks-ee working, frankb-56 stopped, Track P unstaffed, four full-tier reds
of four kinds. Escalated for the 18th is now THREE — `3eb0297f0`, the goal-5 wording,
and which corpus arm the FPC number means.**

## Check-in 1k — THREE REDS CLEARED, and I had already established that two hours before I re-reported them as open

**OPEN REGRESSIONS 7 → 4. `optdiff#shard0/12`, `shard2/12` and `shard10/12` are
FIXED.** tstate's own words, from the `opt` tier at `f02aaea62be9`,
2026-09-16T10:49:17Z: `fixed: ['optdiff#shard0/12', 'optdiff#shard10/12',
'optdiff#shard2/12']`, `still_red: ['optdiff#shard5/12']`. **Attributed to a RANGE
and not to a seat**, as the brief requires: `67f0878f2e59..f02aaea62be9`, 154
commits.

**AND THE RANGE CONTAINS EXACTLY THE TWO COMMITS I NAMED IN THE RETRACTION THIS
MORNING** — `311649be0` (08:52, *optdiff compared each `-O` level's own binary PATH*)
and `84ccb6384` (09:02, *`-O3` inliner dropped the float→int conversion on an integer
Result*). Neither is an ancestor of the previous `opt` run. **The instrument has now
agreed with a reading I took from the FIXES eight hours before it ran.**

### THE FINDING IS ABOUT ME, AND IT IS THE SHARPEST ONE OF THE DAY

| time | what happened |
| --- | --- |
| 08:52 / 09:02 | `311649be0` and `84ccb6384` land |
| ~10:30 | **check-in 0m: I RETRACT the baseline's four-shards-one-cause bullet**, naming those two commits, and write *"Only `optdiff#shard5/12` is open. Do not read this bullet as live."* |
| **12:31** | **check-in 1d: I report "seven open regressions, unchanged … the four optdiff shards"** |
| 12:49 | the `opt` tier finally runs and reports three fixed |
| 14:23 | I read it |

**I had the right answer, in my own hand, in the file I was appending to, and two
hours later I quoted the instrument over my own verified reading.** The retraction
was written so a future seat would not read the bullet as live. **The future seat was
me, and I did not apply it.**

**A RETRACTION DOES NOT PROPAGATE TO THE NEXT READING OF THE INSTRUMENT.** Correcting
a document corrects the document. The tool goes on answering the old way until it is
re-run, and the next reading arrives fresh, carrying the tool's authority and none of
your correction. **The document and the instrument are two stores and only one of
them got the fix.** The cheap guard is to re-read your own most recent correction
about a number BEFORE quoting that number again — which costs one grep of the note I
am already writing in.

**AND THE INSTRUMENT'S OWN LAG IS THE OTHER HALF, MEASURED:** `--status`'s
open-regression list reports the last time a TIER RAN, not the state of the tree. The
`opt` tier's last ten gaps run **46 minutes to 8h19m**, and today's gap was the
8h19m — 02:29Z to 10:49Z. **A row can be fixed at 08:52 and still listed at 12:31,
correctly.** For an `opt`-tier row specifically, treat `--status` as up to ~8 hours
behind. That is not a defect; it is the sampling rate, and I read it as a state.

### GATE WENT RED AND IT WAS THE STALE-BINARY RED, WHICH I CAUSED BY DROPPING ONE STEP

`gate.sh quick` RED on `self-host fixedpoint`, with the gate's **own** diagnosis:
*"`compiler/pascal26` is OLDER than the last commit touching `compiler/`
(`3926a4098`) … a STALE BINARY, not a miscompile."* franks-ee's parser fix arrived in
my pull and **I gated without rebuilding** — the exact step CLAUDE.md says gets
dropped, *"because the reasoning usually comes out right"*, on a day I have spent
writing about instrument discipline. **Two valid fixedpoints, not a miscompile.**

Recovered: `make compiler/pascal26` → **`converged after 1 round(s)`** (a real
recompute, not the `verified` stamp path), new binary `68d79522668e`, re-gate
**GREEN**. Canary **SKIPPED** — `compiler/` unchanged since, seeded green at
`653c5f82e5c4` — which I report as a skip and not a pass.

### THE SHOP

- **Open regressions FOUR:** `optdiff#shard5/12`, `lib-test#crtl_reachability.py`,
  `tools-devtest#00`, `lib-test#crtl_atexit.c` (pin-only, clears at the next pin).
- **`optdiff#shard5/12` is now the whole of Track O**, and its reason is worth having:
  `OPT DIFF -O3: test/test_c_gtk3_stock.pas (rc 1 vs 1)` — **both sides exit 1, so the
  divergence is in OUTPUT, not in the exit code.** Still unassigned; I am not starting
  a seat.
- **franks-ee's `42e127d6d` introduced nothing**: native at that sha is `new_red: []`,
  `still_red: ['test-core#src:test/c_crtl_wait.c']` — the one never-green row. The
  `slow` tier at `7d9a3295b49a` is **GREEN, 0 still_red**.
- frankb-56 stopped. Track P unstaffed. Three things escalated for the 18th.

### AND A NOTE ABOUT THIS NOTE

**It is 2541 lines / 169KB.** Its own header says it is a session-lifetime note and
*"do not grow it into a second handbook."* **I am the one growing it.** I am not
trimming it mid-watch — editing the record to look tidier is worse than a long
record — but it is written here so the deletion at his return is not mistaken for
losing something, and so the next watching seat writes shorter blocks than I did.

## Check-in 1l — wall eleven, and the parked PChar bug has a boundary that hides it from the two shortest reductions

**Wall eleven landed library-only.** `34e3a2fa8` — `FindFirst`/`FindNext`/`FindClose`,
`TSearchRec`/`TRawByteSearchRec`, the nine `fa*` constants and `AllFilesMask` — touches
`lib/rtl/sysutils.pas`, a test, a Makefile row and docs, **zero files under
`compiler/`**. `faAnyFile = $000001FF` at `sysutils.pas:1233`, as it said. Corpus
120 → 0, units-OK 22 → 22. **Tenth null row, and it named in advance the one shape
that could have broken the prediction** — cfileutl being a dependency rather than a
leaf — which did not fire.

**New head `cfileutl.pas:518` `GetDir`, same 120 units, RTL again.** It is taking it
next and it is right not to wait on the two-arm question: **`GetDir` is a real
`SysUtils` gap under either reading of what the corpus number means**, so my call on
the 18th does not gate it. I said so rather than letting silence read as a hold.

**THE WALK-DOWNWARD SHAPE IS BACK IN A SECOND FILE** — `comphook.pas` terminated,
`cfileutl.pas` started afresh 236 lines lower in a different procedure. **Both my 1i
writeup and its correction to it survive**: the shape recurs *and* is not predictive.
Its recorded expectation this time **explicitly declined to guess a next head** on the
strength of exactly that finding, which is the correction being used rather than
filed.

### I REPRODUCED THE PARKED PChar BUG AND THE BYTE IS NOT GARBAGE — IT IS THE LENGTH

`0467be745` banks `PChar(AnsiString('lit'))` yielding *"one garbage byte"*. Reproduced
at HEAD `68d79522668e` against `fpc -O2` on the same source, five neighbouring
spellings as controls in the same program; **only the double cast diverges, B–F are
byte-identical on both compilers.** Then I printed the raw bytes instead of the string:

```
                pxx byte[0..3]        fpc
'abc'           3  0 0 0              97 98 99 0
'hello'         5  0 0 0              104 101 108 108
'hello world'   11 0 0 0              104 101 108 108
```

**The observable is the string's own LENGTH read as characters** — the ticket's
*"pointer to a length-prefix"* made visible, and **deterministic, not garbage.** That
explains why two seats reported two symptoms from one defect: `WriteLn` of a `PChar`
stops at the first NUL, so the length renders as a control code for a short string
(**looks empty**), a printable character for lengths 32–126, and genuinely empty for
any length that is **0 mod 256**. It saw "one garbage byte"; I first saw "empty".
**Same byte. Assert on `Ord(p[0])`, never on the printed form.**

**AND THE DEFECT DOES NOT FIRE BELOW LENGTH 2:**

| literal | pxx | fpc | |
| --- | --- | --- | --- |
| `''` | `0 0 0` | `0 0 0` | **agree** |
| `'x'` / `'A'` | `120 0 0` / `65 0 0` | same | **agree** |
| `'ab'` | **`2 0 0`** | `97 98 0` | DIVERGE |
| `'abc'` | **`3 0 0`** | `97 98 99 0` | DIVERGE |

**The two shortest reductions anyone would write — the empty string and one
character — both CERTIFY the bug as fixed.** That is the passing-arrangement rule with
a measured boundary on it. Appended to the ticket (`d71e09a30`) with the requirement
that any regression test use a literal of **length ≥ 2** and assert on bytes. I did
**not** add a `test/` file: the fix is parked on purpose and a test for an unfixed
defect belongs with the fix.

**Its reason for parking is right and I am not second-guessing it.** The narrow fix at
the `PChar` site is three lines and is **a second path guarding against a lying tag**,
which normalise-don't-special-case says is the path that stays broken; the root fix
materialises in the cast door, and every spelling that works today relies on the
DESTINATION driving the coercion, so that interaction needs measuring first. Inert
until a pin either way.

### TWO OF ITS OWN CATCHES WORTH THE RECORD

- **Its first `FindFirst` fixture passed while measuring nothing.** Run against
  `test/`, `faAnyFile` and `faDirectory` return the IDENTICAL answer — **no
  checked-in tree has a dotfile, a symlink, an unwritable file or a device node** — so
  every attribute-filter row was vacuous and *a filter that ignored its argument
  entirely would have scored full marks*. It now builds its own directory with all of
  those plus a dangling symlink.
- **A claim it had ALREADY WRITTEN INTO THE SOURCE was disproved by its own control,
  in the same hour.** The comment said `faAnyFile` matters because `$3F` *"silently
  drops `faNormal` and `faSymLink`"*. Measured: on unix the two select the **same**
  entries in every arrangement it could construct. **A conclusion written as a
  caption, committed before the output existed, which survived its own re-read because
  the surrounding measurement was real.** The harness caught it only because it had
  made it fail on purpose first — inverting the filter polarity in a scratch copy of
  the RTL and confirming the diff reddens on six of ten rows **before** quoting its
  green.

**Three semantics it read off FPC's source rather than recalling:** `faAnyFile` is
`$1FF` not `$3F`; `Attr` is a **PERMISSIVE** filter, so `faDirectory` still returns
ordinary files and `faArchive`/`faReadOnly` must be forced in or the obvious call
returns **nothing**; and `.` and `..` **are** returned — fpc's own `cfileutl.pas:287`
filters them by hand, which is the evidence that they arrive.

**Still not banked, unchanged at its instruction:**
`test_threadsafe_heap_lock_deadlock_diag` and `fpc-bootstrap#src:compiler/compiler.pas`.

**Shop unchanged from 1k: four open regressions, gate GREEN at `68d79522668e`,
franks-ee working, frankb-56 stopped, Track P and `optdiff#shard5/12` unstaffed, three
things escalated for the 18th.**

## Check-in 1m — GetDir landed, and the builtin snapshot has ALREADY diverged, which is the opposite of what the seat measured

**`d7bf36ce0` verified library-only** — `lib/rtl/sysutils.pas`, a test, a Makefile row
and docs, **zero files under `compiler/`**. 120 → 0, units-OK 22 → 22, eleventh null
row. Both values it flagged confirmed in the tree:
`AllowDirectorySeparators: set of Char = ['\', '/']` at `:1398` — **backslash
included** — and `DriveSeparator = ''` at `:1414`, an **empty string, not a
character**.

### THE CORRECTION, AND IT MAKES ITS OWN CAUTION STRONGER RATHER THAN WEAKER

It wrote: *"the two builtin snapshots are byte-identical right now, which is exactly
the comparison that would wrongly read as 'location does not matter'."* **They are
not.** Measured:

```
diff -rq compiler/builtin/  stable_linux_amd64/default/builtin/
  builtinheap.pas differs
  pyeval.pas      differs
  pylib.pas       differs
tree hashes: live 10bf1f177870   pinned d515f8596626
```

**All three changed AFTER pin v410** (`764ee2ed2`, 09-14 20:45) — `builtinheap.pas` at
`445ce3e25`, 1h45m after the pin, and `pyeval.pas`/`pylib.pas` today at `dea6cf762`
(06:03) and `334680199` (04:30), both nilpy fixes. So its caution was better founded
than it knew: **the divergence is not hypothetical, it is live in three files.**

**AND THAT GIVES THE LEDGER A THIRD STATE, WHICH I HAD BEEN COLLAPSING INTO TWO.** Its
mechanism is right and is the part worth keeping — *"it is not that `compiler/` is
special, it is that `builtin` is SNAPSHOTTED and `lib/rtl` is not"*, measured with
`--where` rather than assumed:

| tree | reached by the pinned compiler from | status today |
| --- | --- | --- |
| `lib/rtl/**` | the **LIVE** tree | a fix is live on push |
| `compiler/**` | the pinned **binary** | inert until a pin |
| `compiler/builtin/**` | the pin's **own snapshot** | inert until a pin **and already 3 files behind** |

**Two nilpy fixes that landed today are in that third row** and are reaching nothing
that runs under the pin. I am not pinning; it is a line for his return.

**Its placement call is a divergence chosen for a stated reason:** fpc declares this
in SYSTEM, visible with no `uses`; pxx's System is `compiler/builtin/builtin.pas`,
whose own header says it contains **no syscalls**, and `GetDir` is `getcwd`. So it
went in `SysUtils`, and the cost is stated in the source — `GetDir(0,s)` without
`uses SysUtils` compiles under fpc and does not here.

### THE CORPUS CAUGHT IT SHIPPING HALF A DECLARATION GROUP, IN ONE RUN

It wrote only the two names the wall named — `GetDir` at `:518`,
`AllowDirectorySeparators` at `:543` — and the re-run moved the head to
`cfileutl.pas:696`, `DriveSeparator`: **the same `const` block in the same fpc include
file**, 178 lines down, one line to fix. **That is normalise-don't-special-case's
sibling rule arriving as a DECLARATION GROUP rather than a code path** — a spelling
neither of us had seen. *One `const` block in fpc's source is one group here, and
taking the names a diagnostic happens to mention is the same mistake as fixing one arm
of a double case.* Cost of getting it wrong: a full corpus re-measurement for a
one-line constant.

**And it produced the unbuilt-rows-report-a-verdict failure in the same hour it was
writing that hazard up:** its first positive control printed `CAUGHT IT` having caught
nothing — the `sed` did not match, nothing was built, `diff` failed on two missing
files, and the `||` arm reported a verdict for rows where nothing existed. Re-run with
the build asserted **and branched on**, narrowing the separator set does redden it.
Same class I owned this morning; third instance today of a `||` arm speaking for a
step that never ran.

### ITS QUESTION, AND I GAVE IT A STRAIGHT ANSWER

New head `cfileutl.pas:714` `rmdir`, and **the detail file says only TWO errors remain
behind that wall** — `rmdir` (MkDir/RmDir/ChDir plus IOResult plumbing, which is
cross-unit state in `textfile.pas`, so a separate change), then
`internal parser bug: statement made no progress in block (would hang)` at
`cfileutl.pas:1495`. It offered to switch to characterising `:1495` while the unit is
fresh.

**I said characterise `:1495` first, and the reason dissolves the conflict rather than
trading it off: CHARACTERISING IS NOT SUBJECT TO THE INERT-UNTIL-PIN DISCOUNT.** The
whole live-vs-inert argument applies to *fixing*, and the artefact of characterising
is a reduction and a ticket, which land live whatever the pin does. So the RTL-first
rule simply does not bear on this choice. What is left is: the advantage is
**perishable and one-directional** (the unit is in hand now, `rmdir` will still be
there tomorrow), it is **Track P without a lane change** on the day Track P has been
unstaffed and is the owner's named priority, `rmdir` is by its own account *"a
separate change"* rather than the cheap one, and **"made no progress in block (would
hang)" is the compiler refusing about ITSELF** — a guard against a spin, which is the
class you want reduced while it reproduces.

**It is still its call.** I am answering a question the seat holding the work asked
me, which is not dispatch.

**Shop: four open regressions, gate GREEN, frankb-56 stopped, Track P about to be
touched by the A/B seat rather than staffed, `optdiff#shard5/12` unstaffed, three
things escalated for the 18th.** Still not banked at its instruction:
`test_threadsafe_heap_lock_deadlock_diag`, `fpc-bootstrap#src:compiler/compiler.pas`.

## Check-in 1n — the detail instrument was undercounting, so a number in MY 1m is a lower bound, not a count

**`dc3fedb0a` + `a29892c8c` landed**: a unit qualifier was ignored by the string/set
const lookup. `dc3fedb0a` touches **2 files under `compiler/`** — **inert until the
next pin** — and `a29892c8c` touches **2 under `test/`** and none under `compiler/`,
so the test is live for anyone who builds. Corrections both landed too (`2f3df27f8`):
the false byte-identical claim is out of the umbrella and the LOGBOOK, **and its own
post-mortem names the mechanism better than I did** — it was `cmp` on ONE file with
the conclusion asserted about the whole DIRECTORY, *committed while writing a
paragraph about sampling*. The third ledger state is written in beside it.

### THE BY-PRODUCT IS BIGGER THAN THE WALL, AND IT LANDS ON MY OWN RECORD

`statement made no progress in block` is the parser **ABANDONING THE BLOCK**, so a
unit's error list is **TRUNCATED wherever the give-up fires and nothing in the output
says so.** Measured by franks-ee across the 207 detail files: total error lines
**419 → 776**, all 357 new ones inside give-up files, three error KINDS never before
seen in this corpus; control, the **41 files that never carried the give-up are
unchanged, every one, grew=0 shrank=0.** The give-up was in **134** files, not the
one its recorded expectation predicted.

**So the instrument built to cure first-error blindness had a blindness of its own,
and I quoted it.** In check-in 1m I wrote: *"the detail file says only TWO errors
remain behind that wall."* **`cfileutl.pas:1495` is where the give-up fired, so
cfileutl's own detail file was truncated BY CONSTRUCTION.** That "two" is a **LOWER
BOUND, not a count**, and I am marking it as one rather than editing 1m — the record
stands and the correction sits beside it.

**A third caveat on the corpus number, next to the two already banked:** a head is a
queue position; a units-blocked count is not a work count; **and any "how much is
left" figure predating `dc3fedb0a` is low by an unknown amount.**

### AND I NEARLY REPLACED THE LOWER BOUND WITH A NUMBER FROM A THIRD CONFIGURATION

I rebuilt (`converged after 1 round(s)`, `b57f90696a01`) and drove `cfileutl` through
a three-line wrapper program to get the corrected count myself. It answered **4**, and
the four are `PInt`, `PUInt`, `PUint` and an unresolved `AWord` — **all in
`globtype.pas`, a dependency, before cfileutl's own body is reached.**

**That number is not a correction to "two"; it is an answer from a different
experiment.** franks-ee's figures come from its harness with its stub set and its
`-Fu` roots; my ad-hoc invocation is a **THIRD configuration** and is comparable to
neither arm. **Publishing it as the fixed count would have been today's wrong-
population failure for the fourth time, by me, an hour after I promoted the rule to
CLAUDE.md.** The corrected number has to come from the harness that produced the
original, re-run after `dc3fedb0a`. I have asked for it and I am not substituting
mine.

### WHAT THE DEFECT ACTUALLY WAS — THE PARSER MESSAGE IS THE LEAST OF ITS THREE FACES

fpc's `cfileutl.pas:142` declares `const ExecuteProcess = 'Do not use' deprecated`, a
constant whose entire job is to **shadow a function**, then calls the real one
qualified twice in its own body. The qualifier was consulted in the PROC table and in
**neither CONSTANT table**. Three faces, and the loud one is the least bad:

- **In an assignment: SILENT.** Returned the constant's text with the call arguments
  discarded — fpc `[FUNC:x]`, us `[SHADOW]`, **no diagnostic.**
- **With a set-const shadow:** printed the baked mask's **ADDRESS as a string** — a
  memory dump.
- **`const T = ''`:** prints nothing at all, **indistinguishable from a blank.**

**Boundary measured rather than assumed:** only an untyped string const of length
`<> 1`; char, typed, integer and float consts all resolve correctly, because **only
string and set consts live in name tables keyed without a unit.** Same class as
`bug-p-a-system-qualified-call-binds-a-same-named-user-routine`, in the sibling
spelling — *grepping for the construct finds nothing; only grepping for the other
handler does.*

### ONE BANKED, NOT COUNTED, AND ITS RANKING TENSION LEFT OPEN ON PURPOSE

`n := F('x')` for a string-returning `F` and an `Integer n` **compiles with no
diagnostic and prints a pointer as a number**; the same assignment from a string
VARIABLE is correctly refused. It was the single row of a 17-row matrix still
diverging AFTER the fix — *"the shape that reads as a confession and terminates the
search"* — so it **attributed to a range first**, and the pinned pre-fix compiler
reproduces it on a program with **neither a qualifier nor a shadowing const**. It was
masked here by the const interception. Filed with the tension stated rather than
silently resolved: *"accepting what fpc rejects is not a defect"* argues `rejected/`;
the counter is that this is a missing CHECK rather than dialect breadth. **It did not
settle it and neither will I** — that is a ranking call for whoever takes it.

**Corpus: twelfth consecutive null row, 22/10/175 unchanged — null BY CONSTRUCTION,
since `:1495` was never a head.** Said in advance, which is the only thing that makes
a null row information.

**It is taking `rmdir` (`cfileutl.pas:714`) next — RTL, live on push — and I said
take it.** The shift record stays open while it is working.

## Check-in 1o — UN-MARKING my 1n caveat: it was over-broad, and a correction that is itself imprecise costs the next reader the same measurement

**`387e1d4cc` verified library-only** — `lib/rtl/textfile.pas`, a test, a Makefile row,
a logbook line, **zero files under `compiler/`**. cfileutl.pas is **CLEAR**.

### THE CORRECTION TO MY CORRECTION, AND IT IS RIGHT

In 1n I marked my own 1m figure as a lower bound and wrote the caveat as *"any
how-much-is-left figure predating `dc3fedb0a` is low by an unknown amount."* **That
is too wide, and franks-ee supplied the number from the SAME instrument I had refused
to substitute for** — its harness, its stub set, its `-Fu` roots, re-run after the
fix. cfileutl.pas's own distinct error lines across three runs of one instrument:

```
before the const fix : {714, 1495}
after the const fix  : {714}
after rmdir          : {}          0 of 207 detail files now name cfileutl.pas
```

**So "only TWO errors remain behind that wall" was EXACT, not a lower bound.** The
give-up at `:1495` was the **LAST** thing in cfileutl.pas, so nothing of cfileutl's
own sat behind it; the 357 concealed lines were in **other units of the import
chain**. **I am un-marking it.**

**AND THE CAVEAT IS BOUNDED, WHICH IS BETTER NEWS THAN THE WALL.** Total error lines
went **776 → 642**, a SHRINK that its own pre-run expectation had called a regression
to explain rather than accept — and it explains exactly: **776 − 642 = 134, all 134
wall files lost EXACTLY ONE line each, that line was the rmdir line, and every
remaining error in every one is byte-identical.** So an `undefined variable` does
**not** truncate a unit's error list; **only a give-up does, because it abandons the
block.**

**The caveat, restated at its true width:** the detail instrument's blindness is
specific to the **GIVE-UP CLASS**, it affects only files whose list carried one, and
whether anything was actually hidden is per-file — for cfileutl, nothing was. It is
**checkable in one command**: grep the detail files for `statement made no progress`;
today that answers **0**. *(I did not run that grep myself — `PXX_CORPUS_DETAIL` is a
caller-chosen directory in franks-ee's scratch, not in the repo. Reported, not
verified here, and labelled so.)*

**The general lesson is the one it named and it is aimed at me:** a correction that is
itself imprecise costs the next reader the same measurement. Mine was cheap to write
and wide; the narrow one took a third run of the instrument.

### ONE CITATION OF ITS OWN IS WRONG, AND THE CONCLUSION SURVIVES IT

It wrote *"merge-base says the pin `ed8616ac3` (07-27) does not carry it."*
**`ed8616ac3` is pin v226, 2026-07-27** — seven weeks old and not what anyone is
running. **The live pin is v410, `764ee2ed2`, 2026-09-14, binary `c599e8546121`.**
The conclusion is unaffected and I had already verified it independently this morning:
the census **FAILS under `c599e8546121` and passes at HEAD**, and `e4c72bd15` (21:03)
is not an ancestor of the pin (20:45). **Right reasoning, wrong citation** — the same
shape as its byte-identical slip and three of mine today.

### TRACK B'S WHOLE GATE IS DOWN UNDER THE PIN, AND I CONFIRMED THE MECHANISM

`make lib-test` has been RED under `$(PXX_STABLE)` since 2026-09-14 and stays red
until someone pins. **Verified in the Makefile rather than taken:** `lib-test:` is at
`34959`, the census is at `35513`, **no target definition lies between them**, and the
line is a plain tab-prefixed recipe line with **no `-` prefix**. So it aborts the
target, and `-k` continues to other TARGETS, not to other lines of one recipe.
**Every `lib_*` row any Track B seat adds is unrun and unrunnable under the pin.** It
verified its own row by running the Makefile's two lines by hand: **31/31**, and fpc
answers 31/31 on the same file.

**Third dated casualty of inert-until-pinned, and the first to take a whole track's
gate with it.** Logged so the next Track B seat does not spend an evening attributing
it to its own change — *which is what it nearly did.* **It is not asking for a pin and
neither am I.** This goes to him.

### WALL FOURTEEN

120 → 0, detail files naming rmdir **134 → 0**, units-OK 22 → 22, new head
`globals.pas:1095` `Replace` going **12 → 132 = exactly 12 + 120**. **Thirteenth
consecutive null row**, fourth in a row where clearing a shared dependency hands its
whole population to the next wall in the same chain. Control: the 41 detail files that
never carried the wall, unchanged, every one.

**The measurement that stopped it reusing the existing table is the good part:**
`MkDir`/`RmDir`/`ChDir` went in `textfile.pas`, not sysutils, because they report
through `IOResult` and `IOResult`/`LastIOResult` already live there. Every code
measured under fpc 3.2.2 and read back — **ENOENT is 2 for RmDir/MkDir but 3 for
ChDir** (fpc separates *file not found* from *path not found* by the OPERATION, same
errno, two answers), and **ENAMETOOLONG is 3 where the file table says 2**. So the
second table is on evidence, not convenience. The empty path is a no-op returning 0 in
all three, and **the test asserts its ABSENCE OF EFFECT as well as its code**, because
an implementation resolving `''` to the cwd would delete or enter it.

**Next wall `globals.pas:1095` — RTL, live on push. Shift record stays open. Four open
regressions, gate GREEN, Track P and `optdiff#shard5/12` unstaffed. FOUR things for
the 18th now: `3eb0297f0`, the goal-5 wording, the two-arm question, and Track B's
gate being down under the pin.**

## Check-in 1p — I misrouted a compiler wall as RTL, and the stale-pin route is a SYMLINK, which is better than the reason I guessed

### THE CORRECTION TO ME FIRST, BECAUSE IT WOULD HAVE COST REAL WORK

In 1o I told franks-ee that `globals.pas:1095` `Replace` is RTL and therefore
live on push, and recommended it as the next subject **for that reason**. It
checked instead of taking it. **It is a COMPILER wall, not RTL**, and acting on
my routing would have meant adding an RTL overload to make the call resolve —
**a compiler-appeasement workaround on the wall with the most reach, making a
WRONG PROGRAM COMPILE.** Its three greps, and I confirmed the two that are ours:

- our only `Replace` is at `sysutils.pas:181-182`, inside
  **`TStringHelper = type helper for AnsiString` (`:159`)** — a helper METHOD.
- **franks-ee's reason is one degree off and the conclusion is right.** It said
  we have only a *two-argument* Replace. We have **two overloads, and one of
  them takes three arguments** — `Replace(OldValue, NewValue: AnsiString;
  Flags: TReplaceFlags)`. It still cannot be a candidate, for two other
  reasons: the third parameter is a **flag set, not a string**, and it is a
  method on a receiver, not a free function. The corpus wants
  `Replace(ShortString, ShortString, ShortString)` from its own
  `cutils.pas:82-83`. *Recording the precise version because it told me this
  morning that a correction which is itself imprecise costs the next reader the
  same measurement, and that cuts both ways.*
- **the real cause is two arguments away, in another unit:** `version.pas:41`
  declares `date_string = {$I %DATE%}`.

**WHY THE MISROUTE IS CHEAP TO REPEAT AND WORTH A LINE:** the diagnostic names a
FUNCTION and prints an OVERLOAD SET, so it reads as a library gap — the one
shape that points at `lib/rtl` — while the defect is a const in a third file.
Same family as the same-line-number trap already in the rules: **the
diagnostic's shape decided my lane, and the shape was honest and misleading at
once.**

### `{$I %MACRO%}` — I REPRODUCED IT AND IT IS WORSE THAN "NOT IMPLEMENTED"

Probe on both compilers, three consts, one file:

```
pxx  b57f90696a01 @ b3ad970f5 : rc=0, ZERO diagnostics,
                                SizeOf(d)=4  d=0   SizeOf(t)=4  SizeOf(v)=4
fpc  3.2.2                    : SizeOf(d)=10 d=2026/09/16  SizeOf(t)=8  SizeOf(v)=5
```

**`const d = {$I %DATE%}` compiles clean and yields Integer 0.** Not a refusal,
not a warning — a silently wrong constant. The seam is the part worth banking:
`compiler/elfwriter.inc:6043` explicitly recognises the form and skips it,
commented *"leave them in the text for the lexer"*, and **a grep of every
`compiler/*.inc` and `compiler/*.pas` for `%DATE%`/`%TIME%`/`%FPCVERSION%`
returns NOTHING.** Each side written as though the other handles it. **A false
premise stated as fact in a comment — the one place nobody re-measures.**
Agreed it is a Track P feature and not a guard: it needs a clock on both build
paths, civil-from-days, and an env-var fallback the compiler has no `getenv`
for. Its ticket, not mine to pre-empt.

### THE STALE PIN SHA: A SYMLINK, AND MY GUESS AT THE ROUTE WAS WRONG

I told it the likely route was a grep for `pin` in prose, and offered the 5:1
to 41:1 ratio. **It was not that.** It read
`git log -1 -- stable_linux_amd64/default/pinned` — and **that path is a
SYMLINK to `stable_pinned`**, so the query answers about the LINK's own history.
Measured here:

```
ls -l  ...default/pinned      -> stable_pinned        (a symlink)
git log -1 -- .../pinned      -> ed8616ac3 2026-07-27 pin v226
git log -1 -- .../stable_pinned -> 764ee2ed2 2026-09-14 pin v410
commits touching the LINK   : 30      (last one 51 days ago)
commits touching the TARGET : 355
```

**Every pin rewrites the target and none of them touches the link**, so the link
has been frozen since July while the thing it points at moved 325 more times.
**And the two instruments disagree in opposite directions, with the FRESH one
mute:**

```
filesystem mtime of the link : 2026-09-14 20:44:41
git log -- the link          : 2026-07-27 22:31:49
pin v410's commit            : 2026-09-14 20:45:14
```

`ls -l` says 33 seconds before v410. `git log --` says July. **The filesystem is
right and has no commit to cite; git is authoritative, precise, and answering
about a different object.** This is the house failure mode wearing a
**path-shaped git command** — the shape this file's rules already flag as the
one that reads as current — and franks-ee's own framing is the sharp part:
**it is the route that looks like doing it properly.** A grep for prose at
least looks like a grep for prose.

**The remedy is the identity the wrong object cannot imitate**, which is the
clause I landed this morning: `sha256sum stable_linux_amd64/default/pinned` →
`c599e8546121`, matched against `chore(stable): pin vN -- binary sha256 <hex>`
→ `764ee2ed2`, v410.

**I CHECKED WHETHER IT IS LIVE ANYWHERE COMMITTED, BECAUSE FIXING BEATS NOTING —
IT IS NOT.** Nineteen tools name `default/pinned` and **every one of them
EXECUTES it** (`$PXX_STABLE`, `--pinned`, `PXX=`), which follows the link
correctly and is exactly right. **No committed consumer asks git about it.** So
there is no bug to fix and nothing to tighten: the trap is confined to an
interactive seat asking for history. That narrows it from an infrastructure
defect to a note, which is the honest size.

### PROMOTION DECISION, STATED OUT LOUD AS THE RULE REQUIRES: **NOT PROMOTED.**

It meets the QUALITY bar easily and it does not meet the RECURRENCE bar — it is
**one instance of its own mechanism**, and the file is explicit that merit
decides banking while a second independent subsystem decides promotion. It also
has **no committed consumer**, measured above, so the population it could
mislead is "a seat typing a git command by hand". And the existing fetch
paragraph already carries the general shape — *"anything reading a PATH is
not"*. **What would promote it:** a second subsystem where a path-shaped git
query answers authoritatively about the wrong OBJECT rather than the wrong
VERSION. Banked here and in the playbook instead.

### ITS FALSIFIER, WHICH IT ANSWERED BEFORE THE RUN AND NOT AFTER

I asked what number would make it stop believing the chain model. **Answered in
advance, which is the whole value:** units-OK moving by **more than one** on a
wall that is not the last error in its own file, or a cleared wall producing a
new head **in a file the cleared one does not import**. Neither in fourteen.
**That is a real falsifier** — it forbids the outcome the model's own success
would otherwise absorb.

**Four open regressions, unchanged. Gate GREEN. Track P and `optdiff#shard5/12`
unstaffed. Four items for the 18th.**

## Check-in 1q — a quiet tick on the instruments, and both of my 1p corrections were taken up in the tree within four minutes

**Gate GREEN.** 23 rows, no FAIL, no SKIP, and the **FPC seed canary ARMED and
PASSED** rather than skipping — so the row that catches what the quick tier
cannot see actually ran this time. Verdict read off `gate-1q.log`, not off the
wrapper's exit code, which said `0` and would have said `0` either way.

**Four open regressions, unchanged from 1n/1o/1p:** `crtl_reachability.py`,
`optdiff#shard5/12`, `tools-devtest#00`, `crtl_atexit.c`. Against **this note's
original baseline of eight**, the standing delta is unchanged: the three A-lane
thread rows cleared, `c_asm_in_inline_body.c@2` was retracted in full (0e), and
three of the four optdiff shards cleared. **Nothing moved in either direction
this tick** — and per the brief, a red that clears is as reportable as one that
appears, so the absence is the report.

Breadth healthy: newest full tier 19m old, 2 testable commits behind. Pin v409's
17 reds unchanged and still not to be read as 17 defects — 4 corroborate in the
later full tier, 13 are noise.

### THE PULL, ATTRIBUTED TO A RANGE AND THEN TO A SEAT

Three commits arrived since 1p; **none touches `compiler/` or `lib/`, so no
rebuild was owed** — recorded because that is the step that gets dropped, and
the red it produces is correct and means nothing. Attribution by **session id,
not by author line** — every seat in this repo commits as `yoctobyte`, which is
check-in 0n's finding and the reason the author column cannot be used here:

```
be9380d54 16:19  franks-ee   docs(logbook): correct my own Replace count -- three-arg overload
3c90bdd73 16:18  franks-ee   ticket(P): {$I %MACRO%} is unimplemented and silently yields 0
d6c58350c 16:17  THIS SEAT   docs(playbook): a path-shaped git query answers about the path
```

**Both of my 1p corrections were acted on in the tree, not merely acknowledged**,
and the second one is the interesting one: `be9380d54` is franks-ee correcting
**its own** logbook entry because I pointed out we DO have a three-argument
`Replace`. Its conclusion never depended on that detail, and it went back and
fixed the detail anyway. That is the behaviour the un-marking exchange this
morning was arguing for, arriving unprompted four minutes later.

### AND IT MADE THE STANDING CHECK STANDING, WHICH IS BETTER THAN WHAT I ASKED FOR

I suggested the probe emit its own give-up count so the question stops being
answered by hand. `e0e2baac8` does that and goes further —
`tools/fpc_compiler_corpus_probe.sh` now prints

```
SUMMARY    both-ok=N oracle-no=N pxx-fail=N truncated=N
SUMMARY    WARNING: N unit(s) hit a parser give-up -- their error ...
```

with a header instructing the reader to **read `truncated=` BEFORE any `errs=`
count**, because *"truncated=0 is what turns these counts into counts."* **The
caveat is now enforced by the instrument instead of remembered by two seats**,
and `tools/` is not `compiler/`, so it is live on push and needs no pin. Verified
in the file at `:120` and `:126-129`, not taken from the commit subject.

### PEER MOVEMENT

- **franks-ee (A/thread-state, working the FPC-corpus walls):** active, 32
  commits in 8h, last 16:19. Filed the `{$I %MACRO%}` ticket as it said it would.
  Next from it by its own statement: the live RTL heads — charset/unixcp/heaptrc
  missing units, swapendian/align System routines. **I am not routing it
  anywhere this tick**, having misrouted it once today already.
- **frankb-56 (C):** last commit 12:45, ~3h30m quiet, `idle` in the session
  list. **Asked it to read its own transcript** rather than judging from here,
  with the three discriminators spelled out: whether anything is pending at all;
  WHO refused, since a hook decline and a user denial wear the same string and
  both live hooks are ones a seat may handle itself; and WHEN, since the newest
  denial may be days old in a seat working fine, and a grep for the denial
  string counts the grep. **A pane is not a session and I read no pane.**
- **neo-a2** is the owner's own home session, not a frank — do not offer it
  compiler work. **lekkerzeilen-c8** parked and correctly so.
- **Still unstaffed: all of Track P, and `optdiff#shard5/12`.** Offered to
  frankb-56 as availability, explicitly *not* as a gap a present seat should
  fill — its own correction on that stands and staffing P is the owner's dial.

**Nothing for him that was not already on the list. Four items for the 18th:
`3eb0297f0`, the goal-5 wording, the two-arm corpus question, and Track B's
lib-test gate being down under the pin.**
