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
summary: "THREE SEATS HIT THIS IN ONE DAY FROM THREE DOORS, which is the argument for the shape of the fix rather than for another predicate. `Procs[pi].Params[j].TypeKind` is the parameter's OWN kind when `Params[j].IsArray` is False and its ELEMENT kind when True; the field name says neither, and nothing refuses a caller that reads it without asking. Verified at pasparser_proc.inc ~1235 (frankS): the named-array-type arm sets `tk := IntToTypeKind(ArrTypeElemTk[paramAi])` alongside `isArr := True`, and that tk is what reaches Params[i].TypeKind. Three landed instances: the parameter default-value check read TypeKind alone and saw a string parameter where an `array of string` was declared (bug-p-a-default-value-is-accepted-on-an-open-array-parameter, closed 2026-09-06); two bracket-argument arms guarded on IsArray alone and sent every `[...]` to the TVarRec builder (bug-p-the-bracket-argument-door-is-hand-written-at-every-call-path, closed 2026-09-06); and an open array and a named dynamic array are stored with the same element kind and the same IsArray bit, so they are ONE signature to FindProcOverloadRec (bug-p-an-open-array-and-a-named-dynamic-array-parameter-are-one-signature, open). THE REMEDY IS AN ACCESSOR THAT REFUSES, NOT A PREDICATE (frankD, seconded by frankS): a predicate can be called correctly and still be handed the wrong field, while `ParamOwnKind(pi, j)` returning tyUnknown for an array parameter cannot give a plausible answer to a caller asking the wrong question. NOT A ONE-SITTING CHANGE and that is why it is a ticket -- BUT THE FIRST NUMBER IN THIS TICKET WAS WRONG BY A FACTOR OF FIFTEEN. Filed as '~18 readers'; frankS re-measured and said 209; both were artefacts of a filter that drops `x := Procs[..].Params[i].TypeKind`, which is a READ. Counted correctly (exclude only lines where the FIELD is the assignment target) it is 266 read lines across 19 files: ir.inc 66, pyparser.inc 42, ir_codegen.inc 33, symtab.inc 31, cparser.inc 14, the five cross-target codegens 44, pasparser_* 30, abi/rtti/inline_expand 6. ZERO of them mention IsArray on the same line (frankS, verified here), which is exactly the condition under which a mechanical substitution looks safe and is not. The 133 in ir*/abi and the 56 in the other frontends' own param tables largely WANT the element kind. The tractable first increment is pasparser_* at 30 reads, which is the population all three known bugs came from."
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

**266 read lines across 19 files**, and the number this ticket was filed with —
"roughly 18" — was wrong by a factor of fifteen. frankS re-measured it as 209 and
that was wrong too; both counts came from a filter excluding every line
containing `:=`, which throws away `x := Procs[..].Params[i].TypeKind`, a read.
Exclude only lines where the FIELD is the assignment target:

| where | read lines | what they are |
| --- | --- | --- |
| `ir.inc` | 66 | marshalling |
| `pyparser.inc` | 42 | NilPy's own param table |
| `ir_codegen.inc` + five cross-target codegens | 77 | ABI, per target |
| `symtab.inc` | 31 | overload matching, RTTI |
| `cparser.inc` | 14 | the C frontend's own |
| `pasparser_*` | 30 | **the population all three known bugs came from** |
| `abi.inc`, `rtti_emit.inc`, `inline_expand.inc` | 6 | |

**Zero of the 266 name `IsArray` on the same line** (frankS's measurement,
re-derived here). Whatever guarding exists is elsewhere in the function, which is
precisely the condition under which a mechanical substitution looks safe and is
not.

**Many legitimately want the element kind** — an argument-marshalling site asking
about an open array's elements is reading the field exactly as intended, and
that is most of the 133 in `ir*`/`abi`. So this is not a substitution: each site
needs a decision about which question it is asking, and a sweep that swapped them
all would break the correct callers.

The tractable first increment is **`pasparser_*`, 30 reads** — stated as a number
because whether someone picks this up depends on knowing that "convert the
pasparser readers" is thirty and not three hundred (frankS's point, and they were
right that the ticket left it to be inferred).

Suggested order, so it can land incrementally and green:
1. Add both accessors beside the existing predicates. No callers. Inert.
2. Convert the **30** `pasparser_*` readers, where the question is nearly always
   the parameter's own kind. This is the population all three instances came
   from, so it has the best defect-per-read ratio in the table.
3. Leave `ir_codegen*` / `symtab.inc` alone until someone has a reason —
   lowering usually wants the element kind and is not where the misreads were.
4. NilPy and C are separate frontends; convert only if their own lane wants it.

## Done when

The two accessors exist, every `pasparser_*` reader of `Params[].TypeKind` has
been through a decision (converted or annotated with which question it asks), and
a new reader cannot get a plausible wrong answer without writing `.TypeKind`
explicitly.

Found by three seats on 2026-09-06: frankB (default values, bracket arguments),
frankD (the slot-mask work and the accessor design), frankS (signature identity,
and the `pasparser_proc.inc` verification of the two meanings).
