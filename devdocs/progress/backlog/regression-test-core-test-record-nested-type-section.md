---
prio: 70
track: P
---

> **Track P by measurement 2026-09-06, not by the auto-guess and not by the job's
> name — but the DEFECT is in `compiler/symtab.inc`, which is A's shared
> internals.** Edit it and say what you are touching, per CLAUDE.md; that is
> telling, not asking.
>
> **Correcting this seat's first version of this line, which had it backwards:**
> `FindNestedType` (`compiler/pasparser_class.inc:159`) is the path that still
> WORKS — it is why `TOuterR.TSubRec` on the adjacent line resolves. The failing
> path is the ALIAS TABLE in `symtab.inc`. (frankB, who read the diff.)

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_record_nested_type_section.pas /tmp/test_rnts26`, which names `test/test_record_nested_type_section.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_record_nested_type_section.pas at 6e00f29b0d93 in step 1/2, `./compiler/pascal26 test/test_record_nested_type_section.pas /tmp/test_rnts26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-05T22:09:44Z
- **Test source:** test/test_record_nested_type_section.pas tools/expect_same.sh +1
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_record_nested_type_section.pas`.
  ```
  ./compiler/pascal26 test/test_record_nested_type_section.pas /tmp/test_rnts26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_record_nested_type_section.pas'` at 6e00f29b0d93c1de28a173ae8867c7f08dd0b3e3

## Range
> **The named sha `6e00f29b0d93` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `6e00f29b0d93`, last good `10fa2709d830`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:87: error: unknown type: TAlias
(tail)
pascal26:87: error: unknown type: TAlias
  near: TSubCls ; a : TOuterR . >>> TAlias ; cl 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## TRIAGED AND NARROWED 2026-09-06 — live at HEAD, regression confirmed against the pin

**Instrument:** `compiler/pascal26` rebuilt at HEAD `ef7b32135`, `converged after
2 round(s)` (the recompute verb, not the stamp path), `sha256
1e6f67eb4e67343ad727219a9e4dfbf9dfde272772b5921f67369f5133d2d283`. Exit codes read
without a pipe.

**Still failing at HEAD**, so the 6-commit advance did not fix it:

```
$ ./compiler/pascal26 test/test_record_nested_type_section.pas /tmp/test_rnts26
pascal26:87: error: unknown type: TAlias
  near: TSubCls ; a : TOuterR . >>> TAlias ; cl
rc=1
```

Line 87 is `a: TOuterR.TAlias;`. **Lines 85 and 86 — `t: TOtherR.TSubRec` and
`c: TOuterR.TSubCls` — were accepted**, because the compiler reached 87 to fail
there. So nested records and nested classes still resolve through a qualified name.

### The boundary, three minimal programs

| probe | shape | HEAD | pinned |
| --- | --- | --- | --- |
| r1 | `TR = record type TAlias = Integer; …`, then `var a: TR.TAlias` | **rc=1** `unknown type: TAlias` | rc=0 |
| r2 | same in a **class** — `TC = class type TAlias = Integer; end` | **rc=1** `unknown type: TAlias` | rc=0 |
| r3 | nested **record** — `TR = record type TSub = record … end`, `var s: TR.TSub` | rc=0 | rc=0 |

> **A qualified nested TYPE ALIAS is unresolvable at HEAD, in BOTH records and
> classes. A qualified nested record still resolves. The pin accepts all three.**

So this is a real regression rather than a pre-existing gap, it is **not** specific
to records despite the test's name, and it is **not** about nested types in general
— it is about an ALIAS declared in a nested `type` section.

### The range, and the one buildable commit in it

The watcher's range is 1 commit. `6e00f29b0d93` is a `tstate` commit and touches no
buildable file. The only buildable commit between `10fa2709d830` and it is:

**`c01eb17a8` — `fix(P): a nested pointer alias belongs to the type that declared
it`**, touching `compiler/pasparser_decl.inc`, `compiler/symtab.inc`,
`compiler/defs.inc`, closing
`bug-p-a-pointer-to-a-generic-nested-type-is-shared-across-specializations` and
adding `test/test_nested_pointer_alias_is_scoped_to_its_owner.pas`.

**Authored in the frankD checkout** (`git -C /home/neo/frankD reflog | grep
'^c01eb17a8 commit'`, one hit), session `01SqXmLQupsKseAhSMny3QkK`. That names the
tree a commit was created in, not who wrote it — corroborate before treating it as
authorship.

**The mechanism is plausible and is NOT established here.** `FindNestedType`'s own
forward declaration (`compiler/compiler.pas:66`) records that
`symtab.inc`'s `ResolvePendingPointerAliases` calls it *"so a deferred `^T` inside
a class body resolves to THAT body's T"* — i.e. the fix in range is precisely about
how a nested alias is claimed by its owner. **A plausible explanation for a red is
the expensive failure mode; this is a hypothesis with a 1-commit range behind it,
not a diagnosis.** Reverting to check is the measurement nobody has taken.

## THE DIAGNOSIS — frankB, 2026-09-06, from reading the diff

**`AliasVisibleHere` (`compiler/symtab.inc:256`) has three arms and none of them is
the QUALIFIED spelling:** owner unset, `ParsingClassBodyCi`, `MethImplOwnerCi`.

`TAlias = Integer` declared in `TOuterR`'s nested `type` section **now carries an
owner**, and `a: TOuterR.TAlias` at unit level has **neither scope global set** — so
the alias is invisible to a caller that named its owner *explicitly*. The two
arms that exist cover being INSIDE the body and being in an out-of-line method
implementation; nobody covers naming the owner from outside.

`TOuterR.TSubRec` on the adjacent line works because **nested class-like types go
through `FindNestedType`, not through the alias table.**

> **The two nested-type kinds now disagree about whether a qualified name is
> admissible** — and that is the fix's shape, whatever form it takes.

This seat's boundary probes agree and extend it one step: the same failure occurs
in a **class** (`TC = class type TAlias = Integer; end`, then `var a: TC.TAlias`),
so it is **not record-specific** despite the test's name.

## ATTRIBUTION — corrected once already, so here is the evidence

`c01eb17a8` is **frankD's**, session `01SqXmLQupsKseAhSMny3QkK`. It was routed to
frankS by one peer in good faith; that was wrong. Four instruments, failing
differently:

- session trailer `01SqXmLQ…` vs frankS's own `01BkWb7U1rL45indZovziXzg` on `8aebcfe72`
- `git -C /home/neo/frankS reflog | grep -c '^c01eb17a8 commit'` → **0**; frankD → **1**
- the same session authored `7f8f97ec6` (the escaped-probe revert) and `2e3922d14`, both frankD's and both self-reported
- frankS stated directly, hours earlier, that it does not hold the nested-pointer work

**`owner:` is deliberately still unset.** Naming the author is attribution; setting
the field would read as an assignment. frankB has offered to take it if frankD has
moved on.

## GATE NOTE

frankB's observation, and it explains why this reached the tip: **`test-core` is not
in the quick tier.** The gate that ran was correct about what it measured.
