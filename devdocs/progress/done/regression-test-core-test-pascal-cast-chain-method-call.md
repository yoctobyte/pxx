---
prio: 70
track: P
status: done
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_pascal_cast_chain_method_call.pas red at 97f96a5cc766 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-27T03:27:54Z
- **Test source:** test/test_pascal_cast_chain_method_call.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_pascal_cast_chain_method_call.pas'` at 97f96a5cc7664fb2521b3fa5d0bd5de681b6c0d2

## Range
> **The named sha `97f96a5cc766` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `97f96a5cc766`, last good `67a83ca0bb63`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:100: error: "NewN": this value has no members (only records, classes, interfaces and variants do)
pascal26:100: error: expected comma or close parenthesis
(tail)
pascal26:100: error: "NewN": this value has no members (only records, classes, interfaces and variants do)
  near: q    cr  >>> NewN   
pascal26:100: error: expected comma or close parenthesis
  near:    cr  NewN >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-08-27 — resolved, commit c97fe56fa.

---

# Triaged and FIXED, 2026-08-27

**Cause: `acd14fe64`** (`fix(parser): route record-cast postfix walkers through
ParseClassRecordSelectors`), which is in the watcher's 2-commit range. Confirmed
by reading the change rather than by bisect: that commit removed the
`FindUField(...) < 0` guard on the record-cast rvalue arm so **every** `.name`
delegates to `ParseClassRecordSelectors`. Removing it was correct — the guard is
what made `TLongWordRec(l).b[0]` read a Byte at the record's width and return
18486690310128388 — but it changed which walker sees a chain that starts with a
field.

## Repro, reduced

```pascal
type
  TBaseClass = class of TBase;
  TRec = record cr: TBaseClass; n: Integer; end;
...
  writeln(TRec(q^).cr.NewN(3));   { pascal26: "NewN": this value has no members }
```

`p^.cr.NewN(3)` and `PRec(q)^.cr.NewN(3)` were unaffected — they take other
walkers. Only the record-cast spelling changed hands.

A `class of T` field records `REC_NONE` (the class lives in `UFldPtrElemRec`),
so after the `.cr` step `recId` is `REC_NONE`, `ci` stays -1, and every arm in
`ParseClassRecordSelectors` declined. The arm it needed did not exist there.

## Fix

`compiler/pasparser_lval.inc`, `ParseClassRecordSelectors` — a metaclass
receiver arm, placed before the `ci` computation so it sees the node first.

The three other walkers that can reach a metaclass value each already have this
arm, and all three go through the same shared pair: `NodeMetaclassCi` (the
five-spelling predicate) and `ParseMetaclassMemberTail` (the member parser).
This is the **fourth caller of that pair, not a fourth mechanism** — which is
the shape `devdocs/dev/root-cause-over-microfix.md` asks for, and the reason the
alternative (restoring the field guard) was not taken: it would have brought the
byte-width read back with it.

## Verified

- The reduced repro is byte-identical to FPC 3.2.2 across five rows, including
  the two cast spellings that already worked and `.ClassName` on the same field.
- `test/test_pascal_cast_chain_method_call.pas`: **9 / 9**, the two rows that
  were red (`recname-cast-classref`, and the `classref-op-through-cast` that
  followed it) included.
- `test/test_record_cast_indexed_field.pas` — the test `acd14fe64` added —
  still passes, so the fix does not undo what caused this.
- `gate.sh quick` GREEN; Pascal conformance 346/0/170/34, C conformance 220/0,
  fgl 7/7.
