---
slug: bug-p-a-field-selection-on-a-record-cast-is-not-parsed
track: P
prio: 35
type: bug
status: backlog
owner: unassigned
blocked-by: []
summary: "`TMethod(TSel(s.Pick)).Code` — a field selected directly off a cast to a RECORD type — is `expected ')' before '.'`. Identical on pinned, so not a regression, and identical for every receiver spelling, so nothing to do with method references: the cast expression simply cannot be a postfix base. Assigning the cast to a variable first and selecting off that works. FPC compiles the direct form. This is the spelling several tickets USE to demonstrate other bugs (the `TMethod(...).Code` idiom), so it is worth fixing for the leverage as much as for itself."
---

# A field selection directly on a record-typed cast is not parsed

## Measured — binary `490a2cfd83a2`, identical on `pinned`

```pascal
  writeln('inst ', PtrUInt(TMethod(TSel(s.Pick)).Code) <> 0);
```

```
pascal26:12: error: expected ')' before '.'
  near: ( s . Pick ) ) >>> . Code )
```

FPC 3.2.2 compiles the same program and prints `inst TRUE`.

**The two-step form works**, which is what isolates the postfix selection as the
variable rather than anything about the operand:

```pascal
  f := TSel(s.Pick);
  m := TMethod(f);
  writeln('via var ', PtrUInt(m.Code) <> 0);     { fine }
```

And it fails identically for every receiver spelling inside the inner cast —
instance variable, `Self`, bare name — so it is not about method references.
Reduced further, the subject is: a cast whose target is a RECORD type is not
accepted as the base of a `.field` postfix.

## Why it is worth more than its own repro

`TMethod(X).Code` is the standard way to look at a method pointer's two halves,
and it is the spelling **the tickets in this area use to state their own test
tables** — including
[[bug-p-a-parenless-method-reference-handles-two-of-four-receiver-spellings]],
whose table lists `TMethod(TSel(TSvc.Pick)).Code` as compiling. It does not, and
never did on any binary measured; that ticket's arms were really measured
through a variable. Anyone writing a gate for a method-pointer ticket will reach
for this spelling first and hit this, which is how one ticket's table came to
record a shape nobody had run.

(That ticket's row B is separately not a valid FPC program for a different
reason: `TSvc.Pick` on an INSTANCE method is rejected by FPC with *"Only class
methods ... can be referred with class references"*. The class-name receiver
needs a class method to be exercised honestly.)

## Gate

The repro above and its two-step control, plus one non-method record cast
(`TSomeRec(x).Field`) to establish whether the gap is method-pointer-specific or
general to record casts — that distinction is not measured yet and should be
before the fix is designed. Oracle: FPC.
