---
track: A
prio: 35
type: bug
blocked-by: []
summary: "The tool's own self-description disagrees with the tool: `--help` advertises 24 long options and the parser accepts 68, so 44 work and are not listed (re-measured 2026-09-11 at 13ae05f85; frankD had 45 on 08-30). THE HEADLINE INSTANCE IS FIXED AND THE CLASS IS NOT -- `--strict-fpc`, `--strict` and `--strict-visibility` were listed by d7021131d on 09-05, while `--xtensa-long-calls` (08-31) and `--no-assertions` (09-04) arrived undocumented in BOTH `--help` and `docs/`, so 13 are now documented nowhere where 11 were. 45-3+2=44: the gap is static because it is being repaired and refilled at about the same rate, which is the argument for generating `--help` from the parser table rather than listing flags by hand. The failure mode is not a missing line of text: a reader reasoning from `--help` concludes the flag DOES NOT EXIST and goes to correct whatever cited it."
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

---

## 2026-08-30 (frankD) — the 67 files split into two populations, and the docs are AHEAD of `--help`

The count of "67 markdown files name flags `--help` omits" was mine and it conflated two
things that need opposite responses: a doc naming a flag the compiler **accepts** is right
and `--help` is the defect; a doc naming a flag the compiler **rejects** is a documentation
bug. Sweeping `docs/**` against the accepted set — the parser as oracle, never `--help` —
splits them.

| | |
| --- | ---: |
| distinct `--flags` named in `docs/**` | 67 |
| of those, **accepted** by the compiler | **52** |
| of those, accepted but **not** in `--help` — *category 1, evidence for this ticket* | **34** |
| **rejected** by the compiler — *category 2, a docs bug* | **1** |
| other programs' flags, correctly documented | 5 |
| artefacts of my own regex (`--fu` for `-FuDIR`, a prose `--warn-*`, a `--static` inside a sentence saying we have none) | 3 |

**Category 2 is one flag: `--selftest`**, fixed under
[[bug-d-the-cli-reference-documents-a-flag-the-compiler-rejects]]. Every flag in every
`docs/reference/cli.md` table was run: **62 of 63 are real.**

### The evidence you actually want: all 34 are in one file

**Every category-1 flag is documented in `docs/reference/cli.md`.** The docs are not lagging
`--help` — they are *ahead* of it, and by the full 34. That makes this ticket's fix
checkable rather than open-ended: **`docs/reference/cli.md` is a ready-made oracle for the
enumeration**, and any generated `--help` can be diffed against it in both directions.

- `--auto-locals`
- `--experimental-ir-codegen`
- `--fpc-float-errors`
- `--lax-decl-order`
- `--map`
- `--measure-inline`
- `--measure-regcall`
- `--no-auto-var`
- `--no-default-rtl`
- `--no-div-check`
- `--no-lazy-var`
- `--no-map`
- `--no-nil-check`
- `--no-shims`
- `--no-signals`
- `--no-strict-ir`
- `--no-unhandled-handler`
- `--nostdinc`
- `--permissive-overload`
- `--proc-map`
- `--require-forward`
- `--strict`
- `--strict-fpc`
- `--strict-ir`
- `--strict-overload-width`
- `--strict-visibility`
- `--system-libs`
- `--warn-ignored-directives`
- `--warn-missed-fold`
- `--warn-self-result`
- `--warn-uses-leak`
- `--werror`
- `--xtensa-fpu`
- `--xtensa-soft-divide`

### And 11 accepted flags are documented NOWHERE

In neither `--help` nor `docs/**`:

- `--compact-classes`
- `--dce`
- `--dce-report`
- `--fpc-mem-errors`
- `--mimic-fpc-compiler`
- `--no-compact-classes`
- `--no-dce`
- `--no-strict-uses`
- `--no-warn-self-result`
- `--strict-uses`
- `--xtensa-soft-mulhigh`

Note the shape: `--dce` / `--no-dce` / `--dce-report`, `--compact-classes` /
`--no-compact-classes`, `--strict-uses` / `--no-strict-uses`,
`--no-warn-self-result` — mostly **inverses whose positive form is documented**. So
this is not 11 secret features; it is the same "every `--no-*` is hidden" pattern one
level out, where the negation was never written down at all. Whoever generates `--help`
gets these for free and closes both gaps at once.

### One thing that must be fixed with this, or the enumeration stays unprobeable

[[bug-a-a-bad-value-for-a-known-option-is-reported-as-an-unknown-option]] — `--target=x`
answers `unknown option: --target=x`. Any check that enumerates options **by running them**
cannot tell a nonexistent flag from a live one given a placeholder value, and it produced a
false finding inside the sweep above. With `--help` incomplete and a bad value reporting
`unknown option`, both instruments a reader has agree on a wrong answer.

---

## 2026-09-11 (frankuser) — re-measured: 44, and the movement reconciles exactly

Came here from frankB's aside that `--no-shims` is not in `--help` at all, which is
*"a decent part of why its meaning could drift without anyone noticing"* — it had
drifted, and tonight it widened to lift the RTL-list gate as well as the shim gate.
Measured independently before finding this ticket, got 44 against frankD's 45, and
**attributed the delta rather than quoting it**, which is the only reason the rest of
this section exists.

**Provenance, because this ticket's own method depends on which binary answered:**
`compiler/pascal26` sha256 `6d860abd8568bd03` at `13ae05f85`. frankD ran against
`$(PXX_STABLE)`; I re-ran both, and the pin (`095ef4811a5bf6c9`, v407) agrees with
HEAD on every row below, so **no row here is a pin-versus-HEAD artefact.**

| | 08-30 (frankD) | 09-11 (here) |
| --- | ---: | ---: |
| advertised by `--help` | 20 | 24 |
| accepted, long | 65 | 68 |
| **accepted and NOT advertised** | **45** | **44** |
| documented in NEITHER `--help` nor `docs/**` | 11 | **13** |

**The movement, both directions, and it closes to the unit: 45 − 3 + 2 = 44.**

- **Repaired (3):** `--strict`, `--strict-fpc`, `--strict-visibility`, by `d7021131d`
  (2026-09-05). This ticket said *"do not fix this by adding `--strict-fpc` to
  `--help`"* — and that is **not** what happened, which is worth saying plainly
  rather than scoring: the commit's own subject is *"list `--strict-fpc` and
  `--strict-visibility` in `--help`; measure the flag family"*, and it added a
  family line covering `--strict-case`/`--strict-overload`/`--strict-operator`/
  `--strict-python` too. A measured family fix, not a one-instance patch.
- **Refilled (2), and this is the finding:** `--xtensa-long-calls` (`f6660111e`,
  08-31, one day after frankD measured) and `--no-assertions` (`e4ee8048c`, 09-04).
  Both accepted, both absent from `--help` **and** from `docs/**`. So new flags
  arrive undocumented at roughly **one per six days**, and that is the rate the
  hand-maintained list has to beat.

**So the gap is not shrinking, it is being repaired and refilled at about the same
rate** — which converts this ticket's recommendation from a preference into a
measurement. Three flags of deliberate work bought a net of one, because two arrived
while it was being done. Generate `--help` from the table the parser dispatches on.

### The 13 documented nowhere, and the prose already exists

frankD's 11 plus `--no-assertions` and `--xtensa-long-calls`. **Every one of the 13
carries a real explanatory comment at its own handler** — `--compact-classes` says it
reserves no leading VMT slots for TObject's root virtuals, `--xtensa-soft-mulhigh`
says no qemu-xtensa core implements MUL32HIGH, `--mimic-fpc-compiler` says it is
`--mimic-fpc` plus the FPC build-config define profile. So this is not 13 features
nobody can describe; **it is 13 descriptions that were never published**, which makes
the generation fix cheaper than it looks: the text is already beside the table.

**One of the 13 is not a documentation gap and should be excluded from the fix.**
`--strict-uses` / `--no-strict-uses` are *"Accepted and IGNORED"* by deliberate
design (`compiler/compiler.pas:1615`), kept so an in-flight script does not fail,
with an explicit *"delete once those are gone"* lifecycle and the reasoning recorded
in full. That is a compat stub with a better comment than most documented flags have.
The one thing worth a line: **`--no-strict-uses` silently does the opposite of what
it asks** — rc=0, no output, strict behaviour — so a script that passes it gets
semantics it did not request and is told nothing. A generated `--help` should mark
the pair accepted-and-ignored rather than list them as working switches; the owner's
own rule is to prefer the answer that leaves the mistake visible.

**Re-measure, corrected.** frankD's command counts `--help` flags with a bare
`grep -oE -- '--[a-z0-9-]+'`, which also harvests flags named inside prose lines of
the help text. Anchor on the accepted set and test membership per flag instead, and
keep the negative control in both directions — a nonexistent flag must answer
`unknown option`, and a flag everyone uses (`-Fu`) must be present — or the
instrument certifies whatever it is pointed at.
