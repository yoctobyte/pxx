---
slug: feature-bare-esp-supports-uses-builtin
track: A+S
prio: 20
type: feature
status: open
owner: ""
found: 2026-08-30
found-by: claude-A
blocked-by: []
summary: "MECHANISM, AND IT IS WHY THIS IS A FEATURE AND NOT A BUG: on the bare ESP profile `builtin` is withheld by design (`(not TargetIsEspClass)` on 22 arms of `needsBuiltin`), and making it compile is not a repair with an endpoint -- each guard you add exposes the next, and THE FAILURE CLASS CHANGES after the first step, from undefined-declaration to link-failure on float kernels. That is what makes the job unsizable from the outside: a static census of declarations answers confidently about the first class and is SILENT about the second, so do not build one and quote it. Every step is a design call about what a size-constrained profile offers. PRIO 20 BECAUSE THE RANKING TEST IS `root-cause-over-microfix`'s tickets-closed-per-change AND THE ONE NAMED CONSUMER HAS ANOTHER ROUTE: a bare NilPy program stops at step 0 because NilPy's runtime is built on `builtin`, but the SAME program runs today on the IDF profile (`examples/esp32/nilpy-c3`), so this is the bare route to Python-on-ESP and not the only one -- which is why it is deliberately NOT wired as a blocker of the NilPy cross-target walls. RAISE IT if a consumer appears with no IDF route. WHAT A SEAT ARRIVING HERE SHOULD KNOW BEFORE ANYTHING ELSE (2026-09-24): the gap a bare program actually MEETS is not this cascade, it is `Str` -- the language statement, no `uses` clause involved -- refused for integer AND float on all four ESP targets by two purpose-built diagnostics in `pasparser_stmt.inc`. Its sibling `WriteLn` warns-and-compiles instead, and THAT ASYMMETRY IS CORRECT, not a normalise-don't-special-case defect: `WriteLn` has no result so dropping it loses nothing observable, while `Str` YIELDS A VALUE the program ships or compares, so warn-and-drop there would be a silent wrong answer. The bounded job in the area is therefore the DIAGNOSTIC (both `Str` errors name an internal routine and offer no remedy, where the `WriteLn` warning names the profile and points at the docs) plus `docs/targets/esp32.md`, which documents the console no-op and is silent about `Str`. COSTS, esp32c3, marginal `code=` bytes over an AnsiString baseline, so a later re-run can tell a regression from a different denominator: Str(integer) +23,724, Variants +35,652, Str(double) +89,116 -- float formatting is the MOST expensive group, which inverts the ordering this ticket's own earlier `writeln`-is-a-no-op argument implied. TWO INSTRUMENT TRAPS measured here: `procs` is not a cost (bare WriteLn(d) is procs=121, code=368B -- pre- vs post-DCE), and differences of `codeseg` come out as exact multiples of 4096 because it carries segment padding, so quote `code=`. WHAT WOULD RETIRE THIS: a bare NilPy program building AND RUNNING on a device, since on this profile `ok:` from the compiler is not a result -- espassert.pas's own lesson."
---

# Make `uses builtin;` compile on a bare ESP boot

Today it does not, and that is the **documented, intended** state:
`(not TargetIsEspClass)` on 22 arms of `needsBuiltin` is the honest constraint,
and [[bug-a-builtin-pas-calls-a-declaration-that-esp-compiles-out]] closed as
working-as-intended on that basis. This ticket exists so the *option* survives
that closure instead of being lost with it.

## Why it is a feature and not a bug fix

Making it compile is not a repair with a known endpoint. It is an **open-ended
sequence of judgement calls about what the bare profile offers**, measured four
steps deep and still going:

```
step 0   undefined PXXVarBinOp (1148), undefined PxxSciDigits17 (1702)
step 1   guard those two      -> __pxx_d2i_rne not linked   (1235, VariantToDouble)
step 2   guard the Variant* group -> __pxx_dcmp not linked  (1586)
step 3   ...
```

Identical on bare riscv32, line for line — a **profile** property, not an ISA
one. Each guard exposes the next, and each step decides whether a feature
(variant arithmetic, float formatting, float comparison) belongs on a target
whose whole campaign is size. That is design work, and it is why this cannot
ride a bug ticket.

## What is already known, so nobody re-derives it

- `PXX_ESP` is **not** a compiler symbol; `PXX_ESP_BARE` is. `builtinheap.pas:18`
  converts one to the other *for that unit only*. Any new guard in another unit
  must define it itself or use `PXX_ESP_BARE` directly.
- `builtin.pas`'s three inert `{$ifndef PXX_ESP}` regions were **deleted** in
  `fccdc4671`, so there is no half-working scaffolding left to build on.
- The `uses softfloat` remedy the kernel diagnostic advises **does not work** —
  [[bug-a-the-no-fpu-diagnostic-advises-uses-softfloat-which-does-not-help]].
  Resolving that is probably a prerequisite, since several steps end in a kernel
  refusal rather than a missing declaration.
- Probing method that costs nothing: copy `compiler/builtin` and the `pascal26`
  binary into a scratch directory and iterate there. The compiler resolves its
  builtin tree relative to **the binary's own directory**, not the cwd, so this
  needs no pin and no repo edit.

## The measure to apply

`root-cause-over-microfix` says count tickets closed per change. Nobody has yet
named a program that wants `uses builtin;` on a bare boot. **Rank it against
that**, not against how close it looks.

## 2026-09-19 (frankS): a named program now wants it

The ranking test above asked for one. A NilPy program on a bare ESP boot
(`--esp-profile=bare`, either ISA) stops at step 0 here, `undefined variable
(PXXVarBinOp)`, because NilPy's runtime is built on `builtin`. The IDF profile
does NOT need this: the same program now runs on an ESP32-C3 under IDF
(`examples/esp32/nilpy-c3`). So this is the bare route of "a static Python
application on an ESP", not the only route. That is why it is not wired as a
blocker of `bug-a-nilpy-on-cross-targets-four-remaining-walls`. Rank it
knowing that.


## 2026-09-24 (frank, frankb-8e) — re-measured at HEAD, and the mechanism named exactly

The chain data above is from 2026-08-30 and its LINE NUMBERS have moved
(`PXXVarBinOp` is now `builtin.pas:1355`, was 1148). The behaviour has not. What
follows is measured at HEAD, riscv32 and xtensa, in a scratch probe.

**Still step 0, still identical on both ISAs, line for line** — so the ticket's
"profile property, not an ISA one" claim holds unchanged:

```
pascal26:1355: error: undefined variable (PXXVarBinOp)
  in: ./compiler/builtin/builtin.pas
```

**THE PROBING METHOD ABOVE IS CORRECT, AND CLAUDE.md APPEARS TO CONTRADICT IT
WITHOUT DOING SO** — worth stating because a seat that reads both will stop.
CLAUDE.md warns that a relocated binary finds no builtin beside itself and falls
through to a CWD-relative last resort, which silently picks up a sibling
checkout. Both are true about different layouts: `--where` at the repo root
reports the builtin root as `<exedir>/builtin/`, so a scratch dir works **only
if `builtin` is copied next to the binary**, which is exactly what this ticket
says to do. Mirror the repo — `pr/compiler/{pascal26,builtin}` plus `pr/lib` —
and `--where` shows every root resolving. Check `--where` rather than assuming;
with `lib` merely symlinked, the RTL roots print `[MISSING]` and the failure
looks like a compiler bug.

**And a symlinked `lib` is a live hazard in that probe**: edits through it land
in the repo. Guard edits belong in the `builtin` COPY.

## Why pulling the unit explicitly does not help, which nobody had recorded

The obvious first move is `uses builtinheap, builtin;`. **Measured: identical
error.** `PXXVarBinOp` and `PxxSciDigits17` are declared inside
`{$ifndef PXX_ESP}` in `builtinheap.pas` (around :583 and :597), and
`builtinheap.pas` opens with `{$ifdef PXX_ESP_BARE}{$define PXX_ESP}{$endif}`.
So on bare the declarations are **not in the unit at all** — this is not a link
or search-path problem and no `uses`, `-Fu` or unit ordering can reach it. The
`espassert.pas` header already records the same two names as the reason that unit
exists separately; this is that note's mechanism.

## The surface the cascade would have to cover, sized

The ticket calls the cascade open-ended, and it is, but the SIZE is measurable
and had not been measured:

- `builtin.pas` is **2863 lines, 251 top-level routines**.
- **12 are the Variant group**, and they sit in two near-contiguous regions —
  declarations `:143`–`:175`, bodies `:1131`–`~:1500` — not scattered.
- Float formatting (`FloatToStr`, `StrFloat`, the `PxxSciDigits17` caller near
  `:2029`) is the second group.

So it is roughly **two features, not two hundred call sites**, which is a
friendlier shape than "four steps deep and still going" suggests.

**But the cascade CHANGES CLASS after step 0, and that is why a declaration
census cannot size it.** Steps 1 and 2 above end in `__pxx_d2i_rne not linked`
and `__pxx_dcmp not linked` — LINK failures from float kernels, not undefined
declarations. A static intersection of "what builtinheap excludes" against "what
builtin.pas references" would answer confidently about the declaration class and
be silent about the link class, which is the shape CLAUDE.md warns about: a
census that cannot contain its subject. Do not build one and quote it.

## A principle that would make the remaining judgement calls mechanical

The ticket's real cost is that each step is an independent decision. One rule
collapses most of them, and the evidence for it is already in the tree:

> **On the bare profile, `builtin` offers no Variant support and no float
> FORMATTING.**

Float formatting first, because that argument is the strong one and it is
documented rather than aesthetic: **`writeln` is a no-op on bare** —
`docs/targets/esp32.md:70` says so, `espassert.pas` hand-rolls a UART write for
exactly that reason, and a draft of that unit *compiled and printed nothing*.
A profile with no console cannot be paying for 17-significant-digit decimal
conversion; that is dead weight by construction, not a trade-off. Variant
arithmetic on a flash-constrained part follows the same way.

Adopting that rule turns the cascade from "decide again at each step" into
"guard the two groups and keep going until it links", which is a bounded job with
a stated endpoint.

**NOT DONE HERE, and deliberately.** It is still a behaviour change to a unit
every program gets, the endpoint is unproven until something links, and the rule
above is a proposal with a name on it rather than a settled position — the sort
of thing that should be agreed before a seat spends an evening on it. What is
banked is the mechanism, the sizing, the corrected probing note, and the
principle.

**What would retire this ticket** is unchanged, plus one addition: a bare NilPy
program building AND running on a device, since on this profile `ok:` from the
compiler is not a result — that is `espassert.pas`'s own lesson and it applies
to every claim made here.

## 2026-09-24, later (frank, frankb-8e) — THE GAP IS `Str`, NOT "FLOAT FORMATTING", AND THE SECTION ABOVE MIS-ATTRIBUTED ITS OWN COST FIGURE

Measured at `c4d759f5c5`, clean tree, `compiler/pascal26` = `bb681c88af9f`
(`rounds 1`, srccount 234). Population: **seven single-statement programs** I
wrote for this, listed in the table. Oracle: none — these are size figures read
off the compiler's own `ok:` summary line, not a differential.

### What is actually refused on bare, and it is wider than this ticket said

`Str` — the **language statement**, no `uses` clause anywhere near it — is
refused on the bare profile for **both** integer and float, on **all four** ESP
targets (esp32c3, riscv32, esp32s3, xtensa), with two purpose-built
diagnostics:

```
pascal26:1: error: Str: StrInt not loaded      (pasparser_stmt.inc:4152)
pascal26:1: error: Str: StrFloat not loaded    (pasparser_stmt.inc:4136)
```

So this is not a `uses builtin` question and not a *float* question. The
compiler already knows the exact routine it wants and names it.

**AND THE SIBLING SPELLING DIVERGES.** `WriteLn(d)` on bare **warns by name and
compiles** — *"write/writeln emits nothing on the bare ESP profile: there is no
console"* — while `Str(d, s)` **errors**. Two spellings of one concept, render a
number as text, opposite outcomes on the same profile.

This reads as `normalise-dont-special-case.md`'s sibling rule — the second path
being the one that stayed broken — and **it is not; see the closing section.**
Flagged here rather than silently omitted because that is the reading a seat
will arrive at, and it is the reading I arrived at and had to back out: the two
statements differ in whether they produce a **value**, so the divergence is
correct and normalising it would ship a silent wrong answer.

### The principle above is refuted by its own scope, by me, the author

The section above argues float formatting should go first because the argument
is *"documented rather than aesthetic: `writeln` is a no-op on bare"*.

**That argument is about the CONSOLE and `Str` does not use one.** `Str` renders
into an `AnsiString` the program then ships over its own UART — which is
precisely what `espassert.pas` hand-rolls and what `docs/targets/esp32.md`
tells a bare program to do. So a bare program has a **live** reason to want
`Str` and no reason at all to want `writeln`. The argument I called the strong
one is the weak one here, and it points the wrong way.

### Cost, corrected — the ~88 KB is FLOAT FORMATTING, not Variants

esp32c3, `code=` bytes (see the caveat below on why not `codeseg=`):

| program | IDF | bare | marginal over `ansistr`, IDF |
| --- | --- | --- | --- |
| `base` | 636 | 144 | — |
| `ansistr` | 33,948 | 3,768 | baseline |
| `wr_int` | 35,872 | 44 | +1,924 |
| `wr_flt` | 66,756 | 368 | +32,808 |
| `str_int` | 57,672 | **REFUSED** | +23,724 |
| `variant` | 69,600 | **REFUSED** | +35,652 |
| `str_flt` | 123,064 | **REFUSED** | +89,116 |

**The earlier pricing in this ticket's other section is superseded and the
reason matters.** An `sz_var` / `sz_str` pair gave "Variants cost ~88 KB
marginal over the string machinery" — the *quantity* was real and the
*attribution* was invented, because that pair never isolated: both programs
pulled unit `builtin`, visible as an identical `procs=620`. The 88 KB belongs to
**`Str(double)`**. Variants are +35,652. So float formatting is the **most**
expensive of the three groups, inverting the ordering the proposal implied.
Carrying both rows rather than replacing one: the old row measured two programs
that differed in more than one feature; this one varies one statement at a time.

### Two instrument caveats, both of which bit me here

- **`procs` is not a cost.** Bare `WriteLn(d)` reports `procs=121` and
  `code=368B`. `procs` counts before DCE and `code` after, so quoting `procs`
  as a size claim overstates by two orders of magnitude on this profile.
- **`codeseg` carries segment padding.** Differences of `codeseg` came out as
  exact multiples of 4096 (+24,576 / +36,864 / +90,112) — a round number is the
  tell, not a confirmation. `code=` gives +23,724 / +35,652 / +89,116. Quote
  `code=`.

### `StrFloat` and `FloatToStr` are not program-level surface on ANY target

Separate correction, to a note of mine earlier today that said `FloatToStr`
*"doesn't exist on the ESP surface at all"*. It does not exist at program level
on **x86-64 either** — `undefined variable (StrFloat)` at the same line, which
is the control that exculpates ESP. They are internals of unit `builtin` and
become visible only as a **side effect** of whatever else caused that unit to be
appended: a `Variant` in the program makes `StrFloat` resolve, an `AnsiString`
does not. So "is this name available" is not a property of the target or the
profile; it is a property of what else the program happens to mention.

### What this does to the two-group proposal

It supports guarding the groups **independently** rather than as one rule, and
there is a call-graph reason: `StrFloat`'s closure is string-and-float only —
`PxxSciDigits17`, `StrInt`, `FloatToStr`, `FloatToExpStr`, AnsiString concat —
with **no Variant in it**, and bare already carries AnsiString at 3,768 B. The
substrate the float half needs is present on the profile that refuses it.

**Still not implemented, still deliberately.** What changed is the framing and
the numbers, not the decision.

### THE SIBLING SYMMETRY IS THE WRONG FIX, AND I NEARLY RECOMMENDED IT

The obvious reading of the `WriteLn`-warns / `Str`-errors divergence above is
"make `Str` warn too". **That is wrong, and the asymmetry is correct.**
`WriteLn`'s no-op is defensible because it has **no result**: there is no
console, the statement's whole effect is absent, and dropping it loses nothing
the program can observe. `Str(x, s)` **yields a value the program then uses** —
ships over its own UART, compares, hashes. Warn-and-drop there produces an empty
or garbage string at runtime: a **silent wrong answer**, which is the failure
class this tree spends most of its effort on. So today's hard error is the right
behaviour and the divergence is not a defect to normalise away.

Three options, then, and only one of them is a no-op-shaped one:

- **(a) hard error — today.** Honest: the feature is absent, the program stops.
- **(b) warn and no-op.** Rejected above. Silent wrong answer.
- **(c) make it work** — pull `StrInt`/`StrFloat` onto bare's surface. Priced at
  **+23,724 B** (integer) and **+89,116 B** (float) on the IDF proxy.

### What IS bounded, and is not this cascade

The **diagnostic**. `Str: StrInt not loaded` is an internal-implementation
message reaching a user who wrote plain Pascal — it names a routine no program
mentions and gives no remedy, where the `WriteLn` warning beside it names the
profile, explains why, and points at `docs/targets/esp32.md`. Restating the two
`Str` errors in that register is a small, verifiable job with no design fork in
it, and `docs/targets/esp32.md` documents the console no-op while being silent
about `Str`. Neither needs the 2,863-line cascade this ticket is about.

## THE RANKING TEST IS MET FOR ONE SLICE, AND THE SLICE IS NOW ITS OWN TICKET

"The measure to apply" above asks for a named program that wants `builtin` on a
bare boot, and says to rank this against that. **There is one, and it is in-tree:
the RTL's own `Assert`.** `espassert.pas` hand-rolls a UART write so that a bare
assertion can be heard at all, and then the message can only contain string
literals -- `Assert(n > 99, 'count too low')` compiles and boots, while the same
assertion carrying the value that failed is refused, because the `Str(n, s)` that
would render it needs `StrInt` from the unit bare does not link.

That is a **bounded slice** and it is filed separately as
[[feature-a-non-float-str-on-the-bare-esp-profile]] (p40): the five non-float
`TextStrArg` arms are pure AnsiString-and-integer code, `espassert.pas` is the
precedent for the shape, and its own header already prescribes an include over a
copy for exactly the moment a second caller appears.

**It does not retire this ticket and it does not need it.** `Str` needs five
routines out of `builtin`; this ticket is about making the whole unit compile,
Variants included. Read the ranking test as satisfied **for the slice only** --
the cascade still has no named consumer, and the Variant half still has none at
all.
