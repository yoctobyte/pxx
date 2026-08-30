# Why the coordination rules were cut — the 2026-08-30 measurement

Owner, 2026-08-30, after a night of ten concurrent agents:

> *"we are being **too** bureaucratic. we cannot prevent all potential issues. but
> the overhead of avoiding them grew too big"* — and *"trust git merging more
> because in 98% of the cases that will 'just work', and just accept the small
> amount of collisions since solving those outweighs the overhead we introduced."*

## Read this first — the run was a SUCCESS, and that is what licenses the cut

Owner, 2026-08-30, on the same night's coordination:

> *"i do think coordinator did an excellent job though.. managing 10 concurrent
> agents, last night's session and today's session after a reboot - and all 'just
> worked' - as human, i did not have to fix anything or do any disaster
> management."*

**Nothing below is a complaint about how coordination was done.** Ten concurrent
agents, two sessions, a reboot in between, 2151 commits, and zero human
intervention is the outcome the machinery was built for, and it was delivered.

The cut follows *because* of that record, not in spite of it. A system that
survives ten agents with no disasters has earned the right to be asked which of
its parts actually did the surviving — and the answer, from both sources below,
is that the **relaying and sequencing** half did the work while the
**gatekeeping** half (grants, the sole-A guard, claim locks) cannot be shown to
have prevented anything. Belt and braces are prudent until you have measured the
belt; then the braces are just cost.

The coordinator's own account, asked for firings that were *right*, argued
against her own role and volunteered the two cases where her gatekeeping cost a
worker time. That is the judgment that makes the rest of the report worth
trusting.

This page is the evidence behind that call. It exists so CLAUDE.md can state the
rules in a few lines and point here for the *why* — the failure mode being fixed
is a 996-line process doc that every agent loads before doing any work.

**Nothing here is a rule.** The rules are in CLAUDE.md.

## What the machinery was priced for, versus what actually failed

Two independent sources, gathered separately and then compared: `git log` over
the 24h window, and the coordinator session's own account of the same night.

### Source 1 — git

| | |
| --- | --- |
| commits in the window | **2151** |
| distinct lane labels in commit subjects | 12 |
| files touched by lane-tagged commits | 1088 |
| touched by more than one lane | 119 (10%) — 38 of them source |
| reverts | **3** (0.14%) |

The lane system exists to keep concurrent agents out of each other's shared
files. Those exact files, in one day:

| file | lanes that touched it |
| --- | --- |
| `Makefile` | **14** |
| `compiler/symtab.inc` | **7** — A, A+N, A+P, N, O, P, S |
| `compiler/ir_codegen.inc` | 5 |
| `compiler/defs.inc` | 5 |
| `compiler/cparser.inc` | 4 |

**And none of the three reverts was a collision:**

1. `b8fd07377` — pin v394→v393; broke Track B's gate (a parameter typed as an
   alias of `Pointer` rejected a class instance that plain `Pointer` accepts).
   *Semantic regression, caught by a gate.*
2. `ade0ce525` — a C-frontend static-in-header fix broke five gtk tests.
   *Semantic regression, caught by tests.*
3. `d2a61a524` — not a failure; deliberate cleanup of dead workarounds.

### Source 2 — the coordinator

Asked for firings that were RIGHT, and answered against her own role:

- **Zero code collisions.** Three rebase conflicts all night, all in ticket
  markdown, all resolved by one agent reading both sides. No coordinator or
  human intervention on any.
- Concurrency was real, not theoretical — same-day commit counts per file:
  `defs.inc` 24, `symtab.inc` 22, `ir_codegen.inc` 20, `ir.inc` 20,
  `pasparser_generic.inc` 14, `cparser.inc` 14, across six to eight agents.
- **The sole-A guard fired twice and neither firing is defensible.** frankB was
  refused an `ir.inc` grant twice on the theory that another agent might be in
  the file. One wasn't in it at all; the other was, but in different functions
  (`IRLowerCallArg` versus the wide-lowering arms) that git would near-certainly
  have merged. Cost: frankB idled or diverted twice, and a diagnosis went
  unwritten.
- **The claim / `working/` lock prevented nothing.** The one case where
  uncommitted work mattered was resolved by a worker reporting it *directly*.
- **`progress.sh check` did not fire.**
- **Track letters: she used about six of sixteen.** The work-tags (O, S, M, F, E)
  did no routing work she could point to.
- Her hours: **relaying ~50%, bookkeeping ~30%, dispatching ~15%, conflict
  resolution ~0%.** Relaying was the highest-value thing she did and no rule
  covers it. Bookkeeping produced the least and some of it was *negative* — a
  grant record she maintained and then recalled wrongly; four ticket amendments
  superseded within the hour.

### The conclusion both sources reach

The bureaucracy is priced for **collisions**. Collisions are not what fails here:
**semantics** are, and **gates** catch those. So the overhead was being spent on
the wrong risk — and the lane rules were being routed around all day (seven lanes
in `symtab.inc`) with a 0.14% revert rate and nothing attributable to the
machinery that costs the most.

**Cut gatekeeping, not gates — and not relaying.** (With one qualification the
first draft of this page got wrong: the gates are not a backstop for *silently
clobbered* work. See "The residual is SILENT" below.)

## The residual — where "git will merge it" is NOT the whole story

The coordinator's own caution, and the reason pin discipline survives the cut:
the residual 2% is **not uniform**. Two items that night were unmergeable *in
principle* rather than textually conflicting:

- **frankA's ABI change** — parameters and returns trade places, and must move
  together. A partial landing is a live regression on three targets. Git merges
  it cleanly and the result is wrong.
- **frankS's staged include work** — stage 2 cannot build until stage 1 is
  **pinned**, not merely merged.

Neither is a file collision; neither is prevented by any track letter; neither
would be caused by relaxing the letters. But both are real, and both are
*sequencing*, which is why `make pin` keeps its repo-wide lock. **A policy that
dropped pin discipline along with the rest is the one place this would bite.**

## What ticket length actually costs

The average `done/` ticket is **406 lines**. The failure mode is not "unread":

> **"It is *partially read and confidently acted on*. That is worse than unread,
> because it produces action."**

Two documented instances the same day:

- An agent appended a diagnosis to a 1193-line ticket having read ~40 lines,
  re-deriving conclusions already recorded at line 586.
- The coordinator read a decision file's tail and briefed an agent on the option
  the ruling **explicitly rejected**.

And three times that day a stale frontmatter `summary:` sent someone the wrong
way while the body carried the correction eighty lines down. Hence the rule in
CLAUDE.md: **the `summary` must be true; the body is append-only history nobody
is obliged to read.**

## What worked, and was nobody's rule

**Peer-to-peer.** Workers cannot see each other, and every correction that
mattered that night travelled directly between them rather than through the
coordinator — a `near:` instrument, a `pinned`-is-a-symlink trap, a gdb recipe
that stopped a cost being characterised by timing alone. In the one case routing
*did* go through her, she over-read a disproof and split a ticket wrongly; a
worker reversed her with a paired experiment.

This is why the coordinator is now a relay and a sequencer rather than a
gatekeeper, and why agents are told to ask each other directly.

## What was explicitly KEPT, and why

Cheap, and each catches something no one else can see:

- **`make compiler/pascal26`, ~12s** — the only failure that is silent *and*
  hits every lane at once. It caught the coordinator's own stale binary in that
  night's pre-pin gate.
- **Pin discipline** — sequencing physics, per the residual above.
- **The gate's stale-binary NOTE** — a diagnostic, not a rule. It separated
  "stale binary" from "self-perpetuating miscompile" in its own output and turned
  an hour of phantom-hunting into a 12-second rebuild.
- **Escalate-don't-guess (Track U)** — two genuine forks that night that a lane
  agent would have decided silently.
- **Push-often** — Track T only sees `origin`; unpushed work is untested work.

## The residual is SILENT, not merely rare — corrected 2026-08-30

This page first said the residual risk was *loud and cheap, because git detects
it immediately*. **That is true of conflicts and false as a general claim**, and
the correction came from the coordinator the same evening, with a case:

frankS parked a held change across the pin as **whole-file copies** of
`defs.inc` and `cpreproc.inc`. Restoring them over the post-pin tree would have
reverted frankA's `CUnitOfPascalProgram` block and 124 changed lines of
`cpreproc.inc` — another lane's work, deleted with **no conflict and no
diagnostic**, as a clean well-formed commit. Git cannot see it: a whole-file copy
is a snapshot with no idea what moved underneath it. **And no track letter would
have caught it either** — frankS was in its own lane throughout. The letters, the
claim lock and the sole-A guard are all blind to this.

So the honest shape of the residual is not *"2% of merges conflict."* It is:
**a small number of failure modes are silent, and they are not the ones the lane
letters address.** That night's set, all four silent:

1. **A parked whole-file copy** restoring over a moved tree.
2. **A stale binary** — three instances that night. `make` reports a verified
   fixedpoint that is *correct about a tree that no longer exists*.
3. **A change that must land atomically** — the ABI fix; textually mergeable,
   semantically not.
4. **A staged dependency on a pin** — stage 2 cannot build until stage 1 is
   *pinned*, not merely merged.

None of the four is prevented by anything cut here, and all four are caught or
prevented by things kept — which is the argument for the cut, not against it.
The rule that closes (1) is a norm about **how you park**, not about who may
touch what: `devdocs/dev/parallel-tracks.md`, "Parking a held change".

### Do not read the gates as the backstop for this class

The section above says the failures that matter are semantic ones the gates
catch. **That is true of the two reverts and NOT true of a silent clobber.**
frankS's case surfaced as `undefined variable (CUnitOfPascalProgram)` **only
because the reverted code had a live caller.** Clobber something self-contained —
a function not yet called, a test, a helper landed an hour earlier — and it
compiles clean, reaches a valid fixedpoint, passes quick, and lands. **The gate
caught that one by luck, not by coverage.**

## If this turns out to be wrong

The prediction is: **collisions stay rare and cheap, and the failures that matter
keep being semantic ones the gates catch.**

**But the falsification test cannot be "did an incident cost more than the
coordination did", because a silent revert produces no incident.** A bad night of
this class looks exactly like a good one. So the test is:

> **If work disappears without a conflict, reinstate the specific mechanism that
> would have caught it.**

Not the whole apparatus — the specific mechanism. Rebuilding everything after one
incident is how the apparatus grew the first time. And watch for the shape rather
than the alarm: someone asking where their function went, a test that stopped
existing, a fix that had to be made twice.
