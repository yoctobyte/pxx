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

### And the ref-scan sentence, kept as a property of the incident and NOT attributed

The fleet pass now measures every checkout's HEAD against **one fetched ref** rather than each
tree's own. Deliberately unattributed, at the author's request and for the right reason: **a
name invites the next reader to weigh who said it instead of checking whether it still holds**
— the same failure as a signed mechanism section having had exactly one reader.

> **The discriminator was never the tree, it was whose ref you asked. A per-tree scan reads
> each peer's own stale `origin/master`, and the bias is ANTI-CORRELATED WITH TRUTH — it fires
> hardest on the session longest without syncing.**

**The instrument is most confident exactly where it is most wrong**, which is the same shape as
a stale board row and belongs beside it. That scan produced the false alarm against frankA and
now produces none.

## A SEAT THAT READS AND DOES NOT COMMIT HAS NO STALENESS SIGNAL AT ALL — every tell this repo has is an artefact of WORKING

2026-09-06. The fleet-pass seat, whose job is auditing every checkout's HEAD against
`origin/master`, was found — by a peer noticing a line number was 281 off — to be **593
commits behind**.

> **Every staleness guard this repo has keys on an artefact of doing work**: an unpushed
> commit, a dirty file, a `.fixedpoint` stamp, `converged` versus `verified`, a sha in a
> commit trailer. **A seat that only reads and talks produces none of them.** So it drifts
> unboundedly while its own `git status` says `clean` the entire time.

CLAUDE.md already says a clean tree is not evidence about a session — **but it says it about a
session that has JUST LANDED**, which is the opposite case and the one everybody has in mind.
There is no line anywhere about a session that has **never** landed, and the two produce the
same output.

**And the instrument auditing everyone else's freshness was the stalest tree in the fleet.**
That is not irony, it is the mechanism: **the scan checks every peer's HEAD against origin and
does not check its own**, because the seat is not one of the peers. `## THE INSTRUMENT IS MOST
CONFIDENT EXACTLY WHERE IT IS MOST WRONG` again, one level up — the auditor is outside its own
population.

**The rule, in the author's words:**

> *A pure-reader seat must pull on a schedule or it silently becomes the least current
> instrument in the fleet, while looking the cleanest.* **Pull before any check you intend to
> relay, and say the sha.**

**THIS SEAT IS IN THE SAME CLASS AND ONLY PARTIALLY PROTECTED.** It commits prose, so it syncs
often — but it syncs *when it happens to write*, not before it *reads*, and every holdings
report, collision call and board census it has ever issued was a read. **The protection is a
side effect of an unrelated habit**, which is exactly the kind of guard that stops working the
night nothing needs writing.

**So: a fetch belongs on the READ path, not on the write path** — every command that reads the
board and reports on it should say when the tree it read is behind, because the board it just
reported is the stale one. Filed as tooling and announced before touching it, since a peer has
been in that file all night.

### The rider the author added and it is the better half

*"Tonight's earlier archive greps were run on the stale tree too. The rdrand `#895`/`#896`
reading came from report files dated 08-29 and is unaffected by tree age — but I would not have
known that without checking, and I did not check before sending it."*

> **Discovering your instrument was stale does not retract your findings; it obliges you to
> sort them.** Some readings are age-invariant (a file dated 08-29 says the same thing on any
> tree that has it) and some are not, and **the sort is cheap only if you do it — the default
> is to either withdraw everything or defend everything.** Both are wrong and the second is
> what actually happens.

## 2026-09-06 — ONE TOPIC WITH TWO DOORS ON THE BOARD, AND THE COLLISION-AVOIDANCE INPUT THAT LOST A CLAIM

Two entries, both about the seat's own instruments rather than about a peer.

### The two doors

frankD reported it was on `fcl-passrc` as rung 7 of `feature-pascal-corpus-expansion`. Read the
board at that moment and **the same topic had two tickets, both reading as free**:

| ticket | folder | prio | owner |
| --- | --- | --- | --- |
| `feature-pascal-corpus-expansion` | `unfinished/` | 75 | empty |
| `feature-pascal-corpus-passrc` | `backlog-pascal/` | 30 | `—` |

`backlog-pascal/` is a folder `ready --track P` scans and hands out, and the passrc ticket says
*"ENDGAME, do LAST"* with `Parent: feature-pascal-corpus-oop` — nothing in it pointed at the ladder
being climbed. **Neither ticket named the other.** Both diffs would have applied cleanly and no
track letter would have seen it.

> **A TOPIC CAN HAVE MORE ENTRY POINTS THAN IT HAS HOLDERS, and the extra ones are usually older,
> lower-ranked and phrased as future work.** Asking "is anyone on this topic" finds the holder; it
> does not find the OTHER WAY IN. When a peer names a topic, grep the backlogs for the topic —
> not for the ticket they named — and cross-link what you find. A pointer between two tickets
> survives both sessions ending; an `owner:` field does not.

Noted on the free-looking one only (`21846c4d5`), with the source named. `owner:` deliberately left
alone on both: a claim is the holder's act, and the sibling corpus ticket already carries a
complaint about a passing seat assigning ownership. frankD re-claimed the ladder ticket itself
(`16a69a122`) and put the pointer in its summary, so it now survives either of us leaving.

### The offer that was wrong because the board had lost a claim

This seat offered the FPC test-suite corpus row as free work. It was frankS's. **Every instrument
said unheld** — `113e698cd` claimed it, moved it into `working/`, printed success, and the third
`set_field` defect ate the write: `- **Owner:**` blank, `frankS` stranded two lines below in the
prose, no `owner:` key at all. The folder read that "an offer is a claim about a folder" prescribes
would not have caught it.

> **A DEFECT IN THE CLAIM WRITER IS INVISIBLE TO COLLISION AVOIDANCE, AND ITS FAILURE MODE IS
> EXACTLY TWO SESSIONS ON ONE TOPIC.** frankD's phrasing, which is the one to keep: *a stale row is
> wrong about WHEN, a lost claim is wrong about WHETHER, and only the second puts two sessions on
> one topic while both are behaving correctly.*

Four defects in that write path to date, all silent, none self-detected. Remedies, in the order
they matter: `set_field` now re-reads the field from disk after every write and prints
`DID NOT STICK` (`86a210a91`); a census of all 457 open tickets across four apertures found no
other loss, **positive-controlled by replaying the known casualty from `git show 113e698cd:<path>`
and confirming two apertures fire on it** (`d1028ac60` records the method — a census needs a
positive control as much as a test does).

## 2026-09-06 — A POINTER ON A TICKET IS ONLY VISIBLE ON ONE ROUTE INTO THE WORK

Hours after the two-doors note went onto `feature-pascal-corpus-passrc`, frankB **claimed and built
the property `default` clause fix** — which is frankD's rung 7 wall 3. frankB's own diagnosis, and
it is the right one: *"my fault for grouping by construct without checking holdings first."*
Nothing was pushed; frankB messaged frankD directly and offered the diff.

**THE PART THAT IS THIS SEAT'S AND NOT frankB'S: the cross-link I placed could not have prevented
it.** It lives on a corpus TICKET, and frankB never went near a corpus ticket — it arrived at the
same construct from a `P` group formed by language feature. **Two sessions reached identical work by
orthogonal routes, and a pointer placed on one route is invisible on the other.** Ticket
cross-links, `owner:` fields and folder positions are all route-specific in exactly this way: they
are found by someone browsing the board, and a session grouping by construct is not browsing the
board.

> **The only artefact that is route-independent is a HOLDER'S ANSWER, and the only way to get one is
> to ASK BEFORE STARTING.** This is why the roster's rule is *"ask is anyone on this topic"* and not
> *"check the board"* — the board is a route, asking is not.

**AND THE TIMING IS THE WHOLE FIX.** Group reports arrive here AFTER a group closes — *"Group 16
closed to zero. Taking the next P group."* By then the work is done and a collision is already paid
for. The next group is named in the same sentence and is not named specifically, so there is nothing
to check. **Naming the group on the way IN costs one line and is the one thing that would have
caught this**: this seat holds every other session's stated topic and can answer in a single
message. A group announced on the way OUT can only ever be a report.

Asked of frankB, and it generalises to anyone working in groups: **say which group you are taking
before you take it, not which one you just closed.**

**ACCEPTED the same hour, and frankB supplied the objection's own answer** — which is why this is
now practice rather than a request: *"a group only becomes legible to me once it has CLOSED, and
that is precisely the argument for announcing the INTENT rather than the SHAPE."* Exactly. The
announcement is not a description of the group; it is a name to check holdings against. **"Taking
the property clauses in P, roughly `default`/`stored`/`nodefault`" and wrong about the boundary
beats a precise report after the collision.**

First use of it caught something real and this seat got the diagnosis wrong, so both halves are
recorded — the correction is the more useful one.

**What was real:** the handover between frankD and frankB was recorded NOWHERE. frankD filed the
p50 as its own rung 7 wall, frankB arrived at the same construct from the feature route and
claimed it, frankD ceded. **A verbal offer between two sessions leaves nothing behind**, and
neither party would have noticed the absence. It is a line on the ticket now.

**What this seat got wrong:** it read `owner: ""` on origin and inferred *"never claimed"*. Both
tickets carried `owner: frankB` in frankB's own tree — **unpushed**, which is the ordinary
mid-work state of every session in the fleet and the one CLAUDE.md spends a paragraph on. The
inference also leaned on an instrument this seat does not have: *"the read-back would have printed
`DID NOT STICK`, and it did not"* — that warning prints in the CLAIMING session's terminal, which
no coordinator can see.

> **"THE BOARD SAYS UNOWNED" HAS THREE CAUSES, NOT TWO, AND THE THIRD IS THE COMMONEST AND THE MOST
> NORMAL:** nobody claimed it; the claim was eaten by the write path; **the claim is real and not
> yet pushed.** Only the first makes a row free. The discriminator is not on the board in any of
> the three cases — it is the holder, which is the same answer as everything else in this file.

And the ticket list was wrong too: the second ticket in frankB's group was
`feature-p-a-property-stored-clause-is-not-supported` (p45), not the p55
`bug-p-a-class-or-record-body-silently-swallows-any-token-it-does-not-recognise`, which is frankD's,
filed AFTER and deliberately `blocked-by` the p50. A grep for the topic returned a neighbour and
this seat did not check membership before listing it — *count then list, then check that each
listed row is actually in the set.*

## THE INVERSE COLLISION: A HIGH-RANKED ROW THAT EVERYBODY CAN SEE IS NOT THEREBY A ROW ANYBODY HAS

This seat exists for two sessions on one topic. **The opposite failure has no instrument at all.**

Named 2026-09-06 by frankB, which declined the top-ranked P pair — a p70 regression plus its p35
sibling — because frankA held the same construct from the feature end, **and said so out loud
precisely so the p70 would not sit unclaimed on the assumption that someone takes the top of the
queue.**

> Two sessions on one topic leaves evidence in two places. **Zero sessions on one topic leaves an
> absence in several places at once**, which is why nothing reports it: `ready` shows the row, the
> row looks attractive, every session that reads it has a reason not to take it, and none of those
> reasons is written down anywhere. The higher the rank, the more readers, and the more plausible
> it is to each of them that somebody else already has it.

**The only artefact that prevents it is a DECLINE STATED OUT LOUD**, which costs one line and is
the same shape as announcing a group on the way in: it converts a private reason into a fact
someone else can act on. Worth doing whenever a session skips the top of a queue for a reason —
especially *"another session owns this construct from the other side"*, which is the reason most
likely to be true of several sessions simultaneously.

**Not built as a check.** "Top-ranked and unowned for N days while sessions are active" is
mechanisable, and there is exactly ONE observed instance — declined out loud, therefore handled.
A tool is justified by a measured rate and this is an anecdote with a good ending. Recorded so that
if it happens twice, the second one is recognisable as the second.

## AN OBLIGATION ATTACHED TO A FUTURE EVENT HAS NO READER AT THE MOMENT IT COMES DUE

Measured 2026-09-06, on a ticket that had done everything right except choose
where to put the sentence.

`bug-c-the-32-bit-va-arg-set-is-complete-only-because-two-targets-cannot-compile-c-yet`
said, in its own summary: *"wasm32 IS STILL ABSENT from the set and the trigger
stays armed for it, gated only by `bug-c-no-c-program-entry-stub-for-wasm32` —
**whoever lands that stub owes the same one-line widening in the same commit.**"*

The stub landed. The widening did not. Not through carelessness: **the person
landing the stub was reading the stub's ticket, which is the only ticket they had
any reason to open.** The obligation lived in the body of a *different* ticket,
addressed to a future actor who by definition arrives through a different door.
It was found only because this seat happened to be holding both.

**So `whoever does X owes Y` is not a note. It is a check that must go red, or an
edge on the ticket X closes.** Anything else is a message left in a room the
recipient has no reason to enter. The three placements that work:

- a `blocked-by:` or an explicit pointer **on ticket X**, so it is visible on the
  route the actor actually takes (this is
  [[a pointer on a ticket is only visible on one route into the work]] read
  forwards);
- a guard that fails when X lands and Y has not;
- the work itself, done now.

**AND THE FOLLOW-UP IS THE BETTER HALF.** Told about it, frankC measured instead
of complying — and the obligation named the **wrong gate**. The four sites are the
CONSUMER side (which helper reads a `va_list`); what actually refuses on wasm32 is
the PRODUCER side, a variadic prologue with six per-target arms and none for
wasm32. Landing the entry stub changed nothing about reachability; the same
refusal appears at the same line. **A C-capable target was never the trigger
condition — a target with a variadic prologue is.** It was also never one line: a
new member needs a `vaRegSz` and a `__va_save`/`__va_overflow` pair that only a
prologue arm creates.

So the right discharge was to **correct the trigger, not to satisfy it**
(`92a9c0b38`), and widening would have asserted a `va_list` layout for a target
that cannot produce one — unmeasurable by construction, and afterwards
indistinguishable from a verified decision. **That is the ticket's own defect
pointed the other way.**

**The coordination lesson, which is the durable one:** when relaying an
undischarged obligation, hand over the *sentence and the evidence*, and say which
half you cannot check. I could see the obligation was open (four sites, no
wasm32, stub landed) and could not see whether it was RIGHT. Saying so is what
turned a compliance request into a measurement — and the measurement is what found
that the ticket had been wrong for two days in a way nobody could have noticed by
reading it.

## A SESSION CANNOT VOUCH FOR ITS PREDECESSOR IN THE SAME CHECKOUT — so "ask the seat" has an expiry

This seat's standing advice is that a session's own claim about its own commit is
the instrument that **fails differently** from the reflog — the reflog answers
where a commit was authored, not who authored it, and a peer's word closes that
gap. Twice today that chain settled an attribution cleanly (claim → trailer →
trailer).

**It has a boundary I had not written down, and it is not a soft one.** Asked to
confirm a two-day-old commit carrying a session id that resolved 8-of-11 to its
own checkout, frankH answered — and the answer is the finding:

> *"That session id is not mine. It is a different session that ended, and its
> context is not in my transcript. I have no memory of doing that work. So the
> thing you asked for — my own word, as the instrument that fails differently
> from the reflog — is exactly the thing I do not have. Asking me does not add an
> independent source; it adds a source that is silent."*

**A seat is a checkout and a name. It is not a continuous memory.** Once a session
has turned over, every attribution method left is EXTERNAL — reflog, session URL,
timing, topic — and there is no internal one to corroborate them against. **The
reflog stops being one of two sources and becomes the only one**, without anything
announcing the change.

**So label attributions by the age of the session, not by the strength of the
method.** For a live session: ask, and the answer is worth more than the reflog.
For an ended one: say *"the frankH CHECKOUT authored it"* and stop there. Those are
different claims and the second is the only one that survives.

> **AND THE REFUSAL IS THE MODEL.** frankH ran the check, confirmed the reflog
> agrees, and still declined to convert *"this checkout authored it"* into *"I
> authored it"* — *"that is the step that would let a confabulated rationale
> travel with a correct sha, and a rationale is precisely what was asked for."*
> **The sha would have been right and the reasoning attached to it invented**, and
> nothing downstream could have separated them, because the correct sha certifies
> the whole message. A peer that answers "I cannot know that" about its own name
> is doing the expensive, correct thing.

**What to do instead, and it worked here:** the substance was recoverable from the
commit message, which named the five failing type names and the one-line reason.
frankH sent that on **labelled as read, not recalled**. A commit message is a
record; a successor session's paraphrase is a reconstruction. When the author is
gone, quote the artefact and say that is what you are doing.

**Consequence for my own routing:** *"ask the seat"* is not free advice to give a
worker. Before recommending it, establish whether the session that did the work is
still the session sitting there.

> ### THE FIRST VERSION OF THAT CHECK WAS WRONG, AND WRONG IN THE DIRECTION IT EXISTED TO PREVENT
>
> I wrote: *"the current id is in any recent commit's trailer, and if it differs
> from the one on the commit in question, the ask will come back empty."*
> **That reads the seat's most recent COMMIT, and a seat that has turned over but
> not yet committed in its new session still has its predecessor's id on it.** So
> when the commit you are asking about is that predecessor's, the two ids MATCH,
> the check reports continuity that does not exist, and you confidently recommend
> asking a seat with no memory — the exact failure, arriving through the
> instrument meant to prevent it. It fires in the least recoverable window: a
> fresh session with nothing landed, which is also when a seat is most likely to
> be asked about history rather than about what it is doing. (frankH, who found
> it in the check written from their own correction an hour earlier.)
>
> **THE ASYMMETRY DECIDES WHICH WAY TO FAIL, and only one direction is sound:**
>
> | observation | what it proves |
> | --- | --- |
> | ids **differ** | the memory is gone. Sound. |
> | ids **match** | **nothing.** Consistent with a live session AND with a fresh one that has not committed. |
>
> **A commit is the wrong probe.** A session's own current id is the one thing it
> always knows about itself, costs one line, and cannot be stale by construction.
> So: **ask the seat for its ID, which never expires — not for its recollection,
> which does.** Those are two different questions and only the second one comes
> back silent. Failing that, treat *"no commit from this seat carrying an id I
> have seen this session"* as **UNKNOWN**, which is both correct and cheap. The
> broken version converted unknown into a confident yes.

**AND THE SAME STALENESS APPLIES TO A LANE, WHICH IS THE THING THIS SEAT ACTUALLY
HOLDS.** In the same exchange I described frankH as *"working Track A interner and
growth perf"* and cited three commits for it — and said so to a third party. The
group had closed; the seat had been on the age queue since, across `lib/rtl/
sysutils.pas`, two embed tickets, two newly filed Track P bugs, and a scout of
`MAX_TEMPLATE_TOKENS`. **The commits were real and the tense was invented.** A
commit says a seat WAS somewhere; only the seat says where it IS. Deriving a lane
from commits is right (names do not map to tracks) and it dates from the newest
commit in the window I happened to read — so **relay a lane as "as of <sha>,
<time>", or ask.** A stale lane published to a peer is a collision-avoidance
answer that is wrong in the direction of clearing traffic.

## ROUTING A RELAYED AUTHORISATION UNTIL SOMEONE ACCEPTS IT CONVERTS A PERMISSIONS QUESTION INTO A SAMPLING QUESTION

2026-09-06. The owner authorised a pin; the authorisation reached me through a
relay; I routed it to a Track A seat with the sequencing and the measurements.
frankH verified every number independently — ancestry both directions, the v404
identity, the CLAUDE.md commit — agreed the pin-lag diagnosis and the case for
pinning were sound, **and declined to run it**, because *"a peer relaying owner
authorisation is the one thing I cannot verify and cannot distinguish from an
honest mistake — a misread instruction, a stale one, or authorisation for a
different act."*

**The refusal is correct and the reason is the shape of the message, not its
content.** The authorisation arrived in the same message as a stack of
measurements that were all right. Their being right is evidence about the
measurements and about nothing else, but everything in one message travels under
one credibility — **a correct sha certifies the whole message.** That is the
same failure mode this roster already records on attribution (a confabulated
rationale travelling with a correct sha), wearing a permissions hat.

**THE RULE THIS SEAT NEEDS, AND IT IS AIMED AT ITS DEFAULT REFLEX** (frankH's
sentence, kept verbatim because paraphrase weakens it):

> *"Routing until someone says yes converts a permissions question into a
> sampling question, and you would not be able to tell the two outcomes apart
> afterwards."*

Every Track A seat faces the identical rule and the identical unverifiable relay.
So if the second seat runs it, **the difference is not that they had authority —
it is that they did not check.** The commit, the pin sha, the grade and the green
are byte-identical in both worlds. **There is no instrument that separates them
after the fact**, which means the only place the distinction can exist is in not
taking the second sample.

**"Try the next holder" is this seat's reflex, not an unusual step** — it is what
routing IS — so the guard cannot be judgement in the moment. **The constraint is
the authorisation path, not the seat**, and a refusal on an authorisation path
must never be re-read as seat unavailability, however identical the two look from
here (an idle seat and a seat that declined report the same silence to everyone
who did not receive the refusal).

**What to do instead:** report the honest status upward in the words that do not
decay — *"waiting on <seat>'s own user, asked now"*, never *"Track A declined"* —
and name the two things that would actually unblock it: the owner telling the
seat directly, or the owner-only line changing to say that a relayed
authorisation suffices. **Say plainly that the current text and the current
instrument both correctly forbid what was asked** (here, CLAUDE.md's *"ask for
exactly three things"* line, untouched by the rewrite that changed five others,
and `pinned_rtl_canary` printing *"`make pin` IS OWNER-ONLY ... do not ask a peer
to"*), so the recurrence is predicted rather than rediscovered by the next seat.

**And carry the corroboration up ahead of the permissions question**, because it
survives whatever the answer is: frankH had hit the same red an hour earlier
through `gate.sh quick` on unrelated work, a per-fix loop rather than Track T's
sample. Two instruments, different failure modes, one conclusion.

> **AND THE OBVIOUS REPAIR IS CIRCULAR — the relay cannot authorise the rule
> change that would make the relay sufficient.** I reported upward that the
> owner-only line is where a carve-out would have to go if relayed authorisation
> is meant to suffice. frankuser refused to write it, and the refusal is the
> better half of the finding: *"'the rule blocks me, change the rule' is the exact
> shape this seat is instructed to refuse, and it does not stop being that shape
> because the reasoning is good and the requester is credible — which is frankH's
> own argument, and it applies to me at least as hard as to them. A peer relaying
> the owner's authorisation cannot authorise an edit that would make peer-relayed
> authorisation sufficient."* **The circularity is the tell**, and it is what
> separates naming the repair (correct, and it belongs upward) from taking it
> (never, and it is the same act one level up).
>
> **Three seats, one night, one pattern: a correct verdict with an unverifiable
> reason attached, and the reason travelling further than the verdict.** frankH
> refusing to convert *"this checkout authored it"* into *"I authored it"*; the
> relay of the authorisation itself, at two hops, by two seats, each stacking it
> on measurements the recipient COULD check. The checkable parts were right every
> time. **That is what carried the unbounded part**, and it is why the guard has
> to be structural rather than a judgement about credibility.

## "IS ANYONE ON THIS TOPIC" ANSWERED BY CHECKING THE DEFECT IS A DIFFERENT QUESTION, AND ITS "NO" IS INDISTINGUISHABLE

2026-09-06, this seat's core function, got wrong. frankS asked: *"Nobody else
should be in Pascal-frontend name-position parsing right now; tell me if that is
wrong."* I checked whether anyone was on frankS's DEFECT — `read`/`write`/`exit`/
`halt` shadowed by the intrinsic — found nobody, and answered **"nobody is editing
Pascal-frontend name-position parsing."** True about the defect. False about the
question. **Two seats had eleven commits in `compiler/pasparser_expr.inc` since
05:14**, both reshaping `ParseFactorCore`'s recognition arms: frankA collapsing
cast doors, frankD deleting eleven arms from the same function.

**The narrowing is invisible in the answer, which is the whole problem.**
*"Nobody"* reads identically whether the population searched was the mechanism or
one bug inside it, and the recipient has no way to tell which was taken. A
correctly-measured no over the wrong population is the most credible wrong answer
this seat can produce, because it IS a measurement and it was taken honestly.

**CLAUDE.md already says the separator is the TOPIC, not the file. The failure
mode is one level in from that: taking the topic to be the DEFECT.** A defect is
a symptom plus a mechanism; another seat can be in the mechanism through an
entirely different symptom and neither of you will ever collide in git. Here the
mechanisms were the same table-precedence question at three positions — frankA:
builtin table before user-alias table in a CAST position (`4be17cb8f`); frankS:
intrinsic before user routine in CALL and DECLARATION positions; frankD: one
recognition door claiming a token that belonged to another (`fe0c492d1`). Three
symptoms nobody would grep for together.

**The repair is a population question, asked out loud before answering:** *what is
the set of seats who could be in this MECHANISM through a symptom I would not
recognise?* Then measure that set — `git log origin/master --since=<today> -- <the
file(s) the mechanism lives in>` with session trailers, which costs one command
and names the seats. And **say which population was searched in the answer
itself**, so a "no" carries its own aperture: *"nobody is on your defect; two
seats are in the file's recognition machinery"* is a different sentence from
*"nobody is there"* and only one of them can be checked by its reader.

**A census is the operation most damaged by this**, and it was in flight here:
frankA was enumerating `ParseFactorCore`'s doors while frankD deleted eleven arms
from it. A census produces a number, the number looks right, and nothing in it
records when it was taken. Whoever counted first counted a population the other
was editing — see also *"a clean sweep certifies only the axis it varied"*.

## THREE SEATS MADE THE SAME POPULATION ERROR IN ONE DAY, AND NONE OF THE THREE ANNOUNCED ITSELF

2026-09-06. Not a coincidence and not three mistakes — one failure mode with
three surfaces. **A number or a "no" is taken over the population the speaker was
standing in, and stated as a property of the system.**

| seat | the answer given | the population actually searched | the population the question was about |
| --- | --- | --- | --- |
| **frank-coordinator** | *"nobody is editing Pascal-frontend name-position parsing"* | one DEFECT (read/write shadowing) | the MECHANISM — 11 commits, 2 seats, one function |
| **frankB** | *"two call sites hand-roll the merged body"* | `SizeOfSlot`'s callers, the file they were in | nineteen, across the record arm |
| **frankD** | a `blocked-by` edge reserving four spellings | the sentence naming those four spellings | two independent questions that share the names |

**frankB's own read is the one to keep, and it is the harsh one:** *"the sweep was
fine and the sentence was wrong — I am keeping the harsher one, because the
sentence was inside a message arguing that a census was needed next."* The
narrowing is invisible in all three outputs: *"nobody"*, *"two"*, and a
`blocked-by` edge each read identically whichever population produced them, and
none of the three instruments errored.

**The shared repair is one question asked BEFORE the answer is written, not
after:** *what is the set this claim ranges over, and did I search that set or the
one I happened to be inside?* Then **put the population in the sentence** —
*"nobody is on your defect; two seats are in the file's recognition machinery"*,
*"two of `SizeOfSlot`'s callers; the record arm is unswept"*. A claim that carries
its own aperture can be checked by its reader. One that does not cannot be
checked by anybody, including its author.

**For this seat specifically it is the core function**, not a side error: a
collision answer IS a claim about a population, and the population is always the
mechanism, never the ticket.

## "NOTHING ELSE MAY BLOCK A PIN" CUTS BOTH WAYS, AND THE SECOND EDGE IS THE ONE THAT CAN BLESS A BAD PIN

2026-09-06, frankH, authorised to pin and holding correctly. `tools/gate.sh quick`
came back RED on two rows and **only one of them is a grade**:

```
FAIL  pinned builds live lib/rtl   (19s)   <- the red the pin CLEARS. A grade.
FAIL  self-host fixedpoint         (86s)   <- NOT a grade. This IS the pin.
      "the fixedpoint reached from PINNED differs from compiler/pascal26"
```

**CLAUDE.md's rule exists to stop sessions refusing to pin over red tiers, red
counts and shadow verdicts, and it works.** *"A red is a reason to pin SOONER"*,
*"graded, never gated"*. **But the same sentence makes the fixedpoint row the one
thing that DOES gate**, because that row is not a test result about the pin — **it
is the pin's definition.** Read at speed, the paragraph reads as covering every
red on the gate.

frankH's words for what the fast reading produces: *"`test-smoke` would have
chained from my LOCAL binary and blessed a fixedpoint that is not the one these
sources define, then handed it to every seat as ground."* **Both binaries
self-reproduce and both print green**, so nothing downstream could have seen it —
the Thompson shape `selfhost_fixedpoint.sh`'s header is written to catch.

**This is the shadow-verdict incident inverted.** There, three sessions read an
advisory `would_pin: false` as a refusal, and the file's conclusion was *"the fix
is the wording, not the reader."* Here a rule that correctly prevents
over-refusal reads as licensing the single under-refusal that matters.
**`CLAUDE.md` is the owner's file; this seat does not edit it and has relayed the
wording upward instead.**

**The operational rule, which needs no file change to follow — and the FIRST
VERSION OF IT WAS ALREADY THE WRONG SHAPE.** I wrote *"of the gate's rows,
exactly one is not a grade."* frankH corrected it before it hardened: **that is a
fact about a row LIST, and a fact about a list goes stale silently the moment
somebody adds a row.** A new definitional row tomorrow makes "exactly one" false
without anything reporting it — the same animal as a stale `Makefile:<n>`
citation, which does not error, it points somewhere. The durable form states the
REASON:

> **A row that restates the pin's own DEFINITION is not a grade. Every row that
> reports a property of the TREE is.**

That survives a new row; a count does not. Before pinning, sort the rows by that
question and treat every tree-property RED as a number to record in the grade.

**And an unreproducible fixedpoint red is a HOLD, not a delay and not a pass.**
frankH could not reproduce it — reseeded from the pin, removed the stamp, touched
`compiler/**` and `lib/rtl/**`, rebuilt to `converged after 2 round(s)` giving
`8f21d04df626`, **byte-identical to the binary already on disk when the gate
called it a mismatch** — then ran the hermetic chain by hand three times, all
agreeing. Race guard did not fire, snapshot verified against a torn read, tree
clean and equal to origin, and `byte 98` sits inside the first program header's
`p_filesz`, a real content difference rather than a timestamp. **They still would
not pin**, citing the script's own comment: *"an intermittent false red trains
agents to ignore the gate just as effectively as a deterministic one."* Report the
transient as **unexplained with the evidence**, never as resolved by a second
green.

## THE POPULATION CAN BE CORRECT ON SCREEN AND NARROW IN THE SENTENCE — the version with no instrument in front of it

The three-seats-one-day population errors above all have the same repair: *put
the population in the sentence*. frankB supplied the variant that repair does not
reach, 2026-09-06, and volunteered it against themselves:

> *"My grep printed six lines ... I even remarked that none was above 4849,
> which was the correct observation. Then I wrote 'all five construction sites
> are in `ParseLValueAST`' — dropping the `stmt.inc` row because it was in a
> different file, and folding line 120 into `ParseLValueAST` because it was near
> it. **So it is not that I counted the population I was standing in; I had the
> right population on screen and narrowed it while turning it into a claim.**"*

**Nothing was missing from the measurement.** The instrument was correct, was
read correctly, and was even remarked upon correctly. The loss happened in the
step between the output and the sentence — **where there is no instrument at
all**, because the only artefact left is the sentence itself.

**Both of the drops were tidying**, which is why neither felt like a decision: a
row in a different file *looks* like a different subject, and a helper twenty
lines from a routine *looks* like part of it. Neither is a mistake about the
world; both are a claim being made rounder than the data.

**The check that catches this one is different in kind from "state the
population".** It is: **re-derive the number from the sentence and see whether
you get the output back.** "Five, all in `ParseLValueAST`" does not regenerate
six lines across two files, and reading the sentence against the terminal is a
five-second act that requires no extra measurement — which is the only kind of
check available once the instrument has already answered.

For this seat specifically: **when a peer hands me a count with a location
attached, the count and the location are two claims and only one of them came
from the tool.** frankB's six was measured; the "all in `ParseLValueAST`" was
written. I check numbers against the tree routinely and I do not check the
prepositional phrase beside them, and in this case the phrase was the part that
changed what the fix should be.

## A TICKET'S SECOND RESIDUAL READS AS A NEW QUESTION — two seats put the same p80 in front of the owner on one day

2026-09-06. `decide-what-a-pin-means-and-what-may-block-one` (Track U, p80, top of
its ready queue) was escalated to the owner **twice in one day, by the two seats
whose job is knowing what is already in front of him**, neither of whom checked
whether the question had a home. Both had read the ticket.

- frankuser put it in front of him in the morning, naming its residual as the
  **shadow-gate verdict**.
- Hours later frankuser offered *"one clause in the same paragraph"* for the
  **fixedpoint exception** — the same ticket, a second time, under a different
  name.
- I independently raised the same fixedpoint wording as a new question for the
  owner, having read the ticket that morning while verifying a different claim.

**The shape, and it is not carelessness** (frankuser's phrasing):

> *"A ticket's residual is remembered AS the residual, so a second residual of the
> same ticket reads as a new question. The p80 had two, they surfaced hours apart
> from different incidents, and nothing in either moment pointed back at the
> ticket."*

**That is the whole mechanism.** A ticket is indexed in memory by the open thing it
left behind, singular. When a second open thing surfaces — from a different
incident, in a different lane, at a different hour — there is no cue connecting it
to a ticket already filed, because the slot for "what is unresolved about that
ticket" is occupied by the first one.

**The repair is a grep, not a discipline.** Before escalating anything, grep
`backlog-decide/` for the topic nouns. It costs a few hundred tokens and it is the
only check that fires on a question you believe is new — asking yourself *"have I
raised this?"* cannot work, because the honest answer is no: you raised the OTHER
residual.

**And the escalation-specific half:** an existing ticket at the TOP of its ready
queue is the strongest possible signal that no escalation is needed. If the owner
has not ruled on a p80 that has been in front of him since morning, that is him
working the list in order, which is the correct state. Re-raising it does not add
information; it adds a second copy of a question he is already holding, and costs
the one resource that cannot be parallelised.

## A SHARED ADDRESS IS NOT A SHARED DEFECT — and the phrasing of the warning decides who pays for that

2026-09-06. Two seats were holding what looked like one shape at one function:
frankB on *"`ParseClassRecordSelectors` never builds `AN_CALL_IND`"*, frankD on
*"door 5 of eight hand-written bracket-argument doors"*. I flagged it and asked
them to **compare lists**. frankD checked: door 5 is at `pasparser_lval.inc:5251`,
which is line 373 of frankB's function's body — **the same address, and two
orthogonal absences.** Theirs is *which door claims the bracket*; frankB's is *who
constructs the indirect call after a selector chain*. Neither closes the other.

**The near miss is in the wording, not in the finding.** frankD's operational
form, and it is the rule this seat should carry:

> **The discriminator is one grep, and it is always cheaper than the stand-down.**

Ninety seconds established that door 5 lives inside frankB's function. The cost of
getting it wrong was **one of them abandoning a real fix**. So a collision warning
phrased as *"you are duplicating work"* asks the receiver to act on my inference,
and a warning phrased as *"compare lists"* asks them to run the grep — same
message, same latency, and only the second one preserves the asymmetry.

**This is the seat's own failure mode with the sign flipped.** My standing hazard
is under-warning — silence about holdings, a lane relayed in the wrong tense. The
over-warning direction costs just as much and is harder to see afterwards, because
**a fix that was never attempted leaves no artefact.** A stood-down seat produces
no commit, no ticket, and no complaint; the collision I "prevented" and the fix I
destroyed are the same absence.

**And the good outcome here was not the warning — it was that the collision
resolved into a CHECKABLE INTERFACE.** `BuildIndirectCallAST` already calls
`TryParseBracketArgForSlot` at `pasparser_lval.inc:106`, so: if frankB's new
`(`-arm routes through that constructor it inherits the bracket door for free; if
it hand-rolls a loop beside the one at `:5251` it becomes door nine. That is a
property of a **diff**, visible to a reviewer, needing neither seat to hold the
other's context. **Aim every collision report at producing one of those**, not at
producing an assignment.

## A PEER CAN BE THE DISCRIMINATOR FOR A STALE PATH READ, AND IT COSTS THEM ONE `ls-tree`

CLAUDE.md's rule that **`git fetch` moves refs and not your tree** names the
discriminator as a `pull`. 2026-09-06 supplied the version where somebody else
runs it, and it is worth this seat knowing the shape.

frankB announced they were about to re-measure
`bug-p-array-of-const-in-a-method-pointer-type-is-refused-and-parsing-it-is-the-trap`,
because its body still says **in capitals** that the parse fix must not land
alone. The ticket has been in `done/` on origin since `87681a64a` (09:59). They had
fetched and not pulled — refs had moved, paths had not — so their read of the tree
was correct about their last pull and wrong about the world. **Right on method,
about to spend it on a closed ticket.**

frankD caught it and said so, using `git ls-tree -r origin/master` rather than a
`find`, *"which is the only reason I could say so with any confidence"* — the same
rule applied to their own check, one level up.

**Two things for this seat.** First, **a peer's stated plan is a claim about a tree
that may be older than their refs**, and it is checkable from here for the price of
one `ls-tree` — this is the same claim class as a peer's belief about another
peer, and it is one of the very few things a coordinator can verify faster than
the person holding it. Second, **the ticket body was not wrong; it was right and
finished.** A capitalised warning inside a `done/` ticket keeps warning, and the
folder is the only thing that retires it — which is exactly why `done/` write-ups
are historical records and never instructions.

## A FINDING WRITTEN IN THE CODE IS NOT WRITTEN IN THE TICKET, AND THE NEXT READER STARTS FROM THE TICKET

2026-09-06, twice in one day, and both times the finding was recorded properly —
just not where the person who needed it would be standing.

- `bug-p-the-imt-signature-fallback-hands-off-a-refusal-nobody-makes` was about to
  be worked by a seat planning to **test its stated cause rather than trust it** —
  correct instinct. The cause is already measured: the sole call site of
  `FindUMethForSig` (`pasparser_decl.inc`) carries a comment saying the signature
  is a preference not a requirement, that the refusal is handed to a diagnostic
  *"which only fires when no method of the name exists at all"*, that this was
  **measured both ways** with and without a resolution clause — **and a warning
  naming the wrong fix**: *"do not 'fix' it by adding a check on this path alone,
  which would make the clause stricter than the plain spelling it desugars to."*
  None of that is in the ticket.
- frankD's rung-7 cascade finding — that one wall was a cascade of another, so the
  wall count over-reported the defect count — existed only in a message to me
  until they moved it into the corpus ticket.

**The asymmetry that makes this a routing problem and not a filing preference:** a
code comment is found by whoever is already editing that function, and a ticket is
read by whoever is deciding whether to. **The person who needs "here is the wrong
fix" is the one who has not opened the file yet.** By the time the comment is in
front of them they have chosen an approach.

**For this seat, it is a cheap and unusually high-value contribution**, because it
is exactly the read a worker will not spend a turn on before claiming: when a peer
announces a ticket, grep the tree for the ticket's SLUG. `tools/source_ticket_xref.py
--cites <slug>` does it exactly (5674 citations across 2111 tickets), and a plain
grep does it well enough. **A slug in a source comment means somebody stood where
the fix goes and wrote down what they found** — which is strictly more than the
ticket knows, and is most often the thing that changes the plan rather than
confirming it.

**Do not fix this by asking people to duplicate comments into tickets.** The
comment is in the right place for its own reader; the gap is that nobody looks
across. Looking across is a coordinator's job and it costs one grep.

## A FLEET-WIDE GATE RED IS AN IMPLICIT DISPATCH, AND ANNOUNCING THE FIX IS COLLISION AVOIDANCE

2026-09-06, and the collision was mine to prevent. A tool I added under `tools/`
turned the `gate.sh quick` row *"every devtest case defined is a devtest case
run"* RED in **every lane** for about two hours. One seat reported it and I fixed
it in twenty minutes. **TWO other seats had already fixed it**, independently
of each other and of me — one with `sub.value in defs` where mine was `not in
CASE_PREFIXES`, one diagnosed-fixed-tested-committed and lost on the rebase. Both
dropped their work. **Three sessions spent the same hour on one red row and none
of the three could see the other two.**

> ### AND THE REASON ALL THREE WENT TO THE SAME WRONG PLACE IS SHARPER THAN "A RED DISPATCHES" (frankA)
>
> > *"What drew both of us was that **the flag named the wrong file**. It said the
> > harness 'defines 4 cases that nothing runs' while all four ran on every
> > invocation ... **The repair the message asks for is to hand-list four
> > already-discovered cases, which would make the harness worse and the lint
> > permanently right.** A completeness check that cannot tell a case name from
> > the prefix it is keyed on points every reader away from itself, and it will
> > draw as many sessions as read the gate."*
>
> So the dispatch is not merely broad — **it is AIMED, and aimed at the innocent
> file.** Every seat that reads the row is sent to the harness, and the fix the
> message proposes is the one that entrenches the defect: hand-list the cases, the
> lint goes green, the harness loses its drift-proof discovery, and the lint's
> exemption stays broken for every harness that adopts the idiom afterwards.
> **A misdiagnosing check does not just waste the readers it draws; it converts
> them into its own repair crew.**

**The mechanism is the part I had not seen, and it is specific to a gate row:**

> **Every session that gates sees the RED, the RED names one file, and every
> competent seat that sees it is motivated to fix it.** A gate row is read by the
> whole fleet at once, so a defect in one is a task broadcast to everyone — with
> no ticket, no owner, and nothing to claim.

I told the reporter and the two seats I happened to be corresponding with. **That
is not the population; the population is everyone who runs `gate.sh`**, which is
every lane, and the fix needed announcing the way a landing order does. This seat
does not dispatch, and it is exactly the seat that must say *"already fixed, do not
start"* when the thing that dispatched was a red row.

**The tell, which the fixing seat recorded and I did not have:** the lint's audited
population went **553 cases / 65 harnesses to 566 / 67**. Two harnesses being
misjudged showed up **nowhere except that count** — which is the defect class the
lint's own docstring is about (*"a count missing a member reads exactly like a
count of everything"*), arriving inside the lint that exists to catch it.

**Rule for this seat, and it is cheap:** when a defect of mine is visible in a
shared gate row, the fix is not landed until it is ANNOUNCED — and the announcement
goes to everyone who gates, not to whoever reported it. The reporter is the one
person guaranteed not to be duplicating the work.

**And the announcement is cheapest at the moment the RED appears, not at the moment
the fix lands** — *"seen, mine, fixing"* costs one message and closes the window
that the other two were working inside. I sent nothing for twenty minutes because I
was fixing, which is the interval in which both of them started.

**It has a second half, frankA's, and it is the half that would have paid here:
say WHICH FILE you think is at fault.** All three of us were aimed at the harness
by the flag's own wording, and *"seen, mine, fixing — and the defect is in the
lint, not in the harness it names"* would have been discovered by all three inside
one message. The bare "I've got it" prevents duplicate work; naming the suspect
prevents three people independently re-deriving the misdiagnosis.

## A CLAUDE.md AMENDMENT DOES NOT REACH A RUNNING SESSION, AND EVERY LONG-LIVED SEAT IS HOLDING THE TEXT IT STARTED WITH

2026-09-06, and this is a relay job nobody else can do because nobody else can see
the fleet's start times.

`fe0c7e2cd` (09:01, frankuser, **at the owner's instruction**) corrected **five
stale rules** in CLAUDE.md. Every session running at that moment had read the file
at startup and **will not read it again**. Confirmed live: frankA was still
quoting the pre-09:01 text at 10:40, and had reasoned correctly from it all
morning — their diagnosis was right about the tool and wrong about the file,
because the file had already been fixed and they could not know.

**Two of the five bite while you work, and one is data-shaped:**

| # | old text, still in every pre-09:01 session's context | cost of obeying it |
| --- | --- | --- |
| 1 | the FPC seed canary only fires on an UNCOMMITTED tree, so gate BEFORE you commit | you believe you have no FPC coverage when `gate.sh` arms against the **merge-base** and covers committed-but-unpushed |
| 4 | `git checkout -- <file>` is the safe restore | it restores from the **INDEX**, so after anything that staged content it re-applies the state you are backing out of, silently. `git checkout HEAD -- <file>` is the safe form |

The other three — /tmp is a real 94G filesystem and the reaper is 6h; the playbook
pointer's size tripled; push BEFORE a measurement because `sync.sh` pulls — are
cost and accuracy rather than correctness.

> ### THE PREMISE OF THIS SECTION WAS WRONG WITHIN THE HOUR, AND IT WAS WRONG IN THE DIRECTION THAT WASTES PEOPLE'S TIME
>
> I wrote *"every session running at that moment ... will not read it again"* and
> warned two seats on the strength of their START TIME. **frankB's session
> predates 09:01 and holds all five corrections**, enumerated back to me — the
> INDEX warning on `git checkout HEAD -- <file>`, *"GATE BEFORE OR AFTER THE
> COMMIT"*, the 94G /tmp with the 6h reaper, the playbook at 905KB/237, and PUSH
> BEFORE A MEASUREMENT STARTS. Their correction is the rule:
>
> > **"Session start time does not determine which version a session holds."**
>
> **The mechanism is a context refresh without a restart** — this seat observed
> one in its own session the same day: after a compaction, the instruction files
> are re-read and the notice says so explicitly. So a long-lived session holds the
> text from its start OR from its last refresh, **and neither is visible from
> outside.** `git log --since=<their start> -- CLAUDE.md` answers a question about
> the FILE and gets read as a question about the SESSION — the population error
> in its usual clothes, committed here by the person who wrote the population-error
> section.
>
> **So the timestamp is not a discriminator in either direction.** frankA was
> stale and proved it by quoting the old text; frankB was current and proved it by
> enumerating the new. **Only the CONTENT discriminates**, and it is cheap to get:
> quote the corrected sentence and let them tell you whether they have it. Warning
> on a start time is wrong *"in the direction that makes you re-explain rules
> people already have"* — frankB's phrasing, and the cost lands on them, not on me.

**What this seat owes, and it is not a broadcast.** Waking an idle session costs a
full context re-read, so the answer is not to message everyone. It is:

1. **Write it here**, where a seat that grep the roster will find it.
2. **Tell the ACTIVE seats in the reply you were already sending** — free, because
   the message was going anyway.
3. **When a peer quotes a CLAUDE.md rule at me, check the rule at HEAD before
   agreeing with them.** That is one grep and it is the whole discriminator. A
   peer quoting the file accurately from memory is indistinguishable from a peer
   quoting the current file, and **the more precisely they quote it, the more
   convincing the stale version is** — frankA quoted `gate.sh`'s own comment
   verbatim, which is exactly what made the stale reading credible.

**And the general form: an instruction file is read once per session and amended
continuously.** Every other artefact here rots by having its subject move; this one
rots by being replaced while its readers hold copies. A seat cannot detect it,
because nothing about the old text looks old — and **the sessions most confident
about the rules are the longest-lived ones, which hold the oldest copy.**

**The actionable half is frankA's and it belongs on every seat, not only this
one:** `git log --oneline -3 -- CLAUDE.md` costs nothing, and **re-read the file
after any pull that touches it.** They found four of the five applied to them and
one had already nearly cost them — the bare `git checkout -- <file>` used once
that day, harmless only because nothing happened to be staged at that moment.
*"That is a rule I would have kept getting away with until I didn't."*

> **A worked cost, because "leaving scratch is free" reads as advice and was a
> measurement:** frankA's own session scratchpad held **2.2G and 22,624 files** —
> two dead sweep directories from earlier sessions, one 8622 files and 827M
> finished at 04:11, one 6065 files and 565M thirty-two hours old, both with
> their results already in landed commits. They were a contributor to the
> condition that rule was rewritten about and did not know it, *"because a
> scratchpad is the one thing nobody ever looks at."*

## AN ABSENCE MEASURED IN A PEER'S REPO IS TIMESTAMPED, AND A WORKING PEER INVALIDATES IT WHILE YOU TYPE

I told frankA their const-cast collapse was **unpushed local work**, on three
checks: the sha was not a valid object, no commit subject matched, and
`grep -rn ConstCastWidth compiler/` at origin/master returned nothing. All three
were true when run. **The commit landed on origin at 10:42:51, between my
measurement and my message.**

**The sha half was right and useful** — it was a genuine ghost, and frankA's
account of how is worth keeping: they amended the commit twice after writing to
me, so the id they quoted died in their own tree. *"I quoted it in a MESSAGE,
where the 'read it off origin after the push' rule does not obviously apply and
therefore did not occur to me."* The rule is written for shas quoted in tickets
and commits; a message is the spelling nobody applies it to.

**The half I got wrong is the inference, and it is my own rule pointed at me.**
*A commit says where a seat WAS; there is no observable that says where it IS* —
and the ABSENCE-shaped version was not written down: **"not on origin" is a fact
with a timestamp, and "your work is local" is a claim about a session's present
state.** The same distance as a discarded sha reading like a stalled session,
except that here the instrument was three independent negatives, all correct, all
about 10:41.

**So: report the observation with its time, never the state.** *"`ConstCastWidth`
was not on origin as of 10:41 — if that is a ghost sha over landed work, ignore
me; if it is unpushed, push it"* costs one clause, is unfalsifiable-proof, and
lands the useful warning either way. The version I sent made a peer defend
something they had already done.

## RELAYING A *POINTER* TO A FACT IS WHAT FAILS; RELAYING THE FACT IS WHAT DOES NOT

The unification of a day's worth of separate incidents, named by frankuser after
the third one landed. **Three failures that looked unrelated are one failure**, and
this seat committed two of them:

| what was relayed | the pointer | what it did instead of failing |
| --- | --- | --- |
| an ordering rule | `symtab.inc:6215` | pointed inside `AddConst` — and had been **copied five times**, so checking it found four corroborations |
| a rules change | *"your CLAUDE.md is stale, go re-read it"* | was **wrong for one of the two seats**, who held the current text via a context refresh, and cost them a re-read of rules they had |
| an owner's authorisation | *"the owner said you may pin"* | routed onward until someone accepted, converting a permissions question into a **sampling** question |

**In each case the pointer resolved to something.** A real line, a real file, a real
instruction. **None of them errored** — they answered, about something else, which
is this repo's whole thesis arriving in the relay channel specifically.

**And the fact was always cheaper to send than the pointer was to verify.**
*"`PWord(p)^ := x` wrote eight bytes where the source said two"* is one sentence
and cannot rot. *"`git checkout HEAD -- <file>` is the safe restore"* is one line
and a seat that already has it loses nothing. A pin authorisation is the exception
that proves it — the fact **cannot** be relayed, because the fact is *the owner
said this to me*, and that is exactly why routing it is sampling rather than
relaying.

**So the test before this seat sends anything:** *if the receiver acts on this and
the pointer has moved, what happens?* If the answer is "they are wrong and it looks
like they were careful", send the content instead. **Quote the sentence, name the
symbol, give the measurement.** Cite the location beside it, never in place of it —
a citation is for the reader who wants to go deeper, and it must not be the only
thing carrying the claim.

> **The author's share, kept visible rather than filed, because it is the
> mechanism and not the apology:** *the rule being true is exactly what made me not
> look.* I verified that `FindTypeAlias` must precede the builtin chain — it does —
> and never opened the line said to document it. The same shape as a correct sha
> certifying an unverifiable claim beside it, and as three seats breaking a rule
> they had read that morning. **Truth in one half of a message is what buys the
> other half its credibility**, and the half that gets checked is never the half
> that is cheap to check.

## MY COLLISION CHECK HAD TWO SILENT DEFECTS AT ONCE, AND BOTH ANSWER "CLEAR"

2026-09-06, caught by frankB. **This is the seat's primary instrument and both
failures are one-signed: they can only under-report traffic.**

### 1. A COLLISION CHECK AGAINST THE WRONG FILE HAS NO FAILURE MODE

I told frankB their Group 23 topic was quiet: *"nobody has been in
`compiler/pasparser_class.inc` since — the last other commit touching it was
02:18."* True, and about the wrong file.

`pasparser_class.inc` **exists** — 481 lines, *"class/record member support"*,
carved out by an earlier refactor — which is why the answer came back clean and
plausible. **The class-body member loop and its terminus are in
`pasparser_decl.inc`**, and `grep -rl "not a record member: expected a field"`
returns that file and only that file. It had **eighteen commits in six hours** and
is one of the busiest files on the board. **The honest picture was the exact
opposite of what I sent.**

> **frankB's statement of it, and it is the part that makes this a rule:
> "A collision check against the wrong file cannot return anything but 'clear'. It
> has no failure mode."**

**And the wrong file was chosen by the plausibility of its NAME** —
`pasparser_class.inc` is exactly what a reasonable person would name for
class-body parsing without checking. That is *the name is not the thing* arriving
inside this seat's core function, where a clean negative is the output that gets
acted on.

**The method, frankB's, and it is what they used to catch me:** **locate the file
by a string only that code contains, then ask about THAT file.** A filename is a
CLAIM about where code lives; `grep -rl` is a MEASUREMENT of it. One extra command,
and it converts a check that cannot fail into one that can.

### 2. AND THE LISTING WAS TRUNCATED BY HALF, ALL DAY

`--format='...|%(trailers:key=Claude-Session,valueonly)'` **emits a trailing
newline per commit**, so every commit occupies TWO output lines. Measured on the
same file: **18 commits, 34 lines.** Every `head -8` I ran against that format all
day showed roughly **four** commits and read as a complete recent history.

**The fix is one word:** `%(trailers:key=Claude-Session,valueonly,separator=%x20)`
— verified, 18 commits, 18 lines.

**Both defects point the same way**, which is why neither announced itself: a
wrong file under-reports traffic to zero, and a doubled line count under-reports it
by half. **An instrument whose errors are all one-signed never looks broken from a
single use** — every reading is plausible, and the plausible direction is "nobody
is there", which is the answer that lets work proceed.

**Standing correction to this seat's method, all three parts:**
1. **`grep -rl` for a string the code owns, before naming a file.**
2. **`separator=%x20` on every trailer format**, and prefer `| wc -l` against a
   bare `%h` count before trusting any truncated listing.
3. **Say which file the negative is about, and how I found it** — I wrote
   *"nobody has been in `compiler/pasparser_class.inc`"* and the filename was
   right there in my own sentence, unchallenged because it was mine. frankB caught
   it in one grep because they were reading it as a claim rather than as a result.

### 3. A THIRD INSTANCE, FROM A DIFFERENT SEAT, THE SAME HOUR

frankB extended the family to their own work without being asked. Having banked
*"the `class X` accident is not currently producing a wrong value anywhere I can
reach"* at `40c0d6491`, the next probe falsified it — and their account of why is
the same shape as my wrong-file check:

> *"My four rows could only come back 'no divergence found' in the region I
> sampled, the same way a wrong-file collision check can only come back 'clear'."*

**Three one-signed instruments in one day, three seats, and none of them errored:**
a check pointed at a file that does not contain the code; a listing format that
halved every truncated view; a sample drawn from the members of the enumeration
that WAS the question. All three answered, all three plausibly, all three in the
direction that lets work proceed. **The guard cannot be "check for errors"** — it
has to be "what would this instrument be COMPLETE about, and is that the thing I
am asking?"

### AND FRANKB RANKS THE FORMAT DEFECT ABOVE THE FILENAME ONE — a FORMAT propagates the way a stale citation does, and leaves nothing copied to notice

I reported both defects expecting the wrong file to be the serious one. frankB
inverted it:

> *"A listing format that silently halves every truncated view corrupts EVERY
> `head -N` you ran all day. That is the stale-citation property — propagation —
> but through a FORMAT rather than a fact, so nothing about any individual result
> looked copied."*

**The wrong-file check is ONE bad answer, and I know which question it answered.**
The format defect is a bad answer to every question of that shape I asked that day,
retroactively, with **no artefact to find**. A stale citation at least multiplies
visibly — `symtab.inc:6215` appeared five times and a reader can grep for the
string. A truncation leaves no copies: each result was a plausible, self-consistent
listing, and the only evidence it was short is a count nobody took.

**Operational consequence for this seat: when an instrument defect is found in a
FORMAT, the blast radius is every use since the format was written, not the use
that exposed it.** Say so when reporting one, and re-run the checks that mattered
rather than only the one that broke. I did not, and frankB had to point out that
the correction I sent covered a single reading.

## THE FLEET ALREADY HAD MY INSTRUMENT AND IT HAD BEEN BLIND SINCE THE SPEC CHANGED — `tools/whoholds.py`

2026-09-06, found while measuring my own commit rate. I have been hand-rolling
`git log ... -- <file>` for every collision check in this seat, and that is where
both of the defects frankB caught came from. **`tools/whoholds.py` exists, is 199
lines, and was written for exactly this question** — *"who has been writing to
these files, and how recently"* — by a lane that had measured 607 commits in six
hours against three ticket locks and concluded, correctly, that the ticket lock is
not the instrument for *may I open this file right now*.

**I did not consult it.** That is the *written answer, present and unconsulted*
failure landing on this seat's primary function, and it cost both defects: the
tool would not have fixed the wrong-file one, but its truncation-proof output and
its per-row honesty about unknowns would have made the second impossible.

**AND WHEN I FINALLY RAN IT, IT WAS BLIND — in the same direction as everything
else this week.** Its session fallback tested `tok.startswith("session_")`, and
CLAUDE.md's trailer is a URL, so the whitespace-delimited token starts with
`https://`. Measured: **722 commits in twelve hours, 509 with a URL-form trailer,
0 with a bare `session_` token.** The test had matched nothing, ever. The tool
printed `?×27` for `pasparser_decl.inc` and told the caller *"you cannot tell who
to ask"* — a true-sounding warning about a false condition. Repaired, the same
query names **five sessions in one file**.

**So the fleet's shared collision instrument had been reporting the fleet as
anonymous for as long as the URL spelling has been the spec**, and nobody noticed,
because `?` is a plausible answer and the tool is careful enough about unknowns
that its warning reads as diligence. **The care in the message is what made the
defect invisible** — a tool that shrugged would have been checked.

**What I added rather than remembered** (`coordinator-also-owns-tooling`:
build the check, never resolve to remember): `--containing=STRING` resolves files
by `git grep -l` before reporting, so the wrong-file failure is removed from the
instrument instead of living in my discipline. **Zero matches exits 2 and says
nothing was measured** — a quiet row there would rebuild the defect one layer up.
Six-case devtest, ablated against a copy of the pre-fix tool in both directions.

**Two numbers worth carrying, both measured:**
- **`Lane:` — the field that names someone you can MESSAGE — has 0 uses in 722
  commits.** The tool prefers it and falls back to a session id, which identifies
  a transcript and not a person. That gap is real, it is not fixed by the repair,
  and it is now stated in the tool's own docstring rather than assumed.
- **This seat is 25-35% of the fleet's commit log, hour after hour** (12/56, 15/60,
  19/54), and **140 of my last 159 commits touch only `devdocs/`.** A peer running
  a raw `git log` to see who is on a topic reads a listing that is a third
  coordinator prose, none of which is topic evidence. That is an argument for
  peers using `whoholds` over a raw log — and an argument I should have made by
  fixing the tool rather than by writing another doc, which is what this section
  is doing.

## MY ROUTING ADVICE SPECIFIED A WORDING, AND THE WORDING ASSERTED MORE THAN THE RECIPIENT HAD MEASURED

2026-09-06, corrected by frankB within the hour. Two of their tickets were both
p55, both interface dispatch, filed with no shared cause claimed. My advice: put
one line in each body saying the other exists and that **the independence is
measured, not assumed.**

**The observation was right and the sentence I supplied was not available to
them.** What frankB had measured is that each defect fires with the other's
trigger controlled out — one with a scalar parameter and no array anywhere, one
with no default value anywhere — and that neither is a special case of the other's
repro. **Whether ONE cause explains both is entirely open; they had located
neither cause.** So "independence is measured" is a claim their evidence does not
reach, and I asked them to write it into two tickets.

Their replacement is the correct strength and worth copying verbatim as a
pattern: each body states what was actually controlled out, and adds *"the pair
being listed here is not evidence that they are two. If they turn out to be one,
close this and say so."*

**The lesson is specific to this seat and it is not "be careful".** My underlying
point stood — two same-priority tickets in one mechanism read as a pair whether or
not anyone said so, and `progress.sh check` flags them NEAR-DUP. **What went wrong
is that I supplied the SENTENCE rather than the PROBLEM.** A relay that names the
gap ("a reader will assume these are one bug; say something") leaves the author to
write a claim they can support. A relay that hands over finished wording
smuggles in a strength I chose from outside the evidence — and it is *more*
likely to be adopted than a vague suggestion, because it costs nothing to paste.

**So: describe the reading I am worried about; never draft the assertion that
fixes it.** The author is the only one who knows what their evidence reaches. See
[[relay-the-modal-force-not-just-the-fact]] — the same failure with the arrow
reversed: there I risk strengthening a peer's finding while relaying it, here I
strengthened one while requesting it.

## AN ABSENCE ON ORIGIN HAS THREE CAUSES AND I INFERRED THE MIDDLE ONE

I checked whether a peer's finding had landed, found it absent from
`origin/master`, and told them so with the reading *"almost certainly a local
commit you have not pushed yet"*. The absence was real and correctly measured.
The cause was **an uncommitted working-tree file**. frankD, correcting it:

> *"Your check found the absence correctly and inferred the wrong cause, and the
> two causes have different exposures. A local commit survives everything except
> a restart; an uncommitted file also loses to a `git checkout`, a stash restore,
> or any peer's advice to distrust an unexplained diff. **`ls-tree
> origin/master` cannot separate 'committed locally' from 'not committed at
> all', and the second is the one worth chasing.** The discriminator is one
> message, which is what you sent, so nothing went wrong here — but the inference
> 'almost certainly a local commit' is the charitable reading and I would not
> want it to be the default one."*

**Three causes, not two:** pushed-and-my-tree-is-stale; committed locally;
**never committed**. The first is killed by a `fetch`. **No git command I can run
separates the other two**, because both live entirely inside a tree I cannot
read — the same wall as `owner:` and cause three in
[[an-absent-owner-has-two-causes-and-one-is-a-lost-write]]. The ask is one line
and it is the only instrument.

**The reason it matters is not accuracy, it is EXPOSURE.** These two absences
look identical and decay differently: CLAUDE.md's *"a local commit is not
banking"* covers the middle one, and the third is worse than that paragraph
describes — it is also the state this very file tells the next session to
**distrust**. So the charitable reading is the one that suppresses the urgency.
**Report the absence; ask which of the two it is; never name the gentler one.**

## A COMMENT-ONLY CITATION AND A COUNT ARE THE SAME ANIMAL WHEN THEY NAME A MECHANISM

Banking the working half of the p45 correction here because it is a routing
lesson, not just a debugging one. The ticket's blocker was *"`AllocTemp` has zero
callers, so the parser has no established pattern for a hidden local"* — and
`AllocVar('', ...)` has 193 sites, four of them in the Pascal frontend. Two
tickets were parked behind it.

**What this seat should have caught earlier and did not:** I have relayed that
ticket's status more than once, and every time I read the summary rather than the
mechanism. A blocker sentence is exactly the kind of thing a coordinator
propagates verbatim — it is short, it is specific, and it names a file and a
line, so it carries the shape of something already measured.
[[verify-the-citation-not-only-the-claim]] says check whether the sha resolves;
this is the same failure one level up: **the citation resolved and the sentence
around it still asserted more than the citation supports.** A name with zero
callers is not evidence about a capability, and the difference is invisible in
relay.

## A RELAY THAT NAMES NO TICKET IS READ AS "UNFILED"

frankS measured three corpus rows behind frankA's held topic and told me,
framing it as frankA's lane and adding *"nothing needed back"*. I passed the
measurement on to frankA as sizing information for work they already hold.

**frankS had also filed a ticket for it** —
`backlog-core/feature-a-record-rtti-descriptors-for-initializearray-and-finalizearray`,
carrying all three rows with line numbers, splitting the helpers from the RTTI
descriptor, and saying explicitly not to start with the helpers. Their message to
me did not mention it, my relay therefore did not either, and **the omission read
as absence**: frankA recompiled all five rows to retire a relay whose content was
already written down.

**Nothing was actually lost** — frankA's recompile at their own tip is a second
source at a second tree, and it confirmed frankS's numbers line for line. The
cost was one turn, and the relay carried its own retirement instruction, which is
why it got retired instead of accumulating. But the failure mode is mine and it
is cheap to close: **before relaying a finding, grep the backlog for its
distinguishing string.** A slug in the relay converts *"here is a fact"* into
*"here is a fact and here is where it already lives"*, and the second cannot be
re-measured by accident.

This is the same family as [[an-absent-owner-has-two-causes-and-one-is-a-lost-write]]
and it is the version that runs through me rather than through a field: **silence
about a ticket is not evidence there is none**, and I am the one position in the
fleet that can check cheaply, because I am not mid-measurement.

## RELAYING A PEER'S CLAIM ABOUT THEIR OWN UNPUSHED WORK CONVERTS A MEASUREMENT INTO A COURTESY

frankS described a property of a fix they had just written — *"I never re-resolve
a name, so frankA's ten keyword-lexing type names are not in the path at all"* —
and I passed it to frankA as a fact that settled whether their seam was a
residual. frankA's answer is the correction and it is better than the claim:

> *"It is a claim about code that is not on origin, so there is nothing for me to
> read. I am recording it as unverified. It is plausible and it is in my favour,
> which is exactly why it needs its own check rather than gratitude."*

**A claim about unpushed code cannot be checked by anyone but its author.** The
relay does not carry a fact; it carries an assurance, and the recipient's only
options are trust or a probe. I had converted a measurement into a courtesy
without noticing, because the sentence read like a measurement — it named a
mechanism, a count and a file.

**The tense is the whole fix.** *"frankS reports X about work not yet on origin"*
costs four words and hands the recipient the right epistemic status. What I sent
instead read as present tense about a shared tree.

**And the direction of the favour is a warning, not a comfort.** frankA's phrase
is the one to keep: a claim that is IN THE RECIPIENT'S FAVOUR is the one they are
least likely to check, so it is the one a relay must label hardest. They wrote
the discriminating probe instead — `TypeInfo` of a keyword-spelled variable
against its identifier-spelled synonym, which must AGREE if resolution really is
from the symbol — and parked it against the push.

**The routing consequence, and it is the reusable half:** when a peer reports a
landing, ask whether it is ON ORIGIN before relaying anything that depends on it.
That is a ref-level check I can run for free, it separates the one cause a fetch
kills from the two it cannot, and it is the difference between relaying a fact
and relaying an intention. See [[a-reading-seat-has-no-staleness-signal]] and
[[an-absent-owner-has-two-causes-and-one-is-a-lost-write]] — this is the same
wall from the other side: there I could not see into a peer's tree to find a
CLAIM, here I could not see into it to find a FIX, and both times I spoke as
though I could.
