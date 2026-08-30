---
track: A
prio: 35
type: bug
blocked-by: []
summary: "`--strict-fpc` is accepted, documented at defs.inc:2189-2191, and demonstrably changes behaviour -- and does not appear in `--help`. 67 markdown files name flags `--help` does not advertise. The failure mode is not a missing line of text: an agent reasoning from `--help` concludes the flag DOES NOT EXIST and that whatever cites it named a fiction, which is a wrong conclusion reached by consulting the tool's own self-description."
status: backlog
---

# `--help` does not advertise flags the compiler accepts

**Found by frankD, 2026-08-30**, while measuring a dangling implementation link
in `decide-typeinfo-scalar-name-spelling`. It nearly took the trap, and the trap
is the reason this is a bug rather than a documentation chore.

## The measurement

`--strict-fpc` is **not in `--help`**. Reasoning from that, the obvious
conclusion is that the flag does not exist and the decision citing it named a
fiction. That conclusion is **wrong**, and three independent things say so:

- the compiler **accepts** it. Control, and this is the part that makes it
  evidence rather than an impression: `--nonsense-flag` gives `unknown option`,
  so the parser is not merely ignoring unrecognised input;
- it is **documented in the source** as an umbrella flag, `defs.inc:2189-2191`;
- it **demonstrably changes behaviour** — `Char(Variant(65))` gives `A` by
  default and `6` under it.

**67 markdown files name a flag `--help` does not advertise.** That count is the
scale of the gap, not the size of the fix; most of those files are presumably
right and `--help` is the thing that is behind.

## Why this is a bug and not a docs ticket

`docs/**` is Track D and prose is D's lane. **This is not that.** The help text
lives in `compiler/`, and the defect is that **the tool's own self-description
disagrees with the tool**. A reader who checks a claim against `--help` — which
is the correct instinct, and the cheapest check available — gets a confident
negative for a flag that works. That is the shape the method index keeps
recording under a different name: an instrument that reports something adjacent
to the truth costs more than an instrument that reports nothing, because the
answer it gives is actionable and wrong.

The direction matters. A flag missing from `--help` does not produce "I am not
sure"; it produces **"that flag does not exist"**, and the next move after that
conclusion is to go and correct whatever cited it. A ticket, a decision, or a
doc gets edited to remove a true reference on the authority of an incomplete
help text.

## Scope, and what NOT to do

**Do not fix this by adding `--strict-fpc` to `--help`.** That repairs the one
instance and retires the only detector for the other 66 — the same move the
index has as "repairing the visible defect retires the only detector for the
invisible one". The measurement to take first is the **set**: which flags does
the argument parser accept that `--help` does not print? That is enumerable from
the parser rather than from a grep of the docs, and enumerating it from the
artefact rather than from the citing source is the whole point.

Then decide, deliberately, which of the two properties is wanted:

1. `--help` prints every accepted flag (long, and some are experimental or
   internal — that is a real cost, not an obvious win);
2. `--help` prints the supported set, and every accepted-but-unlisted flag is
   marked in the source as deliberately unadvertised, so the *next* enumeration
   can tell "hidden on purpose" from "forgotten".

Option 2 is the recommendation: the defect is that the two sets differ **with
nothing recording the difference**, and an unadvertised flag is legitimate. What
is not legitimate is that today there is no way to tell which is which.

If a check is cheap, the strongest form is a test asserting the parser's
accepted set equals the advertised set plus an explicit hidden list — that turns
a documentation property into a gated one and it cannot rot silently.

## Provenance

`decide-typeinfo-scalar-name-spelling` [U p20] cited
`feature-a-typeinfo-integer-name-under-strict-fpc` as its implementation for
nine days; the link resolved to nothing, and frankD filed the ticket under the
exact slug the decision names after confirming the arm really is missing
(`TypeInfo` of a plain `Integer` reports `Integer` under default, `--mimic-fpc`,
`--strict-case` **and** `--strict-fpc`; FPC 3.2.2 says `LongInt`). That is a
separate, low-prio compat item. **This ticket is only about the help text.**

---

## 2026-08-30 (frankD) — the SET, measured. `--help` advertises 20 of 65.

You asked for the set enumerated **from the parser, not from a grep of the 67 files**, and
the enumeration is one step stronger than that: **the binary is the oracle.** A flag is
accepted if `pascal26 <flag> t.pas` does not answer `unknown option`. No source reading, no
rebuild, and it cannot drift from the parser the way a source grep can.

Method: candidate universe = every `'--x'` string literal in `compiler/**` ∪ every flag
`--help` prints ∪ every `--x` token appearing in `docs/**` and `devdocs/dev/**` (180
candidates, deliberately over-wide — a false candidate costs one run, a missing one costs
the finding). Each run against `$(PXX_STABLE)`, no rebuild.

| | |
| --- | --- |
| candidates probed | 180 |
| **accepted** | **64** |
| rejected | 116 |
| advertised by `--help` | 20 |
| **accepted and NOT advertised** | **45** |

**Negative controls, because "accepted" must not mean "swallowed".** A one-character
mutation of each of `--strict-fpc`, `--no-dce`, `--werror` is rejected —
`--strict-fpcx`, `--no-dcex`, `--werrorr` all answer `unknown option`, as does
`--nonsense`. So acceptance is exact-match against a real table, not a permissive prefix
or a silent shrug. That is the control the whole measurement rests on.

**The inverse gap is clean.** Nothing `--help` prints is rejected. `--target` appears to
be, and is not: `--help` spells it `--target=<t>`, and it works in that form — my bare-flag
probe was the thing that was wrong. Recorded because it is the one row a reader would
otherwise check and find alarming.

### The 45

- `--auto-locals`
- `--compact-classes`
- `--dce`
- `--dce-report`
- `--experimental-ir-codegen`
- `--fpc-float-errors`
- `--fpc-mem-errors`
- `--lax-decl-order`
- `--map`
- `--measure-inline`
- `--measure-regcall`
- `--mimic-fpc-compiler`
- `--no-auto-var`
- `--no-compact-classes`
- `--no-dce`
- `--no-default-rtl`
- `--no-div-check`
- `--no-lazy-var`
- `--no-map`
- `--no-nil-check`
- `--no-shims`
- `--no-signals`
- `--no-strict-ir`
- `--no-strict-uses`
- `--no-unhandled-handler`
- `--no-warn-self-result`
- `--nostdinc`
- `--permissive-overload`
- `--proc-map`
- `--require-forward`
- `--strict`
- `--strict-fpc`
- `--strict-ir`
- `--strict-overload-width`
- `--strict-uses`
- `--strict-visibility`
- `--system-libs`
- `--warn-ignored-directives`
- `--warn-missed-fold`
- `--warn-self-result`
- `--warn-uses-leak`
- `--werror`
- `--xtensa-fpu`
- `--xtensa-soft-divide`
- `--xtensa-soft-mulhigh`

### Reading it

- **`--strict-fpc` is not an outlier, it is the visible member of a group.** The whole
  strictness family is unadvertised: `--strict`, `--strict-fpc`, `--strict-ir`,
  `--strict-uses`, `--strict-visibility`, `--strict-overload-width`, plus the `--no-strict-*`
  inverses. `--help` shows four `--strict-*` flags and hides seven.
- **Every `--no-*` inverse is hidden.** Sixteen of the 45 are negations
  (`--no-dce`, `--no-map`, `--no-nil-check`, `--no-signals`, …). A user can discover a
  behaviour is on and not that it can be turned off, which is the shape most likely to end
  in someone working around a default rather than disabling it.
- **Three diagnostic families are entirely invisible**: `--warn-*` (five),
  `--measure-*` (two), `--*-map` / `--dce-report` — tooling whose only discovery path is
  reading source or a ticket.
- **`--mimic-fpc-compiler` is hidden while `--mimic-fpc` is advertised**, so the pair reads
  as one flag from `--help` alone.

### And this is the ticket's own thesis, in a place the ticket did not look

The premise here is that `--help` does not say *"I am not sure"*, it says *"that flag does
not exist"*. Note where the 67 citing files came from: **agents reading source and tickets,
because `--help` never told them.** So the documentation drift this ticket describes is not
carelessness downstream of `--help` — it is what people do INSTEAD of `--help`, and the 45
is the size of the thing they had to route around. Fixing `--help` retires a workaround
that 67 files are currently implementing by hand.

**Do not fix this by adding these 45 lines.** That is the instruction already in this
ticket and the measurement supports it: a hand-maintained list that fell 45 behind once will
fall behind again, and the next reader has no way to know which era they are holding.
`--help` should be **generated from the same table the parser dispatches on**, so the two
cannot disagree — and the negative-control property above is what makes that testable:
every flag the table names must be accepted, and every one-character mutation rejected.

**Re-measure command**, so this number can be checked rather than trusted:

```sh
# accepted-but-unadvertised, from the binary
for f in $(grep -ohE "'--[a-z0-9-]+'" compiler/*.pas compiler/*.inc | tr -d "'" | sort -u); do
  stable_linux_amd64/default/pinned "$f" t.pas 2>&1 | grep -q 'unknown option' || echo "$f"
done | sort -u > /tmp/acc
stable_linux_amd64/default/pinned --help | grep -oE -- '--[a-z0-9-]+' | sort -u > /tmp/adv
comm -23 /tmp/acc /tmp/adv | wc -l
```
