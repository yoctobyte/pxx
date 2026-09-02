---
track: P
prio: 10
summary: "OPEN DECISION, not settled (owner, 2026-09-02: *\"i've been pondering that and not came to a conclusive answer\"*). Track U. SizeOf(System.Integer) is 2 in fpc 3.2.2 and 4 here, because FPC's system unit declares Integer = smallint and the 4-byte Integer comes from the MODE redeclaring it -- so in FPC the qualifier selects a DIFFERENT type and System.Integer(x) truncates to 16 bits. pxx has one Integer and no System namespace. A programmer qualifying a name means THE Integer type, not "narrow this to 16 bits"; reproducing FPC would make an explicit qualification change the semantics of what it qualifies. Narrow: System.LongWord, System.Boolean and System.Char all agree; Integer is the one name FPC's mode shadows."
status: backlog
---

# `System.Integer` is SmallInt in FPC, LongInt in pxx

- **Type:** compat (FPC parity) — tag: compat
- **Track:** P — Pascal frontend
- **Found:** 2026-08-20 (frank1-ACP), while adding the `System.`-qualified TYPE
  parse for [[feature-pascal-corpus-generics]].

## The divergence

```pascal
{$mode objfpc}
WriteLn(SizeOf(System.Integer), ' ', SizeOf(Integer));
```

fpc 3.2.2 x86-64 prints `2 4`. pxx prints `4 4`.

FPC's `system` unit really declares `Integer = smallint`; the 4-byte `Integer`
every objfpc program uses comes from the *mode*, which redeclares it. So in FPC
the qualifier picks a DIFFERENT TYPE, and `System.Integer(x)` is a 16-bit
truncating cast. pxx has one `Integer` and no System namespace to differ from —
`System.X` is stripped and resolves to the builtin (see `EatSystemQualifier`).

`SizeOf(System.LongWord)`, `System.Boolean`, `System.Char` etc. agree in both;
`Integer` is the one name FPC's mode shadows.

## Does it matter

Only for a value outside -32768..32767 cast through the qualified spelling. The
one real-world use found so far is rtl-generics' `TCompare.UInt8`:

```pascal
Result := System.Integer(ALeft) - System.Integer(ARight);
```

whose operands are bytes, so both compilers give the same answer.

## Why this is compat and not a `bug-`

It is a *silent* difference in a cast width, which is the shape that normally
gets promoted out of the compat tag. It stays here because the promotion rule is
about pxx computing a wrong value for code whose meaning is unambiguous — and
here FPC's own answer is the surprising one (a program written against
mode-objfpc's `Integer` gets 16 bits it did not ask for). Reproducing it would
mean giving pxx a second `Integer` type reachable only through a namespace it
otherwise does not have. Prio is low deliberately; raise it if a corpus program
is found that truncates differently under the two compilers.

## If it is ever done

`EatSystemQualifier` is the single place that strips the qualifier, so a
System-scope type table would hook in there — not in the two dispatches that
call it.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick`. Coverage today:
`test/test_fpc_compat_batch.pas` asserts the `System.LongWord` identities and
carries a comment pointing here.

## OPEN DECISION 2026-09-02 — moved OUT of `known-incompat/`, deliberately

This spent about an hour in `known-incompat/` and should not have. That folder's
entry test requires the behaviour to be **CHOSEN**, and the owner's position is
that he has been pondering it and *"not came to a conclusive answer"*. Filing an
undecided question as a settled one is exactly the false confidence the folder
was created to prevent, so it comes back out. **Bending the rule the first time
it was inconvenient would have made the folder worthless.**

Track U, and low: the owner also notes the impact is very limited.

### The measurement, which is not in dispute

```pascal
{$mode objfpc}
WriteLn(SizeOf(System.Integer), ' ', SizeOf(Integer));
```
fpc 3.2.2 x86-64 prints `2 4`. pxx prints `4 4`.

FPC's `system` unit really declares `Integer = smallint`; the 4-byte `Integer`
every objfpc program uses comes from the MODE redeclaring it. So in FPC the
qualifier selects a DIFFERENT TYPE and `System.Integer(x)` is a 16-bit
truncating cast. pxx has one `Integer` and no `System` namespace to differ from.
Narrow: `System.LongWord`, `System.Boolean`, `System.Char` all agree — `Integer`
is the one name FPC's mode shadows.

### The fork

**Keep ours.** A programmer writing `System.Integer` is qualifying a name to be
unambiguous; they mean *the* Integer type, not "narrow this to 16 bits". Matching
FPC makes an explicit qualification change the semantics of what it qualifies.

**Match FPC.** Code ported from FPC that writes `System.Integer` deliberately —
if any exists — silently gets a 32-bit value where it expected truncation. This
is the arm nobody has evidence for.

### What would settle it without a decision

Real source that writes `System.Integer` *because* it wants the 16-bit
truncating cast. Nobody has looked for one. If it does not exist, "keep ours"
follows from CLAUDE.md's *ask what the source MEANT* and this stops being a U
question at all.
