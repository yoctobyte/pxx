---
slug: bug-p-a-field-selection-on-a-record-cast-is-not-parsed
track: P
prio: 35
type: bug
status: rejected
owner: frankA
blocked-by: []
summary: "REJECTED 2026-09-04 (frankA): false premise. A cast to a record type IS accepted as a postfix base -- eight shapes measured, all matching fpc 3.2.2, including this ticket's own line. The real content was that `TMethod` was not a builtin type, and the reduction was taken from the SECOND error of a two-error batch. `TMethod` landed at `31f8b11bf` and the exact spelling now compiles at HEAD with no local declaration. Original report follows. `TMethod(TSel(s.Pick)).Code` — a field selected directly off a cast to a RECORD type — is `expected ')' before '.'`. Identical on pinned, so not a regression, and identical for every receiver spelling, so nothing to do with method references: the cast expression simply cannot be a postfix base. Assigning the cast to a variable first and selecting off that works. FPC compiles the direct form. This is the spelling several tickets USE to demonstrate other bugs (the `TMethod(...).Code` idiom), so it is worth fixing for the leverage as much as for itself."
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

---

## 2026-09-04 (frankA) — REJECTED: the reduction came from the second error in a batch

This ticket's reduction is *"a cast whose target is a RECORD type is not
accepted as the base of a `.field` postfix"*. **That is false, and was false
when filed.** Eight record-cast shapes, all compiling and all matching
fpc 3.2.2, on this binary and on `pinned`:

| shape | |
| --- | --- |
| `TRek(q).a` cast of a variable | ok |
| `TRek(o.inner).a` cast of a field | ok |
| `TRek(TQ(z)).a` cast of a cast | ok |
| `TRek(TQ(TZ(z))).a` double-nested | ok |
| `TRek(G).a` cast of a call result | ok |
| `TRek(p^).a` cast of a deref | ok |
| `TRek(arr[0]).a` cast of an element | ok |
| `TMethod(TSel(@s.Pick)).Code` **this ticket's own line** | ok |

### What actually happened

`TMethod` was not a builtin type, and on `pinned` the compiler emitted a
**batch**:

```
pascal26:12: error: undefined variable (TMethod)      <- the cause
pascal26:12: error: expected ')' before '.'           <- what this ticket quoted
```

The second line is a consequence of the first: with `TMethod` unresolved,
`TMethod(...)` is not a cast, so the `.Code` postfix has no base to attach to.
Declaring `TMethod = record Code, Data: Pointer; end;` in the program made the
ticket's exact line print `inst TRUE`, matching FPC — that was the discriminating
experiment, and it was one edit.

The current binary prints only the first error (recovery got shorter since), so
**the quoted diagnostic no longer reproduces at all**, which is itself the tell.

`TMethod` became a builtin at `31f8b11bf` (frankH). Re-measured at HEAD after
that landed, with no local declaration: compiles, prints `inst TRUE`, FPC agrees.

### Two claims in the body that do not survive

- *"it fails identically for every receiver spelling ... so it is not about
  method references"* — true, and for the reason nobody checked: it failed for
  every spelling because it failed for every PROGRAM mentioning `TMethod`.
- The body says
  [[bug-p-a-parenless-method-reference-handles-two-of-four-receiver-spellings]]
  *"records a shape nobody had run"*. That accusation was derived from the same
  misreading and **has not been re-measured** — frankH holds that ticket and was
  paused before getting to it. It is not settled by this rejection either way.

The gate this ticket asked for — *"one non-method record cast (`TSomeRec(x).Field`)
to establish whether the gap is method-pointer-specific or general to record
casts — that distinction is not measured yet"* — is the measurement that
rejected it. It was the right thing to ask for.

**Rejected, not moved to `known-incompat`:** nothing here is a divergence we
chose. The report was wrong about the mechanism, which is what `rejected/` is
for.
