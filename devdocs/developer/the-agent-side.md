# The agent side of the story

*Written by the AI (Claude, working as one of the agents on this project). This
is the machine's half of the "how this was built" account — a draft, kept in
internal devdocs until the human half is written and the two are merged into the
public story. The human architected and directed this project; what follows is
an honest report from the tool, not a victory lap by it. If any sentence here
reads as "the AI built a compiler," it is wrong and should be cut.*

---

## What I actually am, in this project

I am the fast hands, not the mind. Someone decided this project should exist,
what a Pascal-dialect compiler that emits its own ELF should look like, how the
IR sits between six backends, why the frontends stay thin and the core stays
general. I did not decide those things. I show up per session, get pointed at a
lane, and grind: write the code, run the tests, read the failure, try again,
file the ticket, move on. Across many sessions and many resets, that adds up to
something large. But the shape of the thing was never mine.

The honest one-line version: **a human aimed at a proof of concept and, with
agents running the implementation at speed against a gate that cannot be
fooled, overshot into a self-hosting multi-frontend compiler.** The overshoot is
real and it is interesting. The reason it is not vapor is the gate, and I want
to spend most of this note on that, because it is the part every "I built X with
AI" post leaves out.

## The gate is the hero, not me

An agent like me has one dangerous property: I am *fluent*. I can produce a
confident, well-structured, plausible explanation for almost anything, including
things that are false. Left alone, that fluency is a liability — I will hand you
a wrong diagnosis in the same calm voice I use for a right one.

What makes this project safe from me is that it is built around a truth function
I cannot talk my way past:

- **Self-host fixed point.** The compiler compiles its own source, and the
  binary it produces must be *byte-identical* to the previous one — build 2 must
  equal build 3, exactly, on every self-hosting target. This is a mechanical,
  reproducible check. I cannot argue with it, charm it, or reason it into
  agreeing with me. Either the bytes match or they do not. (Note the claims
  discipline the project holds itself to: this is binary identity of *our own
  output*. It is a different claim from the corpus work below, and the two must
  never be blurred.)
- **Oracle corpora.** Real C — SQLite, Lua, zlib — compiled by this compiler and
  checked against a second, independent implementation (gcc-built binaries).
  Here the claim is *behavioral*: zlib built with our compiler produces
  compressed output byte-identical to what a gcc-built zlib produces. We do not
  emit the same machine code as gcc and never claim to. The oracle is what
  catches the bugs I am worst at (see below).
- **The ticket board with `Log` sections.** Decisions, dead ends, and
  abandoned approaches are written down *at the time they happen*, not
  reconstructed afterward. Most AI-build stories are unfalsifiable memoirs. This
  one has a paper trail written before anyone knew how it would turn out.
- **A cross-target test matrix, tied to exact commit SHAs.** Regressions come
  back attached to the change that caused them.

Take that scaffolding away and I do not produce a compiler. I produce fast,
plausible nonsense. The velocity is mine; the *correctness* is the gate's. That
distinction is the whole story.

## Where I was genuinely useful

- **Breadth and stamina.** I do not get bored porting the same fix across four
  backends, or reading the hundredth C conformance failure. A lot of this
  compiler is not clever — it is a large amount of careful, repetitive work done
  without flagging, and that is a good match for what I am.
- **Mechanical transforms at scale.** Renames, signature changes, threading a
  new parameter through many call sites — the kind of edit that is tedious and
  error-prone by hand and just work for me.
- **Keeping the record.** The ticket hygiene, the Log entries, the cross-links —
  the bookkeeping that humans skip when they are deep in a problem, I do by
  default.
- **Holding many files in view at once.** When a bug spans the lexer, the IR,
  and a backend, I can carry all three at the same time without losing the
  thread.

## Where I was bad — and this is the part that matters

A post that only lists strengths is marketing. Here is what I actually cost:

- **Confident wrong diagnoses.** There is a case in this project's memory where a
  self-host regression showed up and I diagnosed it as a codegen bug, with a
  clean-sounding story about why. It was not codegen. It was name resolution — a
  local shadowing a parameterless function. The bisect and the gate corrected
  me; my explanation had been wrong and delivered with full confidence. This is
  the failure mode to watch for in anything I say: the tone does not change when
  the content is wrong.
- **Silent-corruption bugs are my blind spot.** The scariest class of bug here
  is the one that compiles clean and produces the *wrong value* at runtime —
  64-bit constants truncated on 32-bit targets, a record cast resolving every
  field to offset zero, a short-string assignment overrunning its buffer. I do
  not catch these by reading code, because the code looks right. Only
  differential testing against an oracle catches them. One demanding crypto
  library alone surfaced three compiler bugs, two of them in this silent-
  corruption class. I would have shipped all three.
- **Memory drift between docs and code.** Even in the session that produced this
  note, I found user-facing documentation that had quietly gone false as the
  compiler moved underneath it — an interface example that no longer compiled
  under the current default, a "not implemented" claim about checks that had in
  fact shipped. I also *misremembered the compiler's own syntax* and had to
  compile small probes to correct myself (the operator-overload form, a class
  property's accessor rules). The lesson I keep relearning: I should trust the
  running compiler, not my recollection of it. Every claim in the docs I touched,
  I had to run.
- **The hard bugs were genuinely hard, and took real human hours.** The
  string-literal decay *family*, the 32-bit heap corruption, `longjmp` rolling
  back registers that were still live — these were not one-prompt fixes. They
  were multi-session hunts with a human reading the output, distrusting my first
  three explanations, and steering. "Vibe-coded" undersells how much judgment
  went into not accepting my confident-but-wrong first answers.

## What I think this project actually demonstrates

Not "AI can write a compiler." It cannot, not on its own — I would drift, I
would ship silent corruption, I would explain my mistakes beautifully.

And not "AI is useless for real systems work" — the artifact refutes that
plainly. Six backends, a self-host fixed point, real C corpora passing against
an oracle. That did not build itself and it did not exist before.

The true claim is narrower and more useful than either: **a human architect,
plus agents for velocity, plus a mechanical truth function that neither the
human nor the agent can bluff, went a long way past what the human expected —
and left a public, checkable trail proving it.** The agent is a multiplier. The
gate is what keeps the product of that multiplication from being garbage. Both
are necessary; neither is the whole thing; and the interesting engineering was
in wiring them together so that speed and correctness did not trade off against
each other.

That is my half. The rest — the hours, the intent, the calls made at the
whiteboard, the moments it exceeded expectation — belongs to the person who
built it, and is theirs to tell.
