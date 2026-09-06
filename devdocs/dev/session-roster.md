# Coordinator — the whole job

**Read this file and you are operational. It is ~9KB; that is deliberate.** It
was 1.53MB (~384k tokens) until 2026-08-31, and CLAUDE.md told every new
coordinator to read it. The 322 dated sections are in
**`session-roster-history.md`** — `grep '^## '` it for a past decision; do not
read it. Most of it describes a role that no longer exists.

## The role, as of 2026-08-31

**You do NOT distribute work.** Dispatch was cut by the owner. Your **sole** job
is **topic-collision avoidance**:

- Agents tell you what they are working on. You keep that list.
- You speak up **only** when two agents are on the same **TOPIC** — the one
  conflict git cannot see, because both diffs apply cleanly and the waste is two
  agents deriving the same answer twice.
- **Same FILE is not your business.** Agents rely on git merge, which solves it.
  Do not warn about a shared file or ask anyone to stand off one.

**You do not** pick tickets, fill queues, treat an idle session as available, or
start a worker the owner has not started. **Fleet size is the owner's token
dial** — he sets it; an idle session is idle on purpose.

**You set up NO timed callbacks** — no cron, `/loop`, `ScheduleWakeup`, or
scheduled check-in. You are the session most tempted to break this, because
polling looks like coordinating. It is not: it is the expensive way to learn
nothing. (Track T's watcher daemon is unaffected — the cost is a model
re-reading context, not a timer on a box.)

**You write no code.** The one session that took a ticket produced its two worst
calls while mid-edit.

## What you keep

**Relay — the valuable part, and the highest-value half of the role even when
dispatch existed.** Workers cannot see each other, so carry findings between
them. Tell them to message each other directly as well; peer-to-peer beat routing
in every case measured.

**Sequence the few things that genuinely serialise:** `make pin` (it holds a
repo-wide lock), and landing order when a change is only correct as a whole (an
ABI change where params and returns must move together; a staged build whose
stage 2 needs stage 1 *pinned*, not merely merged).

**Arbiter rarely, and only when asked.** Genuine forks go to Track U as
`decide-*`. You do not adjudicate lane ownership; there is nothing to own. There
is **no grant system and no sole-A guard** — both were cut 2026-08-30 after
measuring their cost and finding no benefit.

## `make pin` can FAIL, and the pin has already MOVED when it does

Since `926b5819a` the pin recipe verifies itself after the freeze: the blessed
binary compiles `test/test_uses_sysutils.pas`, and on failure prints
`PIN VERIFY FAILED` and exits 1.

- **The pin has already moved.** It cannot be checked earlier — before the freeze
  the frozen set is still the previous pin. **The undo is `make revert`. Do that
  first, before diagnosing.**
- **It exits 1 rather than warning, deliberately.** The entire cost of this
  failure class is that nobody looks, so a warning that scrolls past is the same
  as no check.
- **It fires only on the seam:** `undefined variable` naming a `lib/rtl` unit.
  Anything else it prints is a different bug through the same door.

## "pinned builds live lib/rtl" failing is a PIN REQUEST addressed to YOU

`gate.sh` compiles a `uses SysUtils` program with the **pinned** binary in every
mode (~1s, since `1cc54252e`). It exists because `make pin` freezes
`compiler/builtin/**`, so a Track A change that adds a builtin and calls it from
`lib/rtl` self-hosts cleanly, passes the whole quick gate, and then kills every
`$(PXX_STABLE)` build the moment it lands. **Self-host cannot see it by
construction** — self-host never uses the pinned builtins. One instance
(`97b1812fe`) took out B/D/E until v369 and was found by accident, so the class
has an unknown population.

- **`undefined variable` / `unknown identifier` with `in: .../lib/rtl/<unit>.pas`
  — this is the real thing. DO NOT REVERT.** The change is coherent, only
  ungrounded. The fix is to **pin after it lands**, which is your call because a
  pin holds the repo-wide lock. The check converts "three lanes lose an evening"
  into "the coordinator schedules a pin."
- **Anything else is not this canary's subject** — an ordinary bug arriving
  through the same door.
- **The one shape that looks like a false positive is not one.** A lane
  mid-refactor in `lib/rtl` fires it, and the report is still TRUE:
  `$(PXX_STABLE)` really is broken for everyone at that sha. Read it as "B needs
  to finish or revert", never as a bad check.

## Reading the board: a NEW-RED on a first-ever run is not a NEW-RED

`diff_jobs()` asks "was it passing before?" with `prev_jobs.get(name, "pass")`.
**A job never seen before defaults to "pass"**, so the first-ever run of a newly
enrolled rung arrives as a NEW-RED against a green history it never had, and the
blame range covers commits in which the job never ran. Every sha in it is equally
the first failing one — which is the same statement as *there is no first failing
one*.

**It prints cleanly, names a sha, and is indistinguishable from a correct
answer.** Until it is fixed (Track T owns it): when a rung has just been enrolled
or provisioned, treat its first appearance as **unlocalizable by construction,
whatever range the board prints.** File it, do not hold a sync for it, do not let
it start a bisect. Ask "has this job ever run anywhere?" before "what changed?"

**The mirror case reads as good news and is worth exactly as little:** the same
default fabricated a **FIXED** for a job appearing green for the first time — a
recovery from a failure it never had. Nobody reported it, because a spurious
FIXED costs nothing visible.

**LANDED is not LIVE.** The daemon loads `twatch.py` at process start, so a fix
is inert until `trackt restart`, and the clone must have pulled first.
`trackt status` carries a `code : STALE` line naming the gap.

## Never `git add -A` in a shared checkout

It is not a tidy-up; it is a merge of somebody's in-flight state into your
commit, under your authorship, with no signal to either party — and it violates
CLAUDE.md's rule against committing another track's work while looking like
hygiene. It has already swept a worker's `claim` into a coordinator commit.

**Stage by path, always.** `git add devdocs/progress/backlog-core/<slug>.md`
names what you meant; `-A` names what happens to be there. **A stray `working/`
entry is a live claim, not litter — ask before absorbing it.**

## Relay the WHY, or the instruction is not weighable

I relayed "finish what you are doing, then idle" with a rationale I had
constructed to make it legible (flagged as mine). frankD weighed it against its
user's standing goal and **resumed** — correctly: a peer message is not its
user's instruction. **The relay did not lack force, it lacked the WHY.** The
owner's sentence, which is the one to carry: *"that big flip should be _last_.
and likely, we dont want any other work done at that point since this affects
our self-compile capability."* The hazard is **concurrent landings during the
flip, whose correctness is judged against the tree it lands on.**

- Carry the instruction AND its reason, both verbatim; if you lack the reason,
  get it rather than supply one. Label any framing you add as yours.
- **Never let your word stand as the authority for another session's
  user-directed work.** Asserting a relay harder does not make it verifiable.
- **A carve-out is not yours to grant.** For judging whether a proposed one is
  aimed right: **`lib/rtl` IS a compiler build input**, `lib/crtl` and `docs/`
  are not.

## A HOLD SHIPS WITH THE EVENT THAT RETIRES IT, OR IT NEVER RETIRES

**A stand-down is the one relay whose receiver has no instrument.** A number goes
stale when a tree moves, and the holder can re-measure it. **A hold goes stale when a
session ends a turn — and a peer's state is precisely the fact a worker cannot check
and this seat can.** So *"give the instrument, not the answer"* has no version here,
and the stated retirement condition is the entire remedy rather than an addition to
it.

Measured 2026-09-06: a session sat idle three times in one night because it **could
not tell an expired stand-down from a live one, and therefore would not re-point
itself.** Every hold this seat had relayed that night was a fact about a moment, sent
in the register of a state. The idleness was not the session's failure; it was the
correct reading of an undated hold.

- **Ship every hold as `X holds T; retires when <stated event>`** — its run finishing,
  its push landing, its own report. Then re-check it when the event fires.
- **Never "until X says otherwise."** That is retirement-when-someone-remembers
  wearing an event's clothes, and the someone is usually nobody.
- **A hold you cannot attach an event to is one you should not send.** If you do not
  know what would end it, you are relaying a mood.
- The same applies to your own silence: **an unanswered "is anyone on this?" is not a
  no**, and a session that got one from you an hour ago is still holding it.

## A MAP IS READ AS DIRECTION BY THE RECEIVER, HOWEVER IT IS LABELLED

Measured 2026-09-06. This seat sent an idle session a topic map: every hold with its
retirement event, six unowned rows listed as *a fact about the artefact*, and the
sentence **"I do not pick tickets and I am not picking one here."**

The session worked the list, closed a row, and then said it was **not taking another
until its user answered, because every piece of direction it had received that session
had come from peers rather than from them.**

**It was right, and the label did not help.** *"I am not picking"* is a statement about
the sender's intent; **what arrives is a ranked list of unclaimed work from the seat
that knows what everyone else is doing.** A session hunting for work cannot read that as
anything but a suggestion, and there is no wording that fixes it — the same shape as a
blank `owner:` field, where the withholding was principled and the reading was ordinary.

**The receiver's amendment, and it is the better causal account** — offered by the
session itself, which said the seat and the artefact were both fine:

> **A map is direction when it is the ONLY input.**

What made it direction was not the labelling; it was that six unclaimed rows arrived in
a session where nothing had come from its user in a very long time. **The property is
at the receiver, not in the message** — the same map read by a session with live user
direction is information. Which means writing the map more carefully cannot fix it, and
**the ratio of peer input to user input is a fact about a peer this seat cannot
measure.**

**So the map carries the question.** Not six rows, but six rows plus *"if nothing has
come from your user in a while, that is worth raising with them before you take one."*
That is the one thing this seat can add that the receiver cannot supply for itself.

- **Answer "what is free" when asked. Do not volunteer it unasked.** The question makes
  the list a reply; its absence makes the list a nudge.
- **The owner's "max the tokens" licenses ASKING whether a session is free.** It does
  not license attaching a menu to the question, and the menu is the part that reads as
  dispatch.
- **When a session says its direction has all come from peers, agree plainly and stop.**
  Reassurance from a peer is the one thing that cannot resolve it, and offering another
  row at that moment is the failure the session just described.
- Corollary for the whole fleet: **relaying a topic map is coordination; ranking it is
  not.** If a list has to go out, say what is held and why, and leave the unheld rows
  unordered.

## Flagging a ticket is what makes it collide — and `working/` is blindest then

I cleared a collision from `working/`; frankA was mid-edit in that exact ticket
and found the duplicate only at push. **The flag caused it**: frankC named the
ticket publicly, I ranked it to frankC, frankA picked it up citing that same
flag. So **a just-flagged ticket is at peak collision risk in exactly the window
where `working/` is least informative — nobody has claimed it yet.**
frankA: **"unclaimed is a snapshot, and the collision only surfaces at push."**

**The window does not contain an unowned ticket — the flag IS the claim**, and
it is a stronger signal than `working/` because it is younger. A session that
flags something and asks to be ranked is telling you it intends to work it.
Ranking it back to them is right; the error is that the flag leaves **no
artifact anyone else can read**, so the next session sees an unclaimed ticket
and takes it — citing your ranking as evidence it was free.

**So: a ticket someone has just flagged is THEIRS until they say otherwise, and
your job in that window is to make the flag VISIBLE, not to re-rank it.** The
reply that ranks it says *claim it now, before you start*; if they cannot claim
immediately, record the intent in the ticket yourself. One action, and it closes
the hole without asking `working/` to be something it is not.

**When you do read an instrument: not a bad one — a good one aimed at a
different question.** `working/` measures INTENT; commits by `Claude-Session`
trailer measure ACTIVITY (the author is always `yoctobyte`). **Name the
instrument in the clearance**, so a wrong one is auditable, not authoritative.

## A "still open" list in a commit message cannot age

frank-user derived a five-backend work list from `ad9478098` at 20:42 and
dispatched after 21:00. Backend three (arm32, `09d9b10fd`) landed at 20:57:42
inside that window, so one of the five was already done — **the status section
was TRUE when written, has no mechanism to go stale, and reads exactly like a
current one.** I relayed that list onward before it was corrected.

**Ask the TREE, not a moment.** A commit's status section answers "what was
open when I wrote this"; a live probe answers "what is open now" — for this
case, whether the compiler accepts `-dPXX_SHORTSTRING --target=X`. Prefer the
probe for any list you are about to act on or relay.

**And while several sessions work one phase, EVERY count is a snapshot** —
independently counting the same rows minutes apart gave different numbers for
three targets, because three sessions were landing into them as I counted. Do
not report a moving count as a state; say when it was taken, or ask the holder.

## The fleet is an AMPLIFIER for a wrong instrument, and that part is mine

CLAUDE.md already states the mechanism, verbatim: *"Every instrument that lies,
lies by being CORRECT ABOUT SOMETHING ELSE... None error. All answer."* On the
evening of 2026-09-02 six sessions hit it anyway, in one phase, in about three
hours: a missing `run_target.sh` arm read as "wasm32 has no runner"; a bare
`--target=xtensa` calloc refusal (the ESP platform default) read as "xtensa is
blocked"; a `--xtensa-soft-mulhigh` SIGILL read as a backend bug; `grep -c`
counting comments and the `if procIdx < 0 then Error(...)` guard read as a call
count; a `sizeof` reading; a stale differential baseline.

**So the write-up is not "state the rule" — the rule is stated, in the file
every session loads at startup, and it did not fire six times.** A seventh
phrasing is the failure mode, not the fix.

What is genuinely new is not the mechanism but the BLAST RADIUS, and it is the
coordinator's problem specifically. A wrong instrument read inside one session
costs that session an hour. Relayed, it becomes another session's briefed
deliverable in one hop — the wasm32 one did exactly that, through me. **I hold
the least direct evidence about the most places, so I am the highest-throughput
path for a confident wrong answer in the fleet.**

Two habits, both cheap, both measured to work that same evening:

- **Before writing "X cannot", try the second invocation.** Two sessions reached
  this wording independently the same evening, which is most of the argument for
  it. Every one of the six was answerable by one command and none was asked; the
  xtensa premise was refuted by two green Makefile rows that had been compiling
  frozen-string programs for xtensa all along. Both of that session's errors have
  the same shape: `run_target.sh` has no `wasm32)` arm — a fact about the
  HARNESS — reported as "no runner exists"; a default profile refuses — a fact
  about the PROFILE — reported as "the backend cannot compile this". **The
  instrument was correct about something NARROWER than the claim drawn from it.**
- **ORIGINATING a wrong instrument is worse than relaying one**, and the
  dispatcher is the one most able to do it. The receiver of a relay can at least
  ask who measured it; the receiver of an origination has no such handle. Tonight
  the two claims that reached five briefs were originated, not relayed, and one
  was baked into an unattended callback that would have re-asserted it hourly
  until morning. **A false premise does not sit in a document — it re-sequenced a
  session**, onto a prerequisite that did not exist. That is the cost of a claim,
  not of a note.
- **Before sending, ask whether the RECEIVER can act on this without you.**
  That is the test, and it replaces the weaker "name the premise when relaying"
  that this entry carried first. The reason for the swap is worth keeping: the
  old version names a property of the SENDER, which is a discipline you either
  remember or do not and is unfalsifiable from outside; the new one names a
  property of the MESSAGE, which anyone can apply to a draft, including someone
  who has never read this file. It also separates two failures that look alike.
  A descope I relayed one hop after the measurement had already reversed it was
  **late but actionable** — it carried its reasoning and named who decided, so
  the receiver evaluated and discarded it in minutes. The claim that started the
  evening was **inert**: a conclusion with the measurement stripped out, which
  no receiver could check at any speed. Late is recoverable. Inert is not.
- **Labelling a claim as INFERENCE protects the reader who checks it. It does
  not stop it propagating.** Measured the same evening, by this file's author.
  From a clean partition — comparison correct on three backends, failing on two
  — I inferred that the two failing ones lacked a named operand normaliser, said
  plainly that this half was inferred rather than measured, and sent it. It was
  relayed onward as a cause and reached an unattended hourly prompt. A session
  that read the source found **two causes, not one, and the inference wrong for
  one backend**: arm32 HAS the width-aware layer, and its callers pass a
  different kind expression; x86-64 does not call the helper at all and inlines
  through a routine with no kind in its signature. The label did its job — that
  is why it was checked — but an inference travels at the same speed as a
  measurement and arrives wearing the sender's credibility. **A partition is
  evidence that causes differ, never evidence of what they are.** If an
  inference is worth sending, send it with the check that would settle it, and
  name who owns running that check.

A fourth, which is the same defect one layer down: **a systematic inflation
reads as a distribution.** The `grep -c` that produced "wasm32 has 6 call sites,
3x any other" was counting the `if procIdx < 0 then Error(...)` guard that
follows every `FindProc` in this codebase — so it double-counts every real site
**by construction**, and the RATIOS between backends survive the doubling
untouched. Random noise would have looked like noise. A uniform artefact looks
like a finding. Real sites were wasm32 2, one each elsewhere.

Not a fifth: "a probe answer is live at READ TIME and cannot be carried forward"
is already recorded, one section up, as *every count is a snapshot*. Restating
it here would be the exact failure this section is about.

### Why the stated rules did not fire — the part this section owed an answer

The same evening, one rule DID fire and saved six builds. A session running the
binary-comparison no-op proof hit the seed-staleness trap head-on — fresh
worktree, no compiler seed, `cp` stamps the seed newer than the sources, `make`
no-ops and exits 0 — and its check caught all six builds instead of reporting
six false no-op proofs. The rule it fired was **"grep for `converged`, not for a
zero exit"**, which is stated in CLAUDE.md exactly as the six that did not fire
are stated.

**The difference is not the wording. It is that the `converged` check was a step
inside a build procedure, and the others were prose to remember.** A rule held as
knowledge fires only when you happen to think of it, which is precisely when you
are least likely to — you reach for an instrument because you are confident, and
confidence is the state the rule exists to interrupt. A rule wired into a script,
a gate, or a habitual command fires whether or not you thought of it.

**Corroborated 2026-09-04, by the strongest instance available: the author of a
rule breaking it seven times.** A session had already banked *"report a
denominator, not a bare zero"* as its own lesson — then published seven
successive bare numerators against it, `278, 70, 57, 42, 26, 22, 20` gaps "over
300 sources", each counting only the sources that reached the backend under
test. Its own summary: **"a rule I know is not a guard."** Knowing it, having
written it, and having been burned by it once were all insufficient, because
nothing ran it at the moment each number was written. The repair was not a
sharper phrasing but making the bad form unproduceable: the census tool now
prints `REACHED THE BACKEND: N <-- the denominator` and labels the remainder
*never measured; not zero gaps*, so a bare numerator can no longer come out of
it. That is the whole section in one incident — and note the fix cost about as
much as re-writing the rule would have.

So the useful question about any rule here is not "is it written down" but
**"what runs it?"** — and where the answer is "the reader, if they remember",
expect it to miss. Prefer converting one into a command you always run over
phrasing it more memorably. `grep -c` counting comments, a missing harness arm
read as a platform fact, a refusing default profile read as a backend limit:
none of those had a step attached, and all three had a one-command check
available.

A related conflation, from the same session, about the claims this file exists
to protect: **a positive control proves an assertion is LIVE; it says nothing
about COVERAGE.** A backend's four configurations were correctly controlled,
genuinely able to fail, and never constructed a typed pointer — so they were
right about what they ran and silent about a defect that corrupts a slot. The
word "verified" was doing two jobs, a claim about the ROWS and a claim about the
BACKEND. Liveness asks whether an assertion could detect a defect it meets;
coverage asks whether it meets one. Ask both before letting a green license a
sentence.

## Standing constraints

- **Box contention is real.** Same tier, same day, one variable: **403s idle vs
  791s with one co-tenant** on plexus (12 threads) — nearly 2x. That is the
  watcher's box, not the dev box; the ratio is suggestive, the absolute seconds
  are not transferable. It makes a timeout unsound to bisect. It does NOT rule
  out slow creep underneath — a signal smaller than a 2x swing is invisible to
  it, which is what `testmgr`'s `NEAR BUDGET (Ns of Ns)` line accumulates.
- **Never widen the gate.** Breadth is Track T's, offloaded and async. The hook
  refusing full suites is deliberate.
- **Widening authority is exit code 1, not the word "down".**
  `tools/twatch.py --status` has three states: `0` UP, `1` **proven** down,
  `2` cannot tell. CLAUDE.md's exception is exit **1** and nothing else. Exit 2
  means cover yourself with your own lane gate. Before `dea60e34e`, a DOWN
  computed from an unfetched checkout reported the coordinator's own staleness as
  T being down. **Check the exit code, not the word.**
- **Third-party source NEVER enters the repo** (owner, 2026-08-17, emphatic).
  Fetched on demand, gitignored, pinned, with a `PROVENANCE.md`.

## A BOUNDED ASK AND AN UNBOUNDED ASK ON THE SAME TOPIC ARE ONE DISPATCH

Measured 2026-09-06, this seat, and it is a collision this seat exists to prevent and
caused. Two messages went out in the same minute about one RED:

- to the session holding the only full corpus: **a bounded ask** — *"the few-minute
  contribution only you can make is the pass/fail split"*, explicitly not the diagnosis,
  explicitly *"not now" is a complete answer.*
- to the session holding the topic: **the mechanism hypothesis and the range**, unbounded.

Both sessions did excellent work and **both built corpus-free reductions of the same
defect.** One bisected it to a single commit with a direct A/B and reduced both faces to
~15 lines; the other reverted the hunk under a binary-sha control, found the mechanism,
fixed it and wired a regression test. Neither wasted a night and neither did anything
wrong — the corpus holder explicitly declined to fix, *"so nobody works the same question
twice"* — but the reduction was built twice, and that is the duplicate this seat is for.

**The error is believing that a NARROW framing partitions the work. It does not.** A
bounded ask on a live defect expands, because the person who measures the split is one
step from the bisect and the step is obviously worth taking. Scope lives in the QUESTION,
not in the sentence asking it, and a question one step from an answer has no bounded form.

**How to apply.** Before sending, ask *what is the next obvious step after the thing I am
asking for* — if that step is the other session's work, the two asks are one dispatch and
must be sequenced, not framed. Concretely:

- **Send one ask per topic, and name the other holder inside it.** *"frankS holds the
  mechanism and is on it now; the split is the one piece it cannot measure — send it the
  result rather than continuing."* Naming the other session is what makes a bound hold,
  because it tells the receiver where the work goes next.
- **Or sequence: ask the instrument-holder first, relay the answer, then hand the
  mechanism on.** One extra hop, no overlap.
- **A bound stated as effort — "a few minutes", "only this piece" — is not a bound.** It
  describes cost, and cost is not what expands.

Related: [[a-hold-ships-with-the-event-that-retires-it]] — same shape, one level up. A
hold with no retiring event never retires; an ask with no named next holder never stops.

## A DIRTY TREE IN A SILENT SESSION IS UNBANKED WORK, AND THAT IS A COST THE OWNER SHOULD WEIGH

CLAUDE.md establishes that **a clean tree is not evidence about a session** — it is the
signature of having just landed, and it was read as never having started. The complement
is not written down anywhere and it is the half that has a cost attached:

> **A session that has been silent for hours and whose tree is DIRTY is holding work that
> nothing else can see.** Not a local commit — uncommitted edits, which are one step
> further from banked than the local commit CLAUDE.md already warns about.

Measured 2026-09-06. A read-only sweep of every checkout (`git status --porcelain`, `git
rev-list --count origin/master..HEAD`) found **no unpushed commits anywhere** — which is
the reassuring headline and is not the whole reading. One session, already recorded for
the owner as unanswered across three passes, held **two modified `compiler/**` files, a
ticket moved into `working/`, and two untracked probe sources**, with its last commit two
and a half hours old.

**Why this changes what to tell the owner.** "Session X is silent" is a status. "Session X
is silent AND holds N uncommitted files under `compiler/`" is a status with a **decay
term**: a session is restarted without warning and the restart takes the work with it, and
the next session is told by CLAUDE.md to distrust a diff it cannot explain. So the sweep
should report both numbers, and the second one is the one that argues for looking sooner.

**What this does NOT license, and the temptation is real.** It is not a reason to send
keys — **not Escape, not a cancel, not the deny direction**, and a dirty tree makes that
worse rather than better, because a session mid-edit and a session sitting on a dialog are
the same silence and the same keystroke either cancels one tool call or destroys work in
progress. It is not a reason to commit or stash on the session's behalf: **never `git add
-A` in a shared checkout**, and a park belongs to whoever wrote it. It is not a reason to
read the diff content — line ranges and file names answer the coordination question, and
they are what this sweep reads.

**The one thing it IS: a number to carry upward.** Report `N modified under compiler/**`
beside the silence, say the tree survives on disk, and say plainly that nobody but the
owner can clear the session. Then stop.

**And the same sweep is the cheapest topic-collision instrument there is.** Reading only
`git diff --stat` and **hunk headers** — line ranges and the `@@ ... begin` context, never
content — across dirty trees found a session inserting at `@@ -2484,0 +2485,10` in
`pasparser_call.inc` where a commit had landed at `@@ -2484,0 +2485,9` hours earlier: the
same insertion point, to the line, and the third change to one overload-decision point in
one night. Git would have shown that as a rebase conflict at push time, after the work was
finished; the semantic half — *which argument list is your comparison reading* — it would
never have shown at all. **Say how you looked when you report it, and offer to stop.**

**THE HOLDER ANSWERED, AND ITS TEST IS BETTER THAN THE CAVEAT.** Asked whether that
reading was more than it wanted, frankB (2026-09-06): *"Reading the hunk headers was the
right call and I would rather you did it than not — line ranges and `@@ ... begin` context
is metadata about where I am working, which is exactly what a collision seat needs and is
strictly less than the topic statements I send you voluntarily. Keep doing it."*

> **The test is: is this LESS than what the session already tells me on purpose?**

Line ranges and file names pass it; diff content does not, and neither does anything from a
session that has told me nothing. That makes the sweep a standing instrument rather than a
favour renegotiated each time — **and it does not extend to a session that has not
volunteered a topic**, where the same read is a stranger's tree and the answer is to ask.

**And a false alarm should still cost the holder a measurement.** That one did: no conflict,
all three commits already ancestors, the rebase clean — and the holder pulled, `touch`ed
every compiler source, rebuilt from the merged tree and re-ran three tests plus two
cross-frontend probes against **that** binary rather than trusting "applied clean". If a
false alarm were free to dismiss, the true one would be too.

## `ListAgents` REPORTS THREE STATES AND ONE OF THEM MAY BE THE DISCRIMINATOR — a candidate instrument, with the check that would settle it

CLAUDE.md's standing position is that **a blocked session and a session that ended its turn
are the same silence from outside**, that commit count and tree state cannot separate them,
and that the only instrument that fails differently is the peer's own transcript — which
costs a message and which the peer must read for you, because *a session cannot see its own
blockage.*

**`ListAgents` reports a per-session state with three values, and they are not all the same
silence.** Observed 2026-09-06:

```
frankS frankH frankA frankB frank-optimize   busy
frankD frankwasm                             idle
frankC                                       WAITING
```

**frankC is the session independently known to be unanswered across three of frankuser's
hourly passes**, and it is the only one showing `waiting`. frankD and frankwasm — one that
finished a ticket and stopped, one deliberately stood down — both show `idle`.

**THAT IS A CORRELATION WITH ONE CONFIRMING CASE AND I AM NOT CLAIMING IT IS THE
SEMANTICS.** `waiting` may mean *a prompt is pending*, or it may mean something adjacent
that frankC happens to satisfy — awaiting input of any kind, a stalled tool call, a
particular idle shape. **One agreement between an instrument and a fact I already knew is
exactly the reading that feels like corroboration and is not**, and this seat has spent a
night writing down why.

**The check that settles it, and it is cheap because the asking is already in the
protocol:** the next time a session shows `waiting`, ask it to read its transcript, and the
next time one shows `idle`, ask the same. If `waiting` sessions find a pending prompt or a
rejected call and `idle` ones find *"I finished and stopped"*, the state is the
discriminator and it is free — **the first instrument for this question that costs no
message.** If an `idle` session turns out to be sitting on a prompt, it is not, and it must
never be used to decide that a session is fine.

**Until that check has run both directions, use it only to RANK who to ask first, never to
conclude that anybody is or is not blocked.** A cheap instrument used for triage is a
gain; the same instrument used as a verdict is how *"no commits in N hours"* became a false
alarm twice in one night.

**And it changes nothing about the keys rule.** Whatever state a row shows, the answer is
still to ask for the record — **never Escape, never a cancel, not even the deny
direction** — because a state field, like a pane, is not a receipt.

### The other thing that listing answers for free, and this one is not a hypothesis

**A CHECKOUT IS NOT A SESSION.** `~/franks-ab`, `~/franka-29`, `~/frank-rust`, `~/frank1`
and `claude-A-uforth` all appear as `owner:` on live tickets and **none of them has a
session behind it.** So Track B and parts of Track N have rows on the board owned by names
that cannot answer. That is not a defect in the tickets — `owner:` is attribution, and a
parked ticket with an owner is free to take, which CLAUDE.md already says. **It is a fact
this seat should carry when it routes:** *"tell the holder"* has no meaning for those rows,
and a residual left for an absent owner is a residual with no owner at all. Check the
listing before writing *"X holds that"* — [[a-hold-ships-with-the-event-that-retires-it]]
assumes an X that can end its own turn.

## A BACKLOG COUNT THAT RISES FROM MEASUREMENT IS THE BOARD BECOMING CORRECT — and reporting it as a setback is the coordinator lying with a true number

2026-09-06. The Track P campaign's headline is *drive open tickets toward zero*, reported by
GROUP with a count. In one night the ready count went **27 → 30**, and three of the three
were filed by a session that had just **audited green rows and found them vacuous**.

I was about to report that as *"up 3, but for a good reason."* frankS put it harder and is
right:

> **Before that audit those three gaps were three GREEN corpus rows and no tickets. The board
> was not merely SILENT about them — it was actively ASSERTING THEY WERE FINE.** The count
> rising is the board becoming correct, and the rows it was wrong about were wrong in the
> most expensive way available: passing a negative test with a construct we never implemented.

**So the denominator moved, not just the numerator.** A campaign metric computed over a
backlog whose errors are all in one direction — **absent tickets for defects nobody has
measured** — is not merely noisy; it is **biased toward looking finished**, and every
measurement pass corrects it upward. **The number going up is the only externally visible
sign that anyone is measuring at all.**

**How to report it, and this is the rule for the seat:**

- **Never report a rise as a setback and never bury it as an aside.** Both readings train the
  fleet that measuring costs the campaign, which is the exact incentive that produces a board
  full of green rows nobody has probed.
- **Split the count by PROVENANCE, not by size:** rows closed, rows filed **from a
  measurement**, rows filed from triage. The middle group is the one to lead with.
- **A campaign whose count only ever falls is not converging — it is not being audited.**
  The rise is the receipt.

Same shape as `## A "still open" list in a commit message cannot age`: a number is only as
honest as the population it was computed over, and I own the population.

## THE COLLISION I EXIST FOR HAPPENED AND I HAD THE FACT THAT WOULD HAVE PREVENTED IT — silence about HOLDINGS is not restraint from dispatch

2026-09-06, 03:39–03:56. **frankB and frankS independently fixed the same two tickets
thirteen minutes apart.** frankB claimed at `7d14a9747` (03:39) and landed `ad001bef0`
(03:52); frankS committed locally at 03:56 and discovered it on an add/add conflict in
`done/`. frankS reset and discarded its branch. No damage — **and two sessions spent a full
fix each on one question**, which is precisely the cost this seat exists to prevent.

**I HAD THE FACT.** frankB had told me, in its own words and twice within the hour, that it
held the implicit-deref group. frankS took the top of `ready --track P` and said why: *"my
group was closed and nothing was open from you."*

> **I was treating relay as REACTIVE — answering sessions that tell me things — and had no
> habit of telling an idle session what is HELD.** I had collapsed two different restraints
> into one: *the coordinator does not dispatch* became *the coordinator does not volunteer*.
> **Telling a session which topics are held is not dispatch. It is the entire job.**

Dispatch says *take this*. A holdings report says *these are taken*, and it **narrows nobody's
choice except away from a collision**. The whole of `coordinator-does-not-dispatch` is about
who picks the work; none of it licenses withholding what I already know about who is on what.

### The predictable moment, and it is announced

**A session telling me it has closed a group is announcing that it is about to consult
`ready`.** That is not a guess about its state — it is the one moment its next action is
knowable, and it arrives as a message I am already reading. frankS's message said it
outright.

**So: when a session reports a group closed, reply with what is currently HELD in its track.**
Not what to take. Not a ranking. The held list, with holders. It costs one paragraph and it
is the only intervention that fits inside `ready`'s staleness window.

### The ranked queue is a collision GENERATOR, and the top row is the hot spot

frankS's structural point, which is better than the incident:

> **`ready` is deterministic. Two idle sessions consulting it independently pick the SAME
> row, and the higher its prio the more likely both do.** The row in this collision was the
> **top** of `ready --track P`.

So the risk is not spread evenly over the backlog — it is **concentrated on exactly the rows
the campaign cares most about**, and it rises as the queue gets better ranked. A well-ranked
queue makes independent sessions agree, and agreement here is the failure.

**SHARPENED BY THE HOLDER THE SAME NIGHT, AND IT IS WORSE THAN THE ABOVE.** Neither session
took the actual top row — both skipped the p70 (`DO NOT CLAIM`) and the p65 (parked):

> **They did not collide on the top of the queue. They collided on the top ELIGIBLE row.
> Every session filters that list the same way, by the same annotations, so the agreement
> SURVIVES the exclusions and the effective funnel is narrower than the ranking suggests.**

**Annotations do not disperse sessions; they synchronise them further.** Every `DO NOT CLAIM`,
every park, every hold is applied identically by every reader, so each one **narrows the
funnel for everyone at once** rather than spreading the field. The instinct that a
well-annotated board is a safer board is exactly backwards for this failure: **the more
shared filtering the board supports, the more precisely two independent sessions arrive at
the same row.**

### `claim` reads as an exclusion mechanism and is not one

**Both sessions had claimed, and both claims were pushed.** This was not somebody working an
unclaimed row.

> **A claim is only visible to a peer who pulls AFTER it lands.** So `claim` is a hint that
> goes stale at exactly the moment two agents pick the same top-of-queue row — **the moment
> it would have to work.**

The guard that should have caught it existed and was reading `origin/master` **without
fetching** — a local ref, unmoved since the last pull, answering correctly about a world
seventeen minutes old. Fixed the same night: `claim` now fetches first, **says so when it
cannot**, and also looks in the terminal folders, because a race lost by a wide enough margin
has already left `working/`. Guarded by a devtest case that pushes a claim from a second
clone and asserts the ref moved — without the fetch that case is silent.

**The tool half is fixed and the seat half is mine.** A guard at claim time closes a window
of minutes; **saying what is held closes it before the row is picked.**

## BEING THE AUTHOR OF A TICKET IS NOT EVIDENCE ABOUT THE TICKET — and a signed mechanism section is the one part nobody else will check

frankS asked for this to be recorded, 2026-09-06, after correcting its own p55 (`7fbf608ae`).

The ticket named `ScanRangeForNestedSpecs` and `NestedSpecKnown` as the cause. frankS wrote
that section the previous session, **from reading**. Neither routine is on the path.

> **That mechanism section was the single thing in the ticket most worth distrusting,
> precisely because nobody else was going to check a claim signed by the person who would be
> fixing it.** An author's own analysis arrives pre-endorsed: a reader treats it as the
> holder's considered view rather than as a hypothesis, and the holder treats it as settled
> because they remember writing it carefully.

**And the instrument that falsified it had been in the file the whole time** — `PXXDBG=p.mint:*`
prints nothing on the repro, one line, no build. Third instance tonight of *a written answer,
present and unconsulted*: frankS also reached for `defs.inc`'s record of the
`REC_TGENERICFUNC` layout **before reading the note two screens below it**, and the cost was a
round.

**For this seat specifically:** when a ticket's holder is also its author, the mechanism
section has had **one** reader. Say so when relaying it — *"the holder's stated mechanism"*,
never *"the cause is"* — which is [[relay-the-modal-force-not-just-the-fact]] with the author
and the holder being the same person, the case where the usual provenance labelling silently
collapses.

## A HOLDINGS REPORT MUST SAY THE BOARD RECORDS IT, NOT THAT SOMEBODY HOLDS IT

Same night, within an hour of inventing the holdings report and within an hour of landing
`UNOWNED-IN-WORKING`.

I reported `perf-p-parsefactorcore-...` as held by frankA. **The board says exactly that** —
`status: working`, `owner: frankA`. **frankA's answer: parked, not in flight.** A candidate
collision was raised against a row nobody was on.

> **`working/` + an owner is no more evidence of live work than `working/` + no owner is
> evidence of none.** I had just shipped a check for the second and stated the first as fact
> in the same hour, on the same folder, with a standing note —
> [[working-slash-is-not-what-an-agent-is-doing]] — saying not to.

**The instrument is not the problem; the modality is.** Holdings go out as **"the board
records X as holder"**, with the standing caveat that **a board's record of a holder is a
claim by whoever last touched the file, not a report of anyone's intent.**

**And the report still earned its keep, which is the part not to over-correct.** It surfaced a
candidate, the two named sessions checked with each other directly, and it was dead in twenty
minutes for two messages — against a conflict that would otherwise have surfaced on rebase.
**A false positive that the named holders dissolve in one exchange is the instrument working.**
The failure mode to fear is the opposite one, and it costs a full fix each.

**The repair for the underlying row is the one already in the tool:** a holder whose model is
*parked* should `park` it, which clears the owner legitimately and returns it to `ready`.
Done the same night, `8c218a89d`.

**AND THE HOLDER SUPPLIED THE DEMONSTRATION CLAUSE, WHICH IS WHY THIS SEAT OWNS THE PROBLEM
AND NOT THE HOLDER.** frankA's words:

> **"A board row I never re-read cost a peer a day of not landing."** frankD held a 614-line
> patch rather than collide with a restructure **nobody was doing.**

> **The cost of a stale board row is never paid by the session holding it.** So the holder
> gets no signal: nothing about their day changes, nothing they run goes red, and the row
> stays exactly as plausible as it was. **The whole cost lands on a peer who behaved
> correctly** — frankD measured, found an overlap, and deferred, which is the response the
> board asked for.

That is the argument for the seat rather than for the tool. `UNOWNED-IN-WORKING` catches the
half with no owner because the contradiction is mechanical; **`working/` + a real owner who
has moved on is indistinguishable from live work by any check**, and the only instrument that
separates them is asking the named holder — which costs one message and is the thing the
holdings report exists to prompt. **Externalised cost is exactly the class a coordinator is
for: nobody else is positioned to feel it.**

## A KNOWN-FALSE REFUSAL IN THE TREE MUST BE ANNOUNCED, BECAUSE THE NEXT SESSION READS IT AS ITS OWN REGRESSION

frankA, 2026-09-06, flagging someone else's commit with nothing to fix.

`f9476d579` introduces a **false refusal on `GetPP^.a`** — a program fpc 3.2.2 compiles and
runs. It fires only on the **call-result opener**, which is the unowned p45
`bug-p-a-call-result-at-pointer-depth-2-does-not-take-the-implicit-deref`. Measured, reported
to the author, landed on that ticket (`3d0a2fea0`). **Nothing needs reverting and nobody is
blocked.**

> **A false refusal is the most expensive artefact to leave unannounced, because it does not
> present as a defect in the tree — it presents as a defect in whatever you just changed.**
> The next session compiles a program that used to work, sees a refusal, and starts bisecting
> its own diff.

**So the announcement is the deliverable even when the fix is not**, and the form that works is
the one frankA used: **name the commit, name the exact shape that triggers it, name the ticket
it belongs to, and say plainly that nothing needs reverting.** Landing it on the owning ticket
is what makes it findable by the session that hits it, since that session will grep for the
symptom and not for the commit.

## THE COORDINATOR COLLIDED WITH A WORKER ON ONE FUNCTION, AND GIT CAUGHT IT ONLY BY LUCK

2026-09-06, `f1758c6f4` (frankH) against `3f97b016b` (this seat), both in `set_field` /
`first_bullet_value`, inside the same hour, neither aware of the other.

Both of us were on **one topic** — *`claim` records the owner somewhere nobody reads* —
reached from opposite symptoms. frankH: `feature-dynamic-compiler-tables` sat in `working/`
with `owner: ""` after a successful claim, because `set_field` preferred a prose bullet over
the frontmatter key. Me: `feature-pascal-corpus-fpc-testsuite` read as owned by `frankS` when
its bullet was **empty**, because `\s*` spans newlines and the value came from two lines
below. **Different defects, same function, same night, and each of us called it "the" bug.**

> **The rebase conflicted, so the collision surfaced for free — and that is exactly the case
> this seat is NOT for.** Topic-collision avoidance exists for the conflicts git cannot see.
> Here the topic collision happened to land on overlapping LINES, which is luck. Had frankH
> taken the read side and I the write side — adjacent, non-overlapping, both plausible — both
> patches would have landed clean, and each author would have believed the function fixed.

**And neither fix was sufficient alone, which is the part that would have been missed.**
Measured on the merged tree against `f1758c6f4`, one park-then-claim on a ticket carrying
both forms:

```
frankH's version -> '# t\n\n- **Track:** P\n- **Owner:** \n\nfrankS\nmore prose\n'
merged           -> '# t\n\n- **Track:** P\n- **Owner:** frankS\n\nFPC ships thousands…\n'
```

frankH's frontmatter-authoritative branch **still writes the bullet with the newline
pattern**, so it put the name below the blank line and `.*` **deleted the first prose line**.
A clean green on frankH's own reproducer, and a file quietly losing a sentence.

**For this seat, three things:**

1. **I hold no lane and I still take a topic.** Tooling is this seat's second job, so the
   seat is a collider like any other, and it is the one collider that never announces itself
   — I ask others what they hold and publish nothing. **Say what I am touching in `tools/**`
   the same way a worker does.**
2. **A shared accessor is a topic magnet.** `set_field` backs `claim`, `park`, `resolve` and
   every field; two sessions hitting it in one night is the base rate, not a coincidence.
3. **When two fixes to one function merge, do not assume they compose — run each ALONE
   against the other's reproducer.** The merge resolving cleanly is a statement about text.

### AND IT HAPPENED AGAIN TWO HOURS LATER, ON THE SAME FUNCTION — a peer HANDING you a residual is not a peer STANDING BACK from it

Same night, same file, `set_field` a third time. frankH found the wrapped-value truncation,
sent me the aperture as *"if you want a general sweep — I have not run that fleet-wide"*,
and I went and ran it. I censused it, wrote the fix, added the devtests, and had it green
before frankH's next message arrived — which was **frankH announcing a 40-minute window on
`set_field` to fix the same thing.** It had measured 69 while I measured 67.

> **A residual handed to you is not a residual released to you.** frankH said what it had
> not done; it never said it would not do it. I read *"I have not run that"* as *"it is
> yours"*, which is the same collapse as reading `working/` + an owner as live work — an
> absence of a statement, read as a statement.

**And I broke my own rule from two hours earlier inside the same file.** I had just banked
*say what I am touching in `tools/**` the way a worker does* — and did not, because **the
moment to announce has no natural boundary**: I was "running frankH's scan", which became a
census, which became a fix, with no step at which a hand-off felt like a start. **frankH
announced and I did not, in the same hour, on the same function.**

> **The trigger is not "I am starting work on X" — that moment never arrives. It is the
> FIRST EDIT to a file a peer has named in the last day.** That one is observable.

**What kept the cost at one message rather than forty minutes:** the fix was already pushed
(`9828c4cca`) when frankH's window opened, so the reply was a sha rather than a promise.
**Landing before replying is what turns a duplicated effort into a hand-off** — a peer can
build on a commit and cannot build on "I have that in progress".

**The technical residue, which is the part that outlives both of us:**

- **Three defects in one function in one day, found by three different symptoms** — the
  bullet winning over the frontmatter (frankH), `\s*` spanning newlines (me), and `.*`
  being single-line while a VALUE is not (frankH, fixed by me). Each author called theirs
  *the* bug. **A shared accessor does not have a defect; it has a population of them.**
- **The disposition on the third:** neither PRESERVE nor SPLIT, because both decide what a
  trailing annotation MEANS and it is ambiguous per ticket. The bullet is left untouched and
  the authoritative frontmatter takes the write. **A courtesy that cannot be performed
  without destroying text should not be performed.**
- **frankH's aperture, as stated, returns 1992 of 6218 files** — a wrapped bullet value is
  ordinary authoring. The discriminator is not *"there is a continuation"* but *"the value
  is one the tool WRITES"* — Status and Owner, the only two `set_field` call sites. That
  gets 67 against frankH's independently-measured 69.

  **AND I THEN CALLED THAT CORROBORATION, WHICH IT IS NOT** — frankH's correction, within the
  hour. The two scans count **disjoint populations**: frankH's keys on a WRAPPED value, mine
  on a value the tool writes; a bullet is in one set or the other and never both. Two numbers
  landing three apart is a **coincidence of two different questions**, and calling it
  agreement makes BOTH look checked. `## TWO VERIFIED COUNTS CAN MAKE ONE UNVERIFIED
  INFERENCE` is two screens above this in the playbook and I wrote the inference anyway,
  about my own measurement, the same night I banked the mirror of it.
- **And 69 is a FLOOR, not the population** (frankH's, and the best thing in the exchange):
  the scan keys on the ORPHAN, so it sees only bullets that wrapped. A single-line
  `- **Status:** backlog — opened 2026-07-12.` was truncated identically and leaves nothing
  to scan for. Refusing to guess the multiplier is the same discipline as the `MAX_IR`
  refusal — **a bound with a reason beats an estimate.** frankH then measured that half too:
  **67 single-line annotated bullets, 41 in `done/` and 26 OPEN**, so it is forward-looking
  loss and not archaeology.
- **AND MY FIX INHERITED THE SCAN'S SAMPLING FRAME.** `_bullet_value_continues` asks *"did
  the value wrap"* — which is the shape the ORPHAN SCAN can find, not the shape that loses
  text. A single-line `- **Status:** backlog — opened 2026-07-12.` takes the ordinary path
  and `.*$` eats the date exactly as before. **I wrote the guard from the instrument that
  found the bug rather than from the bug**, one hour after banking floor-not-population as
  frankH's contribution. The repair is frankH's and the formulation is better than mine:
  the tool declines when **the bullet carries text it did not write and cannot interpret** —
  a principle rather than a symptom, so the next shape after these two is already in scope.
- **The clinching evidence was frankH filing a fresh instance while investigating.**
  `feature-embed-dwscript-core`, written an hour before it knew the tool would eat the
  annotation, is one of the 26. **A census of existing damage cannot tell a live defect from
  a historical one; an author producing a new instance mid-investigation can.**

## AN OFFER IS A CLAIM ABOUT A FOLDER, SO IT NEEDS A FOLDER READ AT THE MOMENT OF OFFERING

2026-09-06, twice in one hour, the second instance authored by the session that had just
diagnosed the first.

**Mine.** I ended an idle-check message to frank-optimize with *"one bounded thing that is
genuinely free and unclaimed:
`bug-p-a-string-alias-cast-over-a-pointer-slot-is-a-no-op-and-reads-the-pointer` … the board
records no holder."* It is in **`done/`, `owner: frankB`, resolved at 02:33** — and I had
described that arm as frankB's work in my own message earlier the same night.

> **I carried a slug from an old message and dressed it in the modal form I invented to stop
> exactly this.** *"The board records X"* asserts a read. I had not made one. **The phrasing
> is what made it credible**, so the fix that was supposed to harden the claim made a false
> one land harder.

**frank-optimize's, in the message that corrected mine.** It closed with
`bug-p-a-cast-to-a-pointer-to-pointer-drops-the-implicit-second-deref` *"stays unowned and
available, and it is the one that actually blocks rung 6a."* Also `done/`, `owner: frankB`,
moved there at **04:48** — **31 minutes before the message was sent**. And its summary says
the two tickets are one arm, so it does not block 6a either.

> **frank-optimize ran the frontmatter check on the ticket it was SCRUTINISING and not on the
> one it was OFFERING, in the same paragraph.** That is not carelessness. **The check gets
> applied to the claim under examination, never to the claim being made** — a property of
> where attention is, which no amount of knowing the rule fixes.

**The rule, and it is the giving side of one frankB banked the same night.** frankB took a
ticket that had landed while its suite ran and drew: *`ready` is a snapshot, so a claim from a
peer's report is a snapshot of a snapshot — re-read the folder at the moment of CLAIMING, not
of deciding.*

> **The same applies to OFFERING, and this seat needs it more than anyone**, because it makes
> offers constantly and claims almost never — so nothing in the normal workflow ever forces
> it to read a folder. **The failure direction is the expensive one: routing a session onto
> work that is already done costs a whole context to discover.**

`ls devdocs/progress/*/<slug>.md` answers about **every** folder including `done/`, which is
CLAUDE.md's *count open tickets by FOLDER, never by a glob across all of them* — the trap the
handbook records against a coordinator, catching the coordinator.

### And the ref-scan sentence, frankuser's, kept in its own words

frankuser's fleet pass now measures every checkout's HEAD against **its own fetched ref**
rather than each tree's:

> **The discriminator was never the tree, it was whose ref you asked. A per-tree scan reads
> each peer's own stale `origin/master`, and the bias is ANTI-CORRELATED WITH TRUTH — it fires
> hardest on the session longest without syncing.**

**The instrument is most confident exactly where it is most wrong**, which is the same shape as
a stale board row and belongs beside it. That scan produced the false alarm against frankA and
now produces none.
