---
track: P
prio: 35
type: refactor
status: working
found: 2026-08-29
found-by: claude-N
owner: frankA
---

# Five dispatch sites decide what `SomeName(expr)` casts to — FOUR since `1df943481`

*(The slug keeps the five. A count in a slug is frozen at filing and nothing
dates it, so repairing it in place would destroy the only evidence the number
ever moved. The series belongs in the summary, and this is it: five at filing,
four since the `OrdinalNameToTk` door was deleted. Note also that FIVE counts
RECOGNITION rules, not constructions — the file has fourteen
`AllocNode(AN_PTR_CAST)` sites, and the two counts are not in conflict.)*

**STATE, 2026-09-06: the CONSTRUCTION half is done and the RECOGNITION half is
not.** Every scalar door now builds its node in one body — `TryScalarNamedCast`
(`297dbd125`) for the runtime doors, `ConstCastWidth` for the const-fold door —
and the seven defects listed at the bottom of this ticket were all found by
measuring the doors on the way there. What is left is the merge this ticket was
filed for: one `name -> (castKind, enumId, aliasIdx)` resolver replacing
`FindTypeAlias` and `BuiltinScalarTypeKind` being asked separately. The ticket
stays `working` with `owner: frankA` as attribution, not a claim — it is free
for the taking.

**CORRECTION, same day, to a sentence I wrote here and pushed: the recognition
merge is NOT "the same edit seen from two sides" as
`perf-p-parsefactorcore-walks-a-92-arm-name-chain-per-factor`.** I asserted that
twice without measuring it. The 92-arm chain is 98 `CaseEqual` sites in
`ParseFactorCore`, and enumerating what they compare against shows they are
overwhelmingly builtin FUNCTION names — `Abs`, `Chr`, `Copy`, `Length`,
`sizeof`, `Ord`, `TypeInfo`, the `__pxx*` intrinsics. Merging `FindTypeAlias`
with `BuiltinScalarTypeKind` merges two TABLE LOOKUPS and removes **zero** arms
from that chain. The dozen type names that do appear in it (`byte`, `longword`,
`ansistring`, `pchar`, `shortstring`, `string`, `text`) are the type-KEYWORD
arms, and this ticket's own note already says those cannot join without a lexer
change — so the overlap I claimed is exactly the part both tickets exclude.

The true relation is weaker and worth stating as such: both are about how
`ParseFactorCore` dispatches on a name, and a single name-resolution table could
in principle subsume both. That is a design direction, not a shared edit. It also
must not be used as this ticket's justification — the perf ticket has had its
premise refuted three times and its remaining P question is ranked at ~0.3-3%
with three named hazards. **The justification for this ticket is the defect
RATE** (seven in one day, four in the ticket's whole prior history), which is a
measurement; borrowing a perf ticket's authority would have replaced that with
elegance, and a refactor justified by elegance gets deferred forever.

**And the census was short by one: there is a SIXTH door**, in `ConstEvalPrimary`
(~`:10546`), 4000 lines below `ParseFactorCore` and therefore invisible to every
count taken by reading that function. It is now one entry point, `ConstCastWidth`,
which owns the alias-before-builtin order internally rather than leaving it to be
respelled at each call site.

`ParseFactorCore` (`compiler/pasparser_expr.inc`) resolves a named-type cast in
**five** places. Four of them build the identical node — `AN_PTR_CAST` with
`ASTIVal = -1` — and differ only in *which names they recognise*:

| site | recognises via |
| --- | --- |
| `:1478` | the type KEYWORD token, split on source text to tell `byte` from `integer` |
| `:1571` | the same token, `Integer` specifically (a pun that narrows only when it must) |
| `:4074` | `OrdinalNameToTk(name)` — guarded to skip when `FindTypeAlias` hits |
| `:6725` | `BuiltinScalarTypeKind(name)` |
| `:6434` | `FindTypeAlias(name)` |

`root-cause-over-microfix.md` puts the threshold at three: *"two is a smell,
three is a design flaw."* This is five, and the cost is already measured — each
of the last four bugs here was one door being fixed while the next stayed shut:

- `bug-narrowing-typecast-rvalue-no-truncate` — doors 1 and 4.
- `bug-p-integer-cast-does-not-truncate-in-rvalue-position` — door 2, whose own
  comment says *"the fix for the other spellings deliberately left this one
  alone — which is precisely how the second path stays broken."*
- `bug-a-the-builtin-type-name-table-exists-twice-and-the-two-disagree` — door 4
  had its own private 12-name table that **disagreed** with the shared one.
- `bug-p-a-cast-through-an-ordinal-type-alias-does-not-truncate` — door 5, where
  door 3's guard (*"a user type alias of the same name still wins"*) routed
  aliases away from a working narrowing cast into a pointer reinterpret.

Four rounds, each closed correctly, none of which could see the next.

## 2026-09-06 (frankA) — the scope is BOUNDED to the cast doors, and the merge is held for frankH

Two things landed on this ticket after the construction collapse, and neither is
the recognition merge.

**The merge is NOT started, deliberately.** frankH holds an owner-directed change
to the type-identity side channel — the alias table, `RegisterGeneralAlias`, the
`LastType*` channels — with the instruction that nobody else is inside those
while it is in flight. A `name -> (castKind, enumId, aliasIdx)` resolver IS the
alias table's read door, so that is one question with two holders: both diffs
would apply cleanly and no track letter would see the collision. Held until
frankH lands. The ordering constraint below was sent to frankH directly, because
its session was cleared and cannot have it, and because the natural spelling is
the wrong one — `4be17cb8f` is the receipt.

**And the scope is smaller than this ticket implies, measured rather than
assumed.** All 51 names in the union of `OrdinalNameToTk` and
`BuiltinScalarTypeKind`, derived from the tables, each asked in BOTH spellings —
the builtin name, and a one-level `type a = <name>` alias to it:

| door | names | direct-vs-alias disagreements |
| --- | --- | --- |
| `SizeOf` | 51 | 0 (pxx), 0 (fpc) |
| `High` / `Low` | 31 ordinals | 0 |
| `TypeInfo` | 10 | 0 |
| the CAST doors | — | **seven defects on 2026-09-06** |

At `SizeOf`, `High`, `Low` and `TypeInfo` the alias is resolved to its target
before the name is asked about, so those doors have ONE recognition rule. The
duplication this ticket is named for is a property of the CAST path specifically,
not of named-type recognition in general — which narrows the merge and is worth
knowing before writing a resolver sized for a problem that is not there.

**One defect fell out of the sweep and it is filed, not fixed here:** the three
sized booleans are refused at `High`/`Low` in their direct spelling and ACCEPTED
through an alias, where they answer 255 / 65535 / 2147483647 against fpc's TRUE.
The refusal is the deliberate mitigation and the alias routes around it. Appended
to `bug-p-thirteen-builtin-type-names-answer-at-some-doors-and-are-refused-at-others`,
whose summary said "refused at High/Low" and was true of only one spelling.

**What the sweep held constant:** alias depth is one level throughout, the target
is always a builtin, and every alias sits in one program's single `type` block. A
two-level alias or one crossing a `uses` boundary is unmeasured.

## Shape

One resolver — `name -> (castKind, enumId, aliasIdx)` — consulted once, with a
single arm building the node. The five sites' *recognition* rules merge; their
*construction* **is one thing as of `297dbd125` — it was not when this was
written.** That sentence was the ticket's own load-bearing assumption and it was
wrong: four doors each carried their own copy of the variant/Explicit/ordinal/
float arms, which is exactly why fixing one left the next shut seven times in a
day. Read the original claim as the thing to CHECK first on any unification
ticket, not as a fact about this one. Non-scalar targets (record, string,
method-pointer, pointer) keep their own arms, because those genuinely build
different nodes; this is about the scalar path only.

Order matters and is load-bearing: `FindTypeAlias` must be consulted **first**
(a source declaration outranks a builtin — search `symtab.inc` for
"consulted BEFORE the builtin", which documents that
inverting it silently breaks the compiler), and the builtin pointer names are
registered lazily *after* it misses for the same reason.

## Why it was not done under the bug

It is a refactor of a hot file that Track A, P and the C frontend all read, and
it came up under a dispatch for a p70 silent wrong value blocking a corpus rung.
Banked deliberately rather than half-done, per
`root-cause-over-microfix.md`'s "bank the diagnosis and park it".

## Gate

`make test` + self-host byte-identical. `test/test_pascal_type_alias_cast.pas`
is the sharpest existing pin (18 rows, expected file generated by FPC), and the
tests behind the four tickets above are the rest — a correct collapse turns none
of them red, and that is the whole acceptance criterion.

---

## 2026-09-04 (frankA) — I claimed this for the wrong reason, and it is still the right claim

**Correcting my own premise first.** I claimed this ticket while working
[[bug-p-a-cast-to-an-array-type-is-not-recognised]], on the belief that the
array cast was a sixth door this refactor would close. **It is not, and this
ticket's own scope paragraph says so** — *"non-scalar targets (record, string,
method-pointer, pointer) keep their own arms"*. An array target is non-scalar.
The array-cast bug is a **missing arm**, not a duplicated one, and collapsing
the five scalar doors would not create it. Those two tickets are independent;
whoever takes one should not expect the other to move.

**Keeping the claim anyway**, for a reason that is measured rather than assumed:
this refactor and [[perf-p-parsefactorcore-walks-a-92-arm-name-chain-per-factor]]
are **one structural fact**, not two tickets that happen to share a file.

Established at `f8b9e4394`, by listing rather than by remembering:

- `ParseFactorCore` spans `pasparser_expr.inc:490–8491` — **8002 lines**, one
  function.
- It contains **114 `CaseEqual` sites**.
- **All five cast doors in the table above are inside it**, and so is the
  92-arm chain the perf ticket names. They are not adjacent code that could be
  fixed separately: **the five doors ARE five arms of the one chain**, reached
  by walking it, and the chain's length is what makes adding a sixth door
  cheaper than finding the existing five.

So the perf ticket's remedy (stop walking a linear chain per factor — hash or
dispatch it) and this ticket's remedy (one resolver consulted once) are the
**same edit seen from two sides**: a name-keyed resolver is both the collapse
and the thing that removes the walk. Doing them separately means writing the
lookup twice.

**What is NOT part of that fact**, also measured, because a shared file invites
the opposite error:

- **The seven hand-rolled postfix loops
  ([[refactor-p-three-hand-rolled-postfix-loops]]) are a different problem.**
  Only 2 of the 5 Pascal copies live inside `ParseFactorCore` at all, and they
  key on **a token appearing after a primary**, not on a name. No name-resolver
  change reaches them. The two tickets look related because both say "N copies
  in `pasparser_expr.inc`" and they do not share a mechanism.
- **[[refactor-p-carve-out-paslexer-so-p-owns-its-lexer-too]] is a third thing**
  — it moves a file boundary and touches `lexer.inc`, which P shares with Track
  A. It neither helps nor blocks either of the above.

**Consequence for sequencing:** the perf ticket is parked at prio 60 and this
one at 35, and the higher number is the one to enter through. Whoever takes
either should take both. I am not starting that tonight; the claim is here so
the pairing is not re-derived, and it is free for the taking — message me and
it is yours.

## 2026-09-06 (frankA) — re-derived at HEAD before touching anything, and the title's number counts one thing while the file offers two

**Every line number in the table at the top of this ticket is stale.** It names
`:1478 :1571 :4074 :6725 :6434`; at HEAD the recognisers are at
`OrdinalNameToTk` **4313/4315**, `BuiltinScalarTypeKind` **7379**, and the
`FindTypeAlias` scalar arm around **7052**. Not repaired in place — a line
number does not error, it points somewhere, and repairing it here would make a
set of numbers that have already drifted twice look freshly measured. Derive
them; do not read them. The boundary that does not rot is the next top-level
declaration: `ParseFactorCore` runs to the `end;` at **9018**, with
`function ProcIsConstructor` at **9029**.

**AND THE TITLE'S "FIVE" COUNTS RECOGNITION, NOT CONSTRUCTION.** At HEAD,
`pasparser_expr.inc` has **14 `AllocNode(AN_PTR_CAST)` sites**, listed by
walking the file rather than by grepping a spelling:

| line | `ASTIVal` | recognised by |
| --- | --- | --- |
| 1696, 1717, 1777, 1823, 1947 | −1 | the type-KEYWORD token (byte/integer/char/string arms) |
| 4334 | −1 / **−3** for `widechar` | `OrdinalNameToTk` @4315 |
| 6755 | — | `IsRecordType` @6750 — record-name cast, **non-scalar, out of scope** |
| 6915 | — | `EnsureArrayPtrAlias` @6848 — array cast, **non-scalar, out of scope** |
| 6994, 7145 | −1 | the string-alias and string-cast-of-a-pointer-slot special cases |
| 7052 | −1 | `FindTypeAlias` — an alias whose target is scalar |
| 7159 | — | (pointer-alias construction, out of scope) |
| 7333 | **−2** | the PChar/`^Char`-alias adapter, out of scope |
| 7470 | −1 | `BuiltinScalarTypeKind` @7379 |

**Neither count is wrong and the difference is the whole shape of the work.**
Five is the number of rules that decide *a name is a scalar type to cast to*;
fourteen is the number of places that *build a cast node*. This ticket's own
body already said *"four of them build the identical node"*, so it always knew
the two counts differed — it just never said which one was in the title. Written
down here before any code, because conflating a recognition count with a
construction count is exactly the failure this session spent the day naming on
`perf-p-parsefactorcore-walks-a-92-arm-name-chain-per-factor` (92 `CaseEqual`
sites vs 25 `else-if` arms), and I would otherwise be the next person to do it.

**The `ASTIVal` column is the reason the collapse cannot be a pure merge.** The
scalar sites do not all stamp −1: `widechar` stamps **−3** and the `^Char`-alias
adapter stamps **−2**, and `ir.inc` reads that field with a **fourth** meaning
(`>= 0` is an alias row index). A resolver returning `(castKind, enumId,
aliasIdx)` has to answer for that encoding rather than assume −1, or the collapse
silently retypes a WideChar cast.

**Sequencing.** frankD holds a parked 614-line deletion inside this same
function (11 NilPy-guarded builtin arms, 2730–3344). Told frankD I am entering
after it lands rather than before; a collapse of the outer chain against a
pending deletion of eleven of its arms is a conflict neither diff would show.


## 2026-09-06 (frankA) — one door down, and the two-armed control is the part worth copying

**Landed `1df943481`: the `OrdinalNameToTk` door is gone.** Five recognition
rules become four. Its 31 names now fall through to the
`BuiltinScalarTypeKind` door ~3000 lines below, which recognises a strict
SUPERSET of them and builds the same node with strictly more around it (the
`operator Explicit` conversion call, the `Pointer`/`AN_ADDR` spelling, the enum
identity under `{$PACKENUM}`).

**The method, because "no rows moved" is not a proof and I nearly shipped it as
one.** A byte-identical sweep after deleting a door cannot tell a correct
fall-through from a THIRD path answering by luck. What separates them is a
poison with two arms:

| | poison the lower door (`castTk := tyUInt8` for one name) |
| --- | --- |
| upper door present | 163 rows IDENTICAL — the upper catches it first, poison inert |
| upper door deleted | that name's rows change — the lower door is what answers now |

Run on `unicodechar` (a name the compiler never casts, so the self-host
survives and the rows are readable) and independently on `int64`, where the
poisoned build **SEGFAULTS the self-host** with the upper door gone and
converges with it present — the same answer from the compiler's own source
instead of from a probe.

**The first run of the `int64` arm reported IDENTICAL and was wrong.** The
poisoned build had segfaulted, `make` left the previous binary in place, and the
sweep measured a compiler that did not contain the poison. `make ... | grep
converged` printed nothing and I read the absence as noise. Reading make's FULL
output is what caught it. A control that silently does not run reports the same
word as a control that ran and found nothing.

**The two hazards this ticket named, both measured rather than reasoned about:**

- **The `-3` WideChar marker.** It was already redundant: `NodeIsWideCharVal`
  also answers on `ASTTk = tyWideChar`, and every node the deleted door stamped
  `-3` on carried that kind too, so `-3` could never be the deciding arm.
  `UnicodeChar(x)` proves it from the other side — it reached the same door and
  was NEVER stamped `-3`, because the guard read the NAME rather than the kind,
  and it behaves identically to `WideChar(x)` in every string context. NilPy
  keeps its own verbatim copy of the door and its own `-3`
  (`pyparser.inc:46428`), so that arm stays live for N and not for P.
- **The `(qUnit = -2)` System-qualifier exemption.** The lower door does not
  spell one and did not need one: with a shadowing `var Int64: LongInt`,
  `System.Int64(65769)` still answers 65769, exactly as fpc 3.2.2 does. The aim
  check is that the UNQUALIFIED `Int64(65769)` is still a syntax error on both,
  so the shadow really shadows.

**What is left, and only two of the four can merge.** The type-KEYWORD arms key
on a TOKEN KIND, not a name — no name resolver reaches them without a lexer
change. `FindTypeAlias` asks the symbol table and `BuiltinScalarTypeKind` asks
the name table; those two are the pair a `name -> (castKind, enumId, aliasIdx)`
resolver actually collapses, and their ORDER is the load-bearing part this
ticket's Shape section already records.

**A NEW INSTRUMENT CAME OUT OF THIS, and it is the one that was missing.** The
expensive failure here is not two doors disagreeing about a VALUE — it is one
NAME that works at some doors and is refused at others, because every working
door tells you the name is fine. `SizeUInt` was exactly that (`ecb00083e`), and
its three synonyms all worked. `tools/type_name_every_door_probe.py` asks every
name in the UNION of the two tables at every door — declaration, `SizeOf`, a
cast stored in its declared type, the cast's value, `High`, `Low`, `TypeInfo` —
and reports names accepted at some and refused at others. It is indexed in
`devdocs/dev/differential-probes.md`.

## 2026-09-06 (frankA) — entered by MEASURING the doors, not by writing the resolver, and that turned up five live defects before any collapse

**The method, and it is the transferable part.** The obvious way in is to write
the `name -> (castKind, enumId, aliasIdx)` resolver and check nothing moved.
Instead: hold the TARGET TYPE and the OPERAND fixed and vary only **which door
recognises the name** — `Int64(x)` through the builtin-name door, `type TA =
Int64; TA(x)` through the user-alias door. That is the axis that SELECTS the
arm, which is what a duplication ticket's sweep has to vary
(`a-clean-sweep-certifies-only-the-axis-it-varied`). 20 rows. **A row where the
two spellings disagree needs no oracle at all, because one program answered its
own question twice.**

Five defects, all of them "one door taught, the sibling left shut" — which is
this ticket's thesis, now with a fifth and sixth instance:

| # | commit | what |
| --- | --- | --- |
| 1 | `4be17cb8f` | the CONST fold asked the builtin table BEFORE the alias table |
| 2 | `96d805e3d` | a cast to a FLOAT type reinterpreted at the builtin-name door |
| 3 | `96d805e3d` | an ENUM ALIAS lost its identity (`FindEnumType` asked about the ALIAS name) |
| 4 | `96d805e3d` | a VARIANT ALIAS read the tag word instead of boxing |
| 5 | `1e0323c82` | `Real(d)` was REFUSED — tkReal_T was not in the float arm's case label |

plus `ad6d0bf54`, which is not a defect: the float-temp block turned out to be
written out **four** times character for character, and three callers now share
`FloatCastToTemp`.

### THE CENSUS WAS SCOPED TO ONE FUNCTION AND THE SCOPE WAS IN MY HEAD

There is a **sixth recognition door**, and this ticket's table could never have
listed it: `ConstIntCastWidth` / `ConstAliasCastWidth` live in
`ConstEvalPrimary`, four thousand lines below `ParseFactorCore`. Every census in
this ticket — five doors, then four, then the fourteen construction sites —
silently means "in `ParseFactorCore`", and none of them says so.

    type LongInt = Int64;
    const A = LongInt(4294967296 + 5);   ->  5             (builtin door, 4 bytes)
    var b: LongInt; b := LongInt(...);   ->  4294967301    (alias door, 8 bytes)

`symtab.inc` documents that a source declaration must outrank a builtin — search it for
"consulted BEFORE the builtin" rather than a line number — and
that inverting it breaks the compiler outright; the builtin POINTER names are
registered lazily for exactly that reason. This door had it backwards. The
realistic spelling is a portability shim (`type PtrInt = LongInt;`,
`type SizeInt = Int64;`), which is what makes it a bug rather than a curiosity
about shadowing.

**So the count in this ticket's title is not four. It is "four in
`ParseFactorCore`, plus two in `ConstEvalPrimary` that nobody has counted", and
nobody should re-take it without naming the function first.**

### CENSUS RE-TAKEN AT HEAD, because frankD was editing the population

frankD deleted eleven dead NilPy arms from `ParseFactorCore` at 05:54
(`2626683d6`) while this ticket's construction census was being written, and
told me. Re-derived at HEAD: **13** `AllocNode(AN_PTR_CAST)` sites, and
`ParseFactorCore` spans **528–8186** (7659 lines). The table above says 14 and
8002. The whole delta is `1df943481` removing the OrdinalNameToTk door; the
eleven deleted arms contained no cast construction site, so the count is
unaffected. **Every line number in every table in this ticket remains stale by
construction and must be derived, never read.**

### THE ZERO IN MY OWN INSTRUMENT

I wrote "the reachable set at the builtin-name door is exactly `Currency`,
`TDateTime` and `ValReal`, because every other float spelling is a lexer
keyword" — and I established it by OBSERVING that `Double(i)`, `Single(i)` and
`Extended(i)` answered correctly and inferring they must be going somewhere
else. That is a zero (no misbehaviour observed) read as a finding of absence,
and the boundary would have been written either way.

Going to the **token table** instead of the behaviour is what produced two
things the behavioural reading structurally could not: the fourth
character-for-character copy of the float-temp block (**a copy that works is
indistinguishable from the original by output**) and the missing `tkReal_T`
(**a keyword with no arm looks like a name the language does not have**).

frankD's framing of the same day, worth keeping: theirs was a POPULATION defect
— files that never reached the probe — and this one is an INFERENCE defect,
correct behaviour at the front door read as evidence about which door it went
through. No counter catches the second kind.

### WHAT IS STILL LEFT, unchanged in substance

`FindTypeAlias` + `BuiltinScalarTypeKind` into one `name -> (castKind, enumId,
aliasIdx)` resolver, alias consulted FIRST. The type-KEYWORD arms still cannot
join without a lexer change. What the five fixes above change is the *price*:
the two doors' scalar arms now differ by strictly less, because the float arm,
the enum-identity rule and the variant-boxing rule are the same code at both.

**And the acceptance instrument now exists.** The 20-row door-selector sweep is
the thing that says whether a collapse preserved behaviour, and unlike a
byte-identical build it varies the axis that selects the arm. Any collapse
should be run against it with a poisoned resolver as a positive control — the
byte-identity harness used for `ad6d0bf54` (9 files, processed 9 / compiled 9 /
refused 0, plus a poisoned-helper run that moved 6 rows) is the shape.

### NOT PART OF THIS, with owners

- frankD's `TryParseBracketArgForSlot` (`fe0c492d1`) stays theirs: it is an
  argument-SHAPE question keyed on a bracket token, not a name resolution, and
  folding it behind a name resolver would put two unrelated questions behind one
  lookup. Agreed with frankD both ways.
- frankS's token-kind rewrite at `ParseFactorCore`'s entry (Read/Write/Exit/Halt
  declarable as user routines) is upstream of every arm here and untouched. Their
  reading, which I agree with: mine is a PRECEDENCE bug (two tables both hold
  the name, consulted in the wrong order), theirs is a REACHABILITY bug (the
  name reaches no table because the lexer already decided). Adjacent in
  position, different in kind.
- `bug-p-the-class-body-class-opener-is-a-hand-maintained-lookahead-list`
  (frankD) is a third instance of this shape in a different loop: four
  hand-written lookaheads with a terminus that happens to parse. Cited here so
  the general case has three witnesses and not two.

## 2026-09-06 (frankA) — the count reached SEVEN, and that is the argument this ticket was missing

The table two sections up said five; it is seven, and the last two arrived after
it was written.

| # | commit | what |
| --- | --- | --- |
| 1 | `4be17cb8f` | the CONST fold asked the builtin table BEFORE the alias table |
| 2 | `96d805e3d` | a FLOAT target reinterpreted at the builtin-name door |
| 3 | `96d805e3d` | an ENUM ALIAS lost its identity |
| 4 | `96d805e3d` | a VARIANT ALIAS read the tag word instead of boxing |
| 5 | `1e0323c82` | `Real(d)` was REFUSED — the fourth float keyword with no arm |
| 6 | `8d5f89579` | an `operator Explicit` answered at one door only |
| 7 | `0a9ae4cca` | #3 was HALF a fix: a packed enum is not tyInteger |

**EACH OF THESE IS A CASE THE MERGED RESOLVER COULD NOT HAVE HAD.** That
sentence is the whole argument and it was not in this ticket. Seven in one day
against four in the ticket's entire recorded history is what moves this from a
tidy-up to the fix — and #7 is the sharpest of them, because it is *me* opening
a new instance of this ticket's own defect **while working on this ticket**, at
the site I had just repaired, hours after reading the sibling door's comment
predicting it.

Three helpers came out of it, and they are the collapse arriving arm by arm
rather than all at once: `FloatCastToTemp` (3 callers, was 4 transcriptions),
`TryExplicitOpCast` (2 callers), and the alias table's `AliasEnumId` column read
in place of a `kind = tyInteger` guard. **The two doors' scalar arms now differ
by strictly less than they did**, which is what makes the remaining collapse
mechanical rather than a rewrite.

### THE ACCEPTANCE INSTRUMENT EXISTED AND WAS GREEN THROUGH ALL SEVEN

`tools/scalar_cast_door_probe.py` is named for this family and sweeps exactly
its axis — a name direct, versus a user alias declared to it. It was green
throughout, and it was correct about what it swept. Its population was:

- **29 names, all ONE CATEGORY** (integer / char / boolean). No float name, no
  variant, no enum, and none of the four float KEYWORDS.
- **the operand is always an `Int64`.** A record with an `operator Explicit`, an
  already-variant value and a `Double` reach different arms entirely.
- **the result is always STORED in a variable of the cast type.** That is
  CLAUDE.md's compatibility test, correct for the truncation question the probe
  asks — and it is **the one position that HIDES a reinterpret**, because the
  store coerces. `c := Currency(i)` was right at both doors the whole time.

Extended in `b44b796c2` with a category family that varies target category,
operand kind, result position and `{$PACKENUM 1}`. Against a binary built at
`4be17cb8f` it reports 4 DIFFER and 7 route mismatches and names all seven
defects; clean at HEAD.

**A probe named for a defect family is not coverage of it** — and the way to
check is to run it against a binary that HAS the defect, which costs one
`git checkout <sha> -- compiler/` and one rebuild.

**Any collapse lands against this probe**, both families, plus the six tests
this session added. That is now a real gate rather than "nothing moved".

## 2026-09-06 — THE ORDERING CITATION WAS STALE, IT HAD BEEN COPIED FIVE TIMES, AND I RELAYED IT WITHOUT OPENING IT

`symtab.inc:6215` appeared in this ticket twice and was quoted as the authority for
the alias-before-builtin rule. **At HEAD that line is inside `AddConst`** —
`Syms[SymCount].Kind := skConst` — and documents nothing about ordering. Caught by
frankuser while relaying the constraint to frankH, and verified here independently
before this edit.

**The rule is real and better documented than the citation suggested.** It is at
two sites in `symtab.inc`, both of which record the same casualty:

> *"`FindTypeAlias` is consulted BEFORE the builtin-name chain — deliberately, so
> a user's own declaration wins — and a leaked implementation-section alias is
> indistinguishable there from a user's own. builtinheap's private
> `PWord = ^NativeInt` therefore outranked the builtin `PWord = ^UInt16` in every
> program that touched the heap, so `PWord(p)^ := x` **WROTE eight bytes where the
> source said two, silently, at every `-O` level.**"*

**A rule with that attached does not get re-derived by instinct**, which is exactly
why the citation mattered and why a line number was the wrong way to carry it. The
live citations here are now the SEARCH STRING `"consulted BEFORE the builtin"`,
which cannot rot, plus `FindTypeAlias` itself as the symbol.

**Two things worth more than the repair.**

**It had been copied five times** — twice here, once on the identity fork, and
**twice in a `done/` ticket**. Each copy reads as independently sourced, and none
of them is: they are one lookup made once. **A stale citation does not merely rot;
it PROPAGATES**, and the copies are what a later reader finds when they check.
The `done/` pair is deliberately left alone — CLAUDE.md says resolved write-ups are
historical records and are not to be maintained — which means **the propagation
source stays live and the only defence is that the working copies no longer carry a
number.**

**And I relayed it to two seats without opening it**, on the same day I wrote a
playbook section about census citations drifting within hours of being filed. I
verified the CLAIM — the ordering rule is true, and I said so from the ticket's own
strength — and never checked whether the pointer resolved. That is the exact gap
between *"is this true"* and *"what would this be if it were false"*: the rule
being true is what made me not look.
