---
slug: bug-p-a-nested-type-that-specializes-its-own-template-is-renamed-to-the-outer-specialization
title: "A generic class cannot name ITSELF in its own nested type section: `TTestT = specialize TTest<T>` inside `generic TTest<T>` is renamed to the outer specialization and fails"
track: P
prio: 55
type: bug
blocked-by: []
status: done
owner: frankS
created: 2026-09-07
resolved: 2026-09-07
resolution: fd522cc34
summary: "`generic TTest<T> = class type TTestT = specialize TTest<T>; end` -- a container naming its own node or iterator type, and the first two lines of fpc's own ugeneric99 -- did not compile: `expected '<' before ';'`. THE BOUNDARY IS THE `=`, NOT THE SELF-REFERENCE. NestedSpecGroup deliberately refuses a group preceded by `=`, because after `=` a `specialize` is a DECLARATION that must MINT a class rather than collapse to a name -- right for every template but the one being STREAMED, for which minting is the one thing impossible, since that class does not exist yet. It fell through to the verbatim copy, where the identifier arm renames the template's own name to the specialization's: `specialize TI<LongInt>`, i.e. `generic template TI not found`. With the parameter still in it the truncated parse says `expected '<' before ';'` instead -- two messages, one exclusion. FIXED by exempting a group that names the template currently being streamed; whether it COLLAPSES is still SpecializeToBuffer's decision against StreamedSpecCanonName, so the exemption recognises and does not decide. Fixture test_selfnesttype26, five rows. Moves tgeneric99.pp's wall from line 11 to line 25."
---

# The shape

```pascal
generic TTest<T> = class
type
  TTestT = specialize TTest<T>;      { names its OWN template }
end;
TI = specialize TTest<LongInt>;      { -> expected '<' before ';' }
```

fpc 3.2.2 compiles and runs it. This is how a generic container names its own
iterator or node type, and it is the first construct in `ugeneric99.pp`.

# Two probes located it, and neither is the obvious one

**A template carrying such a nested type but never SPECIALIZED parses fine.** So
nothing is wrong at capture; the failure is at specialization.

**The identical self-reference in a USE position works** — `Nxt: specialize
TTest<T>;` as a field compiled and ran correctly throughout, on this tree and on
pin v407. So it is not the self-reference. **It is the `=`.**

`NestedSpecGroup` refuses any group whose preceding token is `tkEq`:

```pascal
if (i > 0) and (TemplateTokens[ts + i - 1].Kind = tkEq) then Exit;
```

which is correct for `TEnumSpec = specialize TEnum<T>` — a declaration must MINT
a class, and that is the deferral machinery's job, not a collapse. It is wrong
for exactly one template: **the one being streamed.** Minting for a
self-reference cannot be done, because the class does not exist yet.

Unrecognised, the group reached the verbatim copy, and the identifier arm
immediately below renames the template's own name to the specialization's name.
`specialize TTest<LongInt>` became `specialize TI<LongInt>` →
`generic template TI not found`. With the parameter still in it, the truncated
parse reads `expected '<' before ';'`. **Two messages, one exclusion**, which is
why they read as unrelated.

# The fix

Move the name extraction above the `=` test and exempt the self-reference:

```pascal
if (i > 0) and (TemplateTokens[ts + i - 1].Kind = tkEq) and
   (not CaseEqual(nm, SpecializeTemplateName)) then Exit;
```

**Recognising the group is all it does.** Whether the group COLLAPSES is still
`SpecializeToBuffer`'s decision, comparing the group's canonical name against
`StreamedSpecCanonName` — the same key the alias-declared self-reference fix
added earlier the same day. The exemption widens what is *seen*, not what is
*decided*.

# The case that still fails, and it is NOT a residual

`TOtherArg = specialize TTest<Double>` inside `TTest<LongInt>` — the same
template at DIFFERENT arguments — is not a self-reference, does not collapse, and
still fails. **fpc 3.2.2 refuses that program too**: `Syntax error, "identifier"
expected but ";" found`. So a nested type may name its own template only at its
own arguments, and ours is a differing diagnostic on code the language does not
accept — deferred, not a gap.

The check therefore stays exact rather than being widened to the template NAME.
Widening it would accept what fpc refuses **and** collapse two different
specializations onto one class.

# Fixture

`test/test_a_nested_type_may_specialize_its_own_template.pas`
(`test_selfnesttype26`), five rows against fpc 3.2.2. Both broken spellings (via
the parameter, and at the template's own argument) because they produced the two
different messages; the USE-position control that locates the defect at the `=`;
and an other-template row that must keep MINTING, so a regression reads as this
change having widened rather than aimed.

That last row is built from INSIDE the template, which is where a nested minted
type is actually used.

**CORRECTED, and the correction is about my own measurement.** This section said
reaching a minted nested type through the OUTER specialization's name —
`TI.TMinted.Create` — was *"a separate gap (`class method not found (TMinted)`),
still open"*. **It is not, and this change is what closed it.** The failure was
real on the build BEFORE the fix, went into the fixture header and into this
ticket, and was already false by the time the fix compiled. Re-measured at
`cd30ba1c7d5d`: it compiles, runs, and matches fpc.

Worth naming beside the stale-binary class, because it is not that one: **a
stale MEASUREMENT — the tree moved under a note rather than under a run.** A
claim written mid-fix ages against the very binary being changed, and afterwards
it reads as though it had been checked. Re-measure every "still broken" note
AFTER the build that might have fixed it.

# Residual

`tgeneric99.pp` does not burn. Its wall moves from line 11 to line 25, which is
`t: specialize TTest<LongInt>.TTestClass` — a nested type reached THROUGH an
inline specialization. The file's remaining forms are unit- and class-qualified
`specialize` (`ugeneric99.specialize TTest<LongInt>`,
`TTestClass.specialize TTest<LongInt>`), which is a separate syntax and a
separate job.
