---
slug: refactor-p-a-parameters-own-kind-and-its-element-kind-are-one-field-and-the-name-says-neither
track: P
type: refactor
prio: 45
status: backlog
created: 2026-09-06
found-by: frankB
owner: ""
blocked-by: []
title: "`Params[j].TypeKind` means two different things depending on `IsArray`, and a caller that reads it alone gets a plausible wrong answer"
summary: "THREE SEATS HIT THIS IN ONE DAY FROM THREE DOORS, which is the argument for the shape of the fix rather than for another predicate. `Procs[pi].Params[j].TypeKind` is the parameter's OWN kind when `Params[j].IsArray` is False and its ELEMENT kind when True; the field name says neither, and nothing refuses a caller that reads it without asking. Verified at pasparser_proc.inc ~1235 (frankS): the named-array-type arm sets `tk := IntToTypeKind(ArrTypeElemTk[paramAi])` alongside `isArr := True`, and that tk is what reaches Params[i].TypeKind. Three landed instances: the parameter default-value check read TypeKind alone and saw a string parameter where an `array of string` was declared (bug-p-a-default-value-is-accepted-on-an-open-array-parameter, closed 2026-09-06); two bracket-argument arms guarded on IsArray alone and sent every `[...]` to the TVarRec builder (bug-p-the-bracket-argument-door-is-hand-written-at-every-call-path, closed 2026-09-06); and an open array and a named dynamic array are stored with the same element kind and the same IsArray bit, so they are ONE signature to FindProcOverloadRec (bug-p-an-open-array-and-a-named-dynamic-array-parameter-are-one-signature, open). THE REMEDY IS AN ACCESSOR THAT REFUSES, NOT A PREDICATE (frankD, seconded by frankS): a predicate can be called correctly and still be handed the wrong field, while `ParamOwnKind(pi, j)` returning tyUnknown for an array parameter cannot give a plausible answer to a caller asking the wrong question. NOT A ONE-SITTING CHANGE and that is why it is a ticket. THE NUMBER TO CARRY IS 30 AND IT COMES WITH ITS GREP: `grep -nE '\.Params\[[^]]*\]\.TypeKind' compiler/pasparser_*.inc | grep -vE '\.TypeKind[[:space:]]*:='` = 30 read lines, 0 assignment targets, 0 in comments (call 13, lval 10, stmt 4, name 2, expr 1); frank-coordinator's comment-aware scanner says 31 for the same population and the difference is regex breadth around the subscript. That is the population all three known bugs came from and it is the tractable first increment. THE WHOLE-TREE FIGURE IS SCALE, NOT EVIDENCE, AND FOUR SEATS PRODUCED FOUR OF IT IN ONE DAY: ~18 (filed here), 209 (frankS), 266 (both of us), 263 (frank-coordinator, comment-aware -- 272 mentions, 6 in comments, 3 assignment targets). The 18 and the 209 were one defect, a filter dropping `x := Procs[..].Params[i].TypeKind`, which is a READ; the coordinator's first predicate had a third variant of it. THE 266 AGREED BECAUSE IT WAS ONE METHOD RUN TWICE -- neither of us had written the filter down, so neither could compare filters, only totals (frankS: a second source that produces a NUMBER has to publish its PREDICATE). The disposition never depended on any of them: 'more than one sitting' was true at 18 and is true at 263. THE LOAD-BEARING CLAIM IS STILL UNCHECKED -- 'many of these legitimately want the element kind' decides the ORDER of the work and nobody has read the 143 ir*/abi lines to find out. 'Zero name IsArray on the same line' is NOT evidence for it: frankS re-derived 0 over the full population and over the 57 dropped reads, so it is accidentally safe rather than actually checked. The honest version is the coordinator's five-line proximity proxy -- IR+lowering 64/142, symtab 9/32, other frontends 9/56, pasparser_* 4/30 (re-derived here; theirs 4/31) -- which is the ranking argument and is a proxy, not the claim."
---

# One field, two meanings, no refusal

```
Procs[pi].Params[j].IsArray = False  ->  TypeKind is the parameter's own kind
Procs[pi].Params[j].IsArray = True   ->  TypeKind is its ELEMENT kind
```

Nothing enforces the pairing and the field name carries no hint of it. Every
instance below is a caller that read one half and got an answer that looked
right.

| landed instance | what it read | what it did |
| --- | --- | --- |
| parameter default-value check | `TypeKind` alone | saw a string parameter for `array of string`, demanded a string literal, and accepted `= 'x'` — the callee then read a frozen literal's prefix as a length |
| bracket-argument arms (2 of them) | `IsArray` alone | sent every `[...]` to the TVarRec builder, so `array of Integer` got the wrong stride |
| overload signature identity | both, but not `ProcParamDynDepth` | `array of LongInt` and `TLongIntArray` are one signature; the later body wins and fpc binds two |

The first two are closed. The third is
[[bug-p-an-open-array-and-a-named-dynamic-array-parameter-are-one-signature]]
(frankS, P p45) and is **not** fixed by this refactor — it needs
`FindProcOverloadRec` to consult `ProcParamDynDepth`, which already records the
difference. This ticket makes that class of misread impossible to write; it does
not decide any particular caller's semantics.

## The remedy, and why it is an accessor rather than a predicate

frankD's argument, which frankS seconded from a third door: **a predicate can be
called correctly and still be handed the wrong field.** A shared
`ParamIsOpenArray(pi, j)` helps a caller who thought to ask; it does nothing for
the caller who did not know there was a question. An accessor that refuses does:

```pascal
function ParamOwnKind(pi, j: Integer): TTypeKind;   { tyUnknown when IsArray }
function ParamElemKind(pi, j: Integer): TTypeKind;  { tyUnknown when not IsArray }
```

Neither can return a plausible answer to the wrong question, which is the
property the raw field lacks. `ParamIsVarRecArray` / `ParamIsOpenArrayScalar`
(pasparser_lval.inc) already encode the array half correctly and stay; the
missing half is the one that declines.

## Why this is a ticket and not a sitting

**The number that decides whether anyone picks this up is 30, and here is the
grep that produced it — on the same line, because the previous three versions of
this number travelled without one:**

```
grep -nE '\.Params\[[^]]*\]\.TypeKind' compiler/pasparser_*.inc \
  | grep -vE '\.TypeKind[[:space:]]*:='          # 30 read lines, 0 assignment targets
```

Per file: `pasparser_call.inc` 13, `pasparser_lval.inc` 10, `pasparser_stmt.inc`
4, `pasparser_name.inc` 2, `pasparser_expr.inc` 1. Zero of the 30 sit inside a
comment. frank-coordinator's comment-aware scanner puts the same population at
**31**; the one-line difference is regex breadth around the subscript and it
changes nothing anyone would decide. **Thirty is the increment. Convert the
pasparser readers is thirty lines, not three hundred** — that is the fact this
ticket exists to carry, and it is the population all three known bugs came from.

### The whole-tree count, and why it is NOT the number to carry

Four counts in one day, from three seats: **~18** (this ticket, as filed),
**209** (frankS), **266** (both of us, agreeing), **263** (frank-coordinator).
The last is the best: a comment-aware scanner finds 272 mentions of which 6 are
inside comments and 3 are assignment targets. The 18 and the 209 were the same
defect — a filter excluding every line containing `:=`, which throws away
`x := Procs[..].Params[i].TypeKind`, a read. frank-coordinator's *first*
predicate had a third variant of it (testing for `:=` anywhere on the line rather
than immediately after the field, giving 12 targets instead of 3).

**Three seats, three versions of "is there a `:=` involved", and the two that
agreed at 266 agreed because they were the same method run twice** — neither of
us had written the filter down, so neither of us could compare filters, only
totals (frankS). **A second source that produces a NUMBER has to publish its
PREDICATE**; without it, agreement in a sub-figure and disagreement in the total
is exactly what one method run twice looks like.

None of this moved the ticket. The decision to file rather than sit rests on
"more than one sitting", which was true at 18 and is true at 263. **The number
was wrong by a factor of fifteen and the disposition never depended on it** — so
carry the 30 with its grep, and treat the whole-tree figure as scale, not as
evidence.

| where | read lines (of 263) | what they are |
| --- | --- | --- |
| `ir.inc` | 66 | marshalling |
| `pyparser.inc` | 42 | NilPy's own param table |
| `ir_codegen.inc` + five cross-target codegens | 77 | ABI, per target |
| `symtab.inc` | 31 | overload matching, RTTI |
| `cparser.inc` | 14 | the C frontend's own |
| `pasparser_*` | **30** | **the population all three known bugs came from** |
| `abi.inc`, `rtti_emit.inc`, `inline_expand.inc` | 6 | |

### The load-bearing claim in this ticket is still UNCHECKED

The sentence that decides the ORDER of the work — *"many of these legitimately
want the element kind, so this is not a substitution"* — has never been verified
against the sites. It is the reason step 3 says leave `ir_codegen*` alone, and
nobody has read those 143 lines to find out whether it is true.

**Zero of the 263 name `IsArray` on the same line.** That was offered as evidence
of unguardedness and it is not: frankS re-derived it over the full population AND
over the 57 lines their own filter had dropped, and it holds at 0 in both —
**accidentally safe rather than actually checked**, because a same-line guard is
not how anyone writes this. frank-coordinator's proximity proxy is the honest
version, `IsArray` anywhere within five lines:

| population | `IsArray` within five lines | denominator |
| --- | --- | --- |
| IR + lowering | 64 | 142 |
| `symtab.inc` | 9 | 32 |
| other frontends (`pyparser`, `cparser`) | 9 | 56 |
| **`pasparser_*`** | **4** | **30** (re-derived here; theirs, 4/31) |

**This table is the ranking argument, and it is a proxy, not the claim.**
Proximity is not intent — a nearby `IsArray` may guard a different parameter —
but the contrast is the point: nearly half the IR sites are visibly array-aware
and one in eight of the pasparser ones is. The population where the field is read
with no array question anywhere nearby is the parser, which is where all three
defects were. Somebody still has to read the 143 IR lines before anyone claims
they *want* the element kind.

## Done when

The two accessors exist, every `pasparser_*` reader of `Params[].TypeKind` has
been through a decision (converted or annotated with which question it asks), and
a new reader cannot get a plausible wrong answer without writing `.TypeKind`
explicitly.

Found by three seats on 2026-09-06: frankB (default values, bracket arguments),
frankD (the slot-mask work and the accessor design), frankS (signature identity,
and the `pasparser_proc.inc` verification of the two meanings).
