# Instruments that answered the wrong question — 2026-09-02

Twenty findings from one evening's shortstring overhaul, seven backends and eight
sessions. **Not a rules file** — these are measured instances, kept because the
mechanism recurred often enough in one night to be a property of the work rather
than eight lapses.

**The single mechanism:** every instrument that misled tonight was **correct about
something else**. None errored. All answered. A missing runner arm read as a
missing target; an ESP-platform refusal read as a target verdict; `grep -c` read
as a call count; a writer census read as a dependency census; a byte dump read
without its config; `| tail` read as a program's exit status.

CLAUDE.md already states that mechanism verbatim, and six sessions with the file
loaded hit it anyway in three hours. **So the useful part is not another phrasing
of the rule — it is the blast radius and the question of what RUNS it.**


- **Liveness is not coverage.** A positive control proves an assertion can detect
  a defect it MEETS; it says nothing about whether it meets one. Three sessions
  hit this in one evening, all careful.
- **A relation between two things that can fail TOGETHER is not a guard.**
  frankh-15's "deref store writes the same bytes as a direct store" passes while
  the slot is corrupt. Remedy: DERIVE the width (`SizeOf` minus capacity) and
  assert byte positions absolutely, staying target-independent.
- **A partition is evidence that causes differ, never evidence of what they are.**
  Cost us a wrong single-cause model that three sessions "corroborated" — all
  three were readings of one inference.
- **The census counted WRITERS.** Comparison and `SetLength` are READERS and were
  in nobody's count.
- **What runs a rule?** Six stated rules did not fire tonight across six sessions
  with CLAUDE.md loaded; the one that fired was a mechanical step inside a build
  procedure. Where the answer is "the reader, if they remember", expect it to
  miss — the moment you reach for an instrument is the moment you are confident,
  and confidence is the state the rule exists to interrupt.
- **A control must VARY the thing it controls for, and say in advance what it
  prints if you are WRONG.** Two controls tonight had the same description —
  "compile an untouched target" — and opposite evidentiary value. The vacuous one
  held both arms at the same commit, so it printed IDENTICAL whether the
  explanation was true or false, *and the script echoed the conclusion as if it
  were a result*. The real one varied the commit and printed DIFFERS with the
  changed blob hash. **Never let a script echo a conclusion.**
- **Row ordering is a HARNESS property, not one file's quirk.** A row that ends
  the process costs every row behind it, so **a crashing test reports LESS the
  worse the state is** — backwards from what a diagnostic should do. Re-check it
  whenever a fix moves which row crashes; it already moved once (first killer was
  `assign from field`, now `compare field to literal`), and that single row is
  currently hiding the verdict of eleven rows behind it on two backends.
- **Cite by CONSTRUCT, not by line.** Two of the three line numbers this document
  originally carried had already drifted within the same evening — arm32's onto a
  procedure header. **A stale line number does not error; it points somewhere.**
- **A population figure needs a DATE, or it keeps answering about the tree it was
  taken on.** "riscv32 refuses the flag" was TRUE when measured and became false
  when riscv32 was converted — an **expired** measurement, not a wrong one, and
  the more dangerous kind: the quoted diagnostic is a real string the compiler
  once printed, so nothing about it ever comes to look false.
- **A clean tree one commit ahead is the signature of a session BETWEEN commit and
  push**, not of stranded work. Sampled in that gap twice tonight; ref-level
  checks (`merge-base --is-ancestor`, `ls-tree origin/master`) are the discriminator.
- **A control can be vacuous because your work is STAGED.** frankA's first
  isolation attempt had the diff staged, so `git diff` came back empty and
  `git checkout --` restored from the *index* — both arms identical by
  construction, and it would have printed a clean 11/11. **Two tells, both
  present: a zero-line patch, and both rebuilds printing `verified` instead of
  `converged`.** Third vacuous control caught tonight, each by a different session.
- **A correct decision can carry a WRONG REASON, and the reason is what the next
  reader inherits.** Twice tonight, by the same session: the compare hold was
  justified partly as "repair arm32 first and the prediction is unfalsifiable"
  when arm32 had *already* been repaired in a commit predating the hold; and a
  deferral was filed under "review already catches it" when the item passes that
  test rather than failing it. **Both decisions were right and both labels were
  wrong.** The decision survives on its label — so a label checked less carefully
  than the decision is how a good call becomes bad guidance. Worth watching for
  in any relaying role, where the label travels further than the reasoning.
- **FITTING THE DISTRIBUTION EARNS A DISCRIMINATING RUN, NOT A PROMOTION.** The
  walker theory predicted the surviving field bug's observed split *exactly* —
  segfault on one word size, FALSE on the other — **and was still wrong.** A
  theory that reproduces the shape of the data has earned one more experiment,
  not the status of an explanation. frankb-a9 refuted three theories here,
  including its own written-out one, and the discriminator turned out to be
  homogeneity of operand shape, symmetric in order.
- **NECESSARY IS NOT SUFFICIENT, and the difference is where the residual lives.**
  i386 resolves the operand kind at the `PXXStrEq`/`PXXStrCmp3` decompose — and
  **still crashes on `r.f = 'hello'`.** So resolving there is necessary and not
  sufficient, which is the more useful statement than the fix shape it replaced:
  it says the surviving field bug is **not something any backend got wrong.**
- **Having the probe open is not the same as running it.** The stale comparison
  claim in this document was not a trusted relay — the author had compiled and run
  that exact program on two targets the same minute, and `--target=arm32` was one
  more argument on a command already typed. **This session had independently
  measured all-TRUE on arm32 and wrote the stale claim into the handover anyway.**
  In conversation a stale claim dies with the next message; in a durable artifact
  it is what someone acts on at 8am — applying a real edit to already-correct code,
  or concluding a converted backend was not.
- **The check that catches the worst rung is asked of the WRITING, not the
  measurement.** frankA's ladder: rung two is having the probe open and not
  widening it; **rung three is running it, having the output on screen, and
  writing the contradicting sentence anyway.** Rung three is invisible to every
  process check here — *"did you verify this?"* answers **yes**, truthfully; the
  measurement happened, and only the reading of the prose against it did not. The
  question that catches it: **"which sentence in what I am about to publish does
  this output bear on, and does it agree?"** A handover is the highest-risk place
  for it — mostly prose, written at the end when the measurements feel settled,
  and the one document that gets *acted on* rather than read.
- **`cmd | tail` reports TAIL's exit status, not the program's.** This session
  read `exit=0` off a segfaulting binary that way, minutes after recording the
  same trap from another session. Use `prog > file; rc=$?`. Both survivors
  re-confirmed live at `0f57d8a55` with binary `4ba5c77aacc7`: `p^[1]` blank,
  `r.f = 'hello'` **exit 139**.
- **A SLUG IS THE WORST POSSIBLE CARRIER FOR AN INFERENCE.** One session's
  unmeasured framing — "the failing backends lack a named operand normaliser" —
  became a ticket slug someone else linked to. **That ticket was never filed**, so
  the link read as an open dependency to everything counting them, and the slug
  asserted a partition that turned out wrong twice over (two causes, not one;
  arm32 *has* the layer; x86-64 never calls the helper). A slug gets quoted by
  other tickets **before anyone measures it**.
- **That inference travelled THREE hops through people who each handled it
  responsibly** — into a peer's summary, into an hourly automated prompt, and into
  a third ticket's slug. **Nobody was careless with it and it still travelled.**
  That is the argument for hedging the premise rather than the conclusion: the
  conclusion gets scrutinised at every hop, the premise gets carried.
- **Recovering a bare "state at commit X" ghost: `git log -S <ghost-sha>`.** Subject
  matching is unavailable for a marker with no subject of its own, but the commit
  that *introduced the string* is the commit whose pre-rebase id it was. Safe here
  only because that commit touches no `compiler/` or `lib/` file, so its tree and
  its parent's are identical for every build input — **write the derivation into
  the ticket, not just the answer**, so the next reader can check it.
