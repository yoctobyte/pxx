---
prio: 70
track: P
status: working
owner: frank-rust
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_methodptr_nil_assign.pas red at dc798834ba33 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T18:15:54Z
- **Test source:** test/test_methodptr_nil_assign.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_methodptr_nil_assign.pas'` at dc798834ba33aee86e1af089a8e2579da57087e7

## Range
> **The named sha `dc798834ba33` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `dc798834ba33`, last good `fc9e258e1b71`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:46: error: incompatible types: cannot assign Pointer to record
pascal26:51: error: incompatible types: cannot assign Pointer to record
pascal26:58: error: incompatible types: cannot assign Pointer to record
(tail)
pascal26:46: error: incompatible types: cannot assign Pointer to record
pascal26:51: error: incompatible types: cannot assign Pointer to record
pascal26:58: error: incompatible types: cannot assign Pointer to record

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


---

# DIAGNOSED — and the track guess was wrong: this is `ir.inc`, Track A

Cause bisected **by building**, not by reading:

| binary | `test_methodptr_nil_assign.pas` |
| --- | --- |
| `fa8f2424d^` | **compiles** |
| `fa8f2424d` | **FAILS**, all three lines |

The only other buildable commit in Track T's range is `9588c8535` (the
string-literal perf change) and it is *newer*, so the range collapses to one
commit.

## The mechanism

`fa8f2424d` — *"the assignment type check never RAN for five of six lvalue
shapes"* — is a real fix and its diagnosis was right. It added `AN_INDEX` /
`AN_FIELD` / `AN_DEREF` to `AssignSideKind` (`ir.inc:87`). The `AN_IDENT` arm it
was modelled on carries **two** bails against types that are *spelled* `tyRecord`
without being records:

```pascal
  if SymProcSig[si] >= 0 then Exit;    { procvar: the kind is the RESULT's }
  ...
  if ... UClsIsInterface[...] then Exit;   { an interface is a 16-byte fat pointer }
```

The three new arms inherited the **interface** bail and not the **procvar** one.
A method pointer is the second thing spelled `tyRecord` that is not a record — it
is the 16-byte `{Code, Data}` layout — and `nil` is an `AN_INT_LIT` 0 typed
`tyPointer`. So a method-pointer FIELD or ELEMENT now meets the record rule head
on and `OnClick := nil`, which is how you detach an event handler, is refused.

That is the commit's own note one line further down, about the other member of
the same class: *"the kind is not a reliable description here, which is exactly
what this function is for."* There were two such types; the new arms learned one.

`ev := nil` on a plain variable is unaffected, which is what makes the shape
legible: the variable arm has the procvar bail, the element/field arms do not.

## The fix

One line in the arm `fa8f2424d` added, the exact mirror of the interface bail
beside it:

```pascal
  if (rec = MethodPtrRecId) and (rec <> REC_NONE) then Exit;
```

The more literal analogue of the `AN_IDENT` arm would be per-shape —
`UFldProcSig` for a field, the array's element signature for an index, nothing
obvious for a deref — three lookups where the destination's record id answers all
three uniformly. Which of the two is wanted is a Track A call and is with frankA,
along with clearance to write it: `ir.inc` is not this session's lane, and frankA
authored the change.

## No new test is needed, and that is worth saying explicitly

`test/test_methodptr_nil_assign.pas` already has the property a fix here must be
measured against. It covers **four** shapes — a variable, a FIELD (`c.OnHit :=
nil`, which is what event-handler code actually writes), an ARRAY ELEMENT, and a
`var` parameter nilled by the callee — and each is **re-armed and CALLED first**,
so it proves the slot was live before it was cleared rather than proving
`Assigned()` is uniformly false. Red now, green when the bail is restored: the
existing test going from red to green IS the measurement.

## Provenance

Bisect and diagnosis at HEAD `38a9803b7`; both bisect binaries were fresh
self-host fixedpoints of the named tree, not the seed. Repro is the ticket's own
`testmgr` line, or simply
`./compiler/pascal26 test/test_methodptr_nil_assign.pas /tmp/x`.
