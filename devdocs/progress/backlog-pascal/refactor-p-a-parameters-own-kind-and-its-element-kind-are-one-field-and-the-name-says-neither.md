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
summary: "THREE SEATS HIT THIS IN ONE DAY FROM THREE DOORS, which is the argument for the shape of the fix rather than for another predicate. `Procs[pi].Params[j].TypeKind` is the parameter's OWN kind when `Params[j].IsArray` is False and its ELEMENT kind when True; the field name says neither, and nothing refuses a caller that reads it without asking. Verified at pasparser_proc.inc ~1235 (frankS): the named-array-type arm sets `tk := IntToTypeKind(ArrTypeElemTk[paramAi])` alongside `isArr := True`, and that tk is what reaches Params[i].TypeKind. Three landed instances: the parameter default-value check read TypeKind alone and saw a string parameter where an `array of string` was declared (bug-p-a-default-value-is-accepted-on-an-open-array-parameter, closed 2026-09-06); two bracket-argument arms guarded on IsArray alone and sent every `[...]` to the TVarRec builder (bug-p-the-bracket-argument-door-is-hand-written-at-every-call-path, closed 2026-09-06); and an open array and a named dynamic array are stored with the same element kind and the same IsArray bit, so they are ONE signature to FindProcOverloadRec (bug-p-an-open-array-and-a-named-dynamic-array-parameter-are-one-signature, open). THE REMEDY IS AN ACCESSOR THAT REFUSES, NOT A PREDICATE (frankD, seconded by frankS): a predicate can be called correctly and still be handed the wrong field, while `ParamOwnKind(pi, j)` returning tyUnknown for an array parameter cannot give a plausible answer to a caller asking the wrong question. NOT A ONE-SITTING CHANGE and that is why it is a ticket: `Params[i].TypeKind` has ~18 readers across ir_codegen*, symtab.inc, pyparser.inc and cparser.inc, and many legitimately WANT the element kind -- each site is a judgement, not a substitution."
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

`Params[i].TypeKind` has roughly 18 readers spread across `ir_codegen*`,
`symtab.inc`, `pyparser.inc` and `cparser.inc`, and **many legitimately want the
element kind** — an argument-marshalling site asking about an open array's
elements is reading the field exactly as intended. So this is not a mechanical
substitution: each site needs a decision about which question it is asking, and a
sweep that swaps them all would break the correct callers.

Suggested order, so it can land incrementally and green:
1. Add both accessors beside the existing predicates. No callers. Inert.
2. Convert the `pasparser_*` readers, where the question is nearly always the
   parameter's own kind. This is the population all three instances came from.
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
