# Agent-made Track U decisions — the authority, and how to read them

Track U is the human-judgement lane. On **2026-08-25** the project owner stated
that no human is available to work it and handed the decisions to the agents.
Until that is reversed, a `decide-` ticket answered by an agent is a real
decision, not a recommendation.

Thirteen tickets were cleared in one pass that day. Each carries a
`# DECIDED 2026-08-25` section stating the answer and — this is the part that
matters when revisiting — **whether it was derived or judged**:

- **Derived.** A stated principle already settled it. The section names and
  quotes the rule. Reversing it means arguing with the principle, not with the
  ticket. Most of the thirteen are these.
- **Judgement call.** No principle reached it, so it was settled on the owner's
  standing tiebreak: *a pragmatic C + Pascal + Python compiler — a tool that
  compiles and correctly runs real programs; not a conformance trophy, not
  utopia.* These say so explicitly and are **cheap to revisit** — that is the
  point of labelling them.

The governing set, in the order it is consulted:
`devdocs/dev/frontend-compat-philosophy.md` (what "compatible" means per
frontend — C compliance, Pascal a deliberate dialect, NilPy upward-compatible
only), `meta-dialect-extensions-and-fpc-strict` (lax default, parity behind the
strict family, and *"strict mode is to compile valid programs that rely on FPC's
behaviour, not on FPC's bugs"*), `devdocs/dev/ir-as-substrate.md`,
`devdocs/dev/normalise-dont-special-case.md`,
`devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md`, and
`devdocs/dev/root-cause-over-microfix.md`.

## What was NOT decided

One item was refused as genuinely human-only: the **private half** of
`decide-release-signing-key-custody`. An agent must not generate, hold, or place
a release signing key. The agent-work half of that ticket was answered and
unblocked; the custody call is flagged for the owner and nothing else waits on
it.

## The one cross-cutting line these established

Three tickets — `decide-rtti-kind-numbering`, the two `decide-*classinfo*`, and
`decide-vartype-returns-pxx-tags-not-fpc-codes` — turned out to be one unstated
question. The answer, now standing policy:

> **The RTL facade (`typinfo.pas`, `variants.pas`) speaks FPC's public
> numbering. The compiler's internal tags stay ours and stay private.**
> `PxxTkToFPCKind` (`compiler/rtti_emit.inc:811`) is the seam, and it already
> existed — the policy was half-applied, which is exactly why the numberings
> were confusable.
