---
slug: decide-old-style-object-types
track: U
prio: 30
status: decided
---

# Decide: do we implement Turbo Pascal `object` types?

`type TFoo = object ... end;` — the pre-Delphi class construct — is **entirely
unsupported**. Not partially: the parser stops at the first field.

```pascal
type TO1 = object x: Integer; procedure Set1(v: Integer); end;
```
```
pascal26:2: error: unexpected token — Expected: begin, but got: x
```

Every form fails the same way: plain, with `constructor Init`, with `virtual`
methods, with inheritance `object(TParent)`.

## Why it is being asked now

It is the single largest remaining cluster in the FPC conformance suite's skip
list. Three tests are skipped for it outright — `tobject2.pp`, `tsealed6.pp`,
`tprocvar1.pp` — and `tprocvar1` only surfaced today, after four *other* gaps it
was blamed on were each fixed and it still would not run.

## What it actually is — and why it is not "just a class"

An `object` is a **value type with a VMT**, and that combination is the whole
cost. It differs from `class` on every axis that matters to codegen:

| | `class` | `object` |
| --- | --- | --- |
| storage | heap, always | wherever declared — stack local, global, record field, array element |
| a variable holds | a reference | the instance itself |
| assignment | aliases | **copies**, bitwise |
| `SizeOf(T)` | pointer size | the instance's real size |
| lifetime | `Create`/`Free`, refcounted for interfaces | scope, like a record |
| `constructor Init` | returns an instance | initialises **in place**, returns nothing |
| VMT pointer | always present | present only if the type has a virtual method, and `Init` is what sets it |
| inheritance | reference-compatible | layout-prefix compatible; assigning a child to a parent **slices** |

So it is closer to "a record with a VMT and a hidden Self" than to a class, and
it lands in Track A's ground: layout, the VMT emit path, the constructor
protocol, and `SizeOf`. Reusing the `UCls` machinery would get the parsing and
method dispatch nearly free; the value semantics (copy on assign, slicing, no
allocation, in-place `Init`) are the part that has no existing analogue.

## The options

**A. Don't.** `object` is deprecated in FPC's own documentation and Delphi
dropped it. No code in this tree, in `lib/**`, or in any corpus we build uses
it. The three conformance tests stay skipped with an honest reason. Cost: zero.
Loss: three tests, and any old real-world Pascal that walks in the door.

**B. Implement it as a record-with-VMT.** Full semantics per the table above.
Unskips the three tests, and makes pre-Delphi source compile. This is a real
feature, not an afternoon: the value-semantics half touches assignment,
parameter passing, `SizeOf`, and the constructor protocol.

**C. Implement the non-virtual subset only** — `object` as "a record whose
methods may be declared inside it", no VMT, no `virtual`, no `constructor`.
Cheap, since `advancedrecords` already does exactly this and works. But it
accepts the keyword while silently refusing the half of the feature that
motivates it, and a program using `virtual` would then fail deeper in with a
worse message than today's clean one. **The bad middle** — this is the option to
avoid.

## Recommendation

**A for now, B when a real program asks for it.** The conformance tests are the
only caller, and "three FPC tests" is not a reason to add a second object model
to the language — that is conforming to FPC's history rather than to Pascal.
The moment actual source someone wants to build needs it, B, in full; the
per-feature strict-flag pattern does not apply here, since this is a missing
feature rather than a laxness.

Worth noting the asymmetry: this is the mirror of the `compat` tag's usual
direction. Most compat work is "behave exactly like the reference on something
we already do". This is "implement a thing the reference has and we don't",
which is a feature request wearing a compat hat, and should be ranked as one.

## If the answer is B

It is a Track A feature (layout / VMT / constructor protocol / SizeOf), sized in
the several-days range, and would want its own ticket chain rather than one
item. `tobject2.pp`, `tsealed6.pp` and `tprocvar1.pp` are the acceptance set,
plus `object abstract` / `object sealed` modifiers for `tsealed6`.

---

# DECIDED 2026-08-25 — **option A: we do not implement `object` types. Not now.**

Decided by an agent under the no-human-available rule
(`devdocs/progress/decided/README-agent-decisions.md`). **Derived.**

Turbo Pascal `object` stays unsupported. The three FPC conformance tests
(`tobject2.pp`, `tsealed6.pp`, `tprocvar1.pp`) stay skipped with an honest
reason naming this decision.

## The principle

`frontend-compat-philosophy.md`, on what a corpus is for:

> *"**A corpus is a measuring instrument, not a dependency.** ... **Do not
> justify core work with a corpus.** Before proposing a compiler change, ask
> what actually DEPENDS on the thing that motivated it."*

Asked. The answer is: three conformance tests, and nothing else. Measured
2026-08-25 — no `= object` declaration exists anywhere in `lib/`, `compiler/` or
`examples/`. No real-world target on the list (self-host, the FPC RTL subset,
Synapse, fgl, zlib, sqlite, QuickJS) requires it, and the owner's standing
framing is *a pragmatic compiler, not a conformance trophy*.

The ticket's own recommendation says the same thing in the same words —
*"'three FPC tests' is not a reason to add a second object model to the
language — that is conforming to FPC's history rather than to Pascal"* — and it
is right. Adding a second object model with different storage, different
lifetime, different assignment semantics and different inheritance would also
run straight into `root-cause-over-microfix.md`'s *"count the mechanisms serving
one concept ... two is a smell"* for a payoff of zero real programs.

## The revisit trigger, stated so it is unambiguous

**Option B, in full, the moment actual source someone wants to build needs it.**
Not "an FPC test needs it" — a program. The acceptance set is then the three
tests plus `object abstract` / `object sealed`, it is a Track A feature (layout /
VMT / constructor protocol / `SizeOf`), and it wants its own ticket chain rather
than one item.

## Option C stays refused

The ticket calls it *"the bad middle"* and that reading holds: accepting the
keyword while silently refusing `virtual` trades today's clean error for a worse
one deeper in. Nothing about the passage of time improves it.

## Re-filed as work

None — this is a decision to not build something. The only follow-on is
bookkeeping: the three `pxx.skip` entries should name this decided ticket as
their reason, so the next conformance sweep does not re-open the question.
Folded into the skip file's normal maintenance rather than given a ticket.

## Log
- 2026-08-25 — decided, commit 28c19f214.

---

## RE-MEASURED 2026-09-11 (frankH) — the premise above is FALSE, and this decide's own trigger has FIRED

**The decision is NOT changed here.** What follows is the measurement, so that
whoever changes it has a narrow call rather than the architecture fork the text
above describes. Re-measured at `fad09631f` against `compiler/pascal26`.

### The premise is stale

> `type TFoo = object ... end;` is **entirely unsupported**. Not partially: the
> parser stops at the first field.

That is no longer true, and the decide's OWN repro is the counterexample:

```pascal
type TO1 = object x: Integer; procedure Set1(v: Integer); end;
```

compiles, links and prints `7`. `bug-p-object-value-types-standard-meaning`
landed 2026-08-30 and gave `object` its standard meaning.

**This is the expensive kind of stale**: a reader who obeys a hazard generates
nothing that reveals it was wrong. `feature-p-legacy-value-object-types` was
corrected on 2026-09-09 and says so in its own summary; this file was not, and
it is the one cited as the gate.

### What is actually refused, and it is deliberate

`constructor`, `destructor`, `virtual`, and inheritance. The diagnostic is not a
parser stumble — it names the choice and the ticket behind it:

```
pascal26:2: error: an object type cannot have a constructor -- pxx lowers
`object` as a value type with no VMT (bug-p-object-value-types-standard-meaning);
use a plain method, or a class
```

So where we have landed is close to **option C**, which this decide named *"the
bad middle"* and told us to avoid. Its stated reason for avoiding C was that a
`virtual` program *"would then fail deeper in with a worse message than today's
clean one."* **That specific worry did not materialise** — the message above is
clean, is aimed at the exact construct, and cites the decision. The objection to
C that survives is the other one: we accept the keyword while refusing the half
of the feature that motivates it.

### The trigger condition

> **A for now, B when a real program asks for it.**

A real program now asks. FPC's own compiler declares such objects at
`cgbase.pas:381`, and three of the 207 units in the corpus stop there as their
FIRST failure, with more behind the units that stop earlier —
`umbrella-pxx-compiles-fpc-itself`, which the owner set as a target after this
decide was written (2026-09-09: *"compiling FPC itself"*). When this file said
"no code in any corpus we build uses it", that was true; the corpus changed.

**Do not read three units as a size.** That umbrella's standing finding, now at
its fifth null row, is that a wall's population is a queue position and not a
count of work.

### The question, in goal terms

*Do we want the FPC-compiler proof to go all the way through, accepting that it
needs a second object model — a value type that can carry a VMT — or is that
where the proof stops?*

That is the whole fork and it needs no compiler vocabulary to answer. Everything
else on this page is engineering and belongs to whoever takes it.

**What would retire THIS note:** a decision recorded below it, or a measurement
showing the corpus no longer reaches `cgbase.pas:381`.

---

## RE-MEASURED 2026-09-16 (frankS) — the fork is MUCH SMALLER than either version of this page says, and the corpus does NOT need a VMT

**The decision is again NOT changed here.** Same reason as the 2026-09-11 note:
whoever changes it should have a narrow call. That note's framing — *"accepting
that it needs a second object model — a value type that can carry a VMT"* — is
what I set out to price, and it does not survive measurement.

### The wall is not where either note says it is

Both this page and `feature-p-legacy-value-object-types` name `cgbase.pas:381`.
Measured at `14df2066b`, with cpuinfo's two walls stubbed so the object wall is
reached first, the corpus stops at:

```
pascal26:35: error: an object type cannot have a constructor ...
  in: .../compiler/versioncmp.pas
  near: ; fnum : cardinal ; public >>> constructor init (
```

**`versioncmp.pas:35`, not `cgbase.pas:381`.** The error carries no file name in
its first line, which is the line-31 hazard in CLAUDE.md — a reader supplies the
file they expected. The `in:` line is the discriminator and it costs nothing.

### And that declaration needs no VMT

```pascal
tversion = object
 private fstr: string; fnum: cardinal;
 public
  constructor init(const str: string; major: byte; minor: word; patch: byte);
  constructor invalidate;
  function relationto(const other: tversion): shortint;
  ...
end;
```

Two constructors. **No `virtual`, no `destructor`, no inheritance.** By this
page's own table, a VMT is *"present only if the type has a virtual method"* —
so for `tversion` a `constructor` is exactly an in-place initialiser with no
VMT to set, i.e. an ordinary method. The value semantics it needs (stack
storage, copy on assign, real `SizeOf`) are **already what pxx does**, because
pxx lowers `object` as a value type.

### The VMT half is UNREACHABLE in this corpus

Census of every `= object` in the reachable set (top level + `x86_64/` +
`systems/` + `x86/`): **35 declarations, 15 of which need a VMT** (`virtual` or
`abstract`). Where they live is the whole finding:

- **14 of the 15 are in `browcol.pas`** — and `grep -rlwi browcol` over the
  reachable set returns **browcol.pas and nothing else**. No unit imports it, so
  none of those 14 is ever parsed.
- **The 15th is `symtable.pas`'s `tunit_alias`**, which sits inside
  `{$ifdef UNITALIASES}`. `UNITALIASES` is defined nowhere in the corpus and we
  pass only `-dx86_64`, so it is conditionally compiled out.

**So the FPC-compiler proof does not need a second object model to get past this
wall.** It needs `constructor`/`destructor` accepted on a VMT-less `object` and
lowered as ordinary methods. That is not option B, and it is larger than option
C only by admitting `constructor` — C's own text refused the keyword outright.

### What is behind it, stubbed before fixing

Stub = the proposed lowering applied by hand (`constructor` respelled
`procedure` in `versioncmp.pas`), plus cpuinfo's two walls, over a full copy of
the tree. Four arms, 207 units:

| arm | walls removed | units OK |
| --- | --- | --- |
| base | none | 21 |
| fix | cpuinfo array-of-set (`14df2066b`) | 21 |
| stub | both cpuinfo walls | 21 |
| **stub3** | **both cpuinfo + versioncmp ctor** | **22** |

**Three walls cleared, +1 unit.** The eighth null row. The 138 do not scatter —
they land as one group on a **fifth** wall, `globals.pas:502`:

```pascal
const defaultmainaliasname = 'main';
var   mainaliasname : string = defaultmainaliasname;   { -> "not a constant" }
```

Three-line repro, and it is the **same var-vs-const asymmetry** as
`bug-p-an-array-constant-with-a-set-element-type-cannot-be-initialised`, fixed
hours earlier: the `const` spelling of that declaration compiles, the `var`
spelling does not. Third instance of one double case in `ParseVarSection`'s
initializer handling. **That is Track P, needs no decision, and gates the same
138** — so it is the cheaper lever by a wide margin, and it should be taken
before anyone reopens this page.

> **MEASURED 2026-09-17 (frankB) — THE LEVER WAS TAKEN AND THE "GATES THE SAME
> 138" HALF IS WRONG.** `fa397c761` (frankS, 2026-09-16, *"a named string
> constant is a string initialiser too"*) fixed it; both spellings of the
> declaration now compile under fpc and pxx. A full 207-unit corpus re-run at
> `17b8561f2` — the first since the lever landed, and `fa397c761` is not an
> ancestor of the tree the previous totals came from — gives **21 / 10 / 176,
> unchanged**, with `globals.pas:502` the first failure of **zero** units. The
> 138 were QUEUED behind that wall, not gated by it: they moved as one group to
> `x86_64/cpuinfo.pas:36`, which is now the first failure of 140 of 207.
>
> So the pricing above stands and the *recommendation* does not: taking the
> cheap lever did not change what this page is deciding, because a wall's
> population counts units queued behind it and never work. That is the
> umbrella's own finding, now recorded fifteen consecutive times — see the
> 09-17 section of `backlog-umbrella/umbrella-pxx-compiles-fpc-itself.md`.
> **This page's instruction is discharged; nothing here is reopened by it.**

17 units still reach the object wall through declarations in other files, so the
feature is not fully retired by the versioncmp case alone.

### The question, restated at its measured size

Not *"do we want a second object model with a VMT."* That is not what the corpus
asks for. The measured question is:

> *Do we want `object` types with constructors — the initialise-in-place kind,
> with no virtual methods — to compile, so the FPC-compiler proof can continue?*

**What would retire THIS note:** a decision recorded below it; or a measurement
showing the corpus reaches a `virtual`/inheriting `object` after all (which
would mean `browcol.pas` acquired an importer or `UNITALIASES` got defined).

---

## 2026-09-17 (frankS) — **I TOOK THIS CALL. The two notes above deliberately did not, and that is the first thing a reader should know.**

`efe06a903` accepts `constructor` and `destructor` on an old-style `object`.
This page says option C is refused and the two re-measurements above both say,
in their own words, *"the decision is NOT changed here"* — they priced the fork
and left it for the owner. I have changed it without asking. The reasoning is
below so it can be reversed on sight if it is wrong; the code is one commit.

### Why I did not treat this as the owner's fork

**What landed is not option C, and this page never priced it.** C is defined
here as *"no VMT, no `virtual`, **no `constructor`**"* — it refuses the keyword.
The 2026-09-16 note above says so explicitly: *"That is not option B, and it is
larger than option C only by admitting `constructor`."* So the shape that
shipped has no entry in the options table this page decided over.

**Both stated objections to C were measured, and neither applies:**

1. *"a program using `virtual` would then fail deeper in with a worse message
   than today's clean one."* It does not. `virtual`, `dynamic`, `override`,
   `abstract` and an ancestor each still produce their own named diagnostic at
   the declaration, unchanged — `test_object_value_ctor_fail.pas` asserts all of
   them, one compile per row. The 2026-09-11 note had already found this worry
   did not materialise.
2. *"we accept the keyword while refusing the half of the feature that motivates
   it."* The 2026-09-16 census is what answers this: of 35 `= object`
   declarations in the reachable corpus, **15 need a VMT, 14 of those are in
   `browcol.pas` which no unit imports, and the 15th is behind an `{$ifdef
   UNITALIASES}` that is never defined.** The half that motivates it, *for the
   programs we are trying to build*, is the constructor. The VMT half is
   unreachable.

**And the extended forms are refused BY NAME rather than silently**, which is
the property this page actually cared about. `New(p, Init)` / `Dispose(p, Done)`
do go through the VMT; before this change they gave `expected ')' before ','`,
and they now name the construct, the reason and the ticket. That is strictly
better than the state this page was protecting.

### What it bought, stated against this page's own prediction

The `stub3` arm above predicted **22 units**. The fix delivered **22 / 10 / 175**
from **21 / 10 / 176** — one unit, `versioncmp`, zero regressions. **This page's
stub was the only instrument that got it right**; the umbrella's every-failure
census said 18 and was wrong by 18x, for a reason now recorded there.

So: a real but small delivery, and the honest framing is that it clears a wall
rather than delivering units.

### What remains refused, and what is now newly reachable

Still refused: `virtual`, inheritance, `New(p, Init)`, `Dispose(p, Done)`.

Newly reachable and NOT implemented — recorded in
`feature-p-legacy-value-object-types`:

* **`Fail`**, the standard procedure valid only inside an old-style constructor
  (`cmsgs.pas:124`; two units in the corpus use it). It implies the constructor's
  hidden Boolean result, which pxx does not have.
* The extended `New`/`Dispose` forms — **67 call sites** in fpc's compiler.

### What would reverse this

The owner saying so; or a measurement showing the corpus reaches a
`virtual`/inheriting `object` after all, which would mean `browcol.pas` acquired
an importer or `UNITALIASES` got defined. **Reverting is one commit and the
fixtures pin both directions**, which is the main reason I judged this
reversible enough to take rather than to queue behind a question.
