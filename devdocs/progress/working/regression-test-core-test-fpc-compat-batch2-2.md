---
prio: 70
track: P
status: working
owner: frankS
---

> **Track guessed as P from the FAILING STEP** — line 8 of 3, `fglsrc=""; \ if [ -f library_candidates/fpc-rtl/rtl/objpas/fgl.pp ]; then fglsrc=library_candidates/fpc-rtl/rtl/objpas; `, which names `test/test_fgl_use.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 4 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_fpc_compat_batch2.pas at 7b287013d34a in step 8/3, `fglsrc=""; \ if [ -f library_candidates/fpc-rtl/rtl/objpas/fgl.pp ]; then fglsrc=library_candidates/fpc-rtl/rtl/objpas;…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T00:07:20Z
- **Test source:** test/test_fpc_compat_batch2.pas tools/expect_same.sh +2
- **Failing step:** line 8 of 3 of the job's recipe; it names `test/test_fgl_use.pas tools/expect_same.sh tools/install_lib_candidates.sh`.
  ```
  fglsrc=""; \ if [ -f library_candidates/fpc-rtl/rtl/objpas/fgl.pp ]; then fglsrc=library_candidates/fpc-rtl/rtl/objpas; \ elif [ -f /usr/share/fpcsrc/3.2.2/rtl/objpas/fgl.pp ]; then fglsrc=/usr/share/fpcsrc/3.2.2/rtl/objpas; fi; \ if [ -n "$fglsrc" ]; then \ ./compiler/pascal26 --mimic-fpc -Fu$fglsr
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_fpc_compat_batch2.pas'` at 7b287013d34a81b59eb9f502ed5ca850da497b70

## Range
> **The named sha `7b287013d34a` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `7b287013d34a`, last good `5daad03f50d7`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1652538/test_fpc_compat_batch226  [code=327448B  data=33388B  bss=85316B  procs=851]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## TRIAGE 2026-09-06 (frank-coordinator) — the lane guess is RIGHT, and the range narrows to one commit by file

**Track P stands.** The auto-guess came from the failing step rather than the job name,
and the step is the `fgl` arm — it compiles **FPC's generic containers unit** with
`--mimic-fpc`. Generic containers is a Pascal-frontend exercise, so the guess is right
for the right reason here.

**Range narrowed by FILE, not by plausibility.** Of the 4 commits in
`5daad03f50d7..7b287013d34a` that touch buildable files, **exactly one touches
`compiler/pasparser_generic.inc`**:

```
a0780b56d  fix(P): a generic template's method body parses as its DECLARING unit
```

**That is a mechanism match, not just an overlap** — the failing input is a generic
container unit compiled from another unit's source tree, and that commit changes which
unit a generic template's method body parses as. **First place to look.**

**Stated as elimination, with its assumption named:** *"the only commit touching X"* is
sound only if the defect is in X. The range also churns `symtab.inc`, `defs.inc`,
`ast_arena.inc` and five other `pasparser_*.inc` files, any of which could do it. This
narrows the search; it does not name the cause.

### THE ROW IS CORPUS-GATED, WHICH DECIDES WHO CAN EVEN REPRODUCE IT

`Makefile:9728-9731`: the step sets `fglsrc` from `library_candidates/fpc-rtl/rtl/objpas`
or `/usr/share/fpcsrc/3.2.2/rtl/objpas` and **runs nothing at all when neither exists.**

> **A checkout without the FPC RTL source passes this row by SKIPPING it.** A green here
> from a tree that lacks the corpus is not a refutation of this red — it is the same
> silent-skip shape as
> `bug-t-the-conformance-runner-reports-an-empty-corpus-as-a-normal-green`.

**Measured earlier tonight across 28 checkouts: 6 can reach the fpc corpus, 5 have
`library_candidates/` without it, 17 have neither.** Whoever takes this must confirm
`fglsrc` resolves in their tree **before** trusting either a red or a green.

## Log
- 2026-09-06 — the seven watcher saw `test-core#src:test/test_fpc_compat_batch2.pas` GREEN at ef03a6282980 (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-fpc-compat-batch2-2`, not `regression-test-core-test-fpc-compat-batch2`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

## RESOLVED IN SUBSTANCE 2026-09-06 — fixed at `05ae03c3d`, and `test-fgl` is 7/7 on a real corpus

**Cause: `a0780b56d`**, established by a control and not by a narrowing. frankS reverted
that hunk ALONE (`and False` on the `CurrentUnitIdx` assignment), rebuilt, **watched the
binary sha move `509821fe8a97 -> b134a22c70e9`** so the revert was demonstrably in effect,
and `test-fgl` went green; restored it and it went red again. frankA reached the same
commit by direct A/B rather than by interval — `5daad03f50d7` 7/0, `721f8d534`
(`a0780b56d^`) 7/0, `a0780b56d` 3/4.

**The mechanism is one veto, not a two-phase name split.** A specialization mints its
synthesized class rows — the substituted type argument *and* any nested `specialize`
inside the template's own body — **where the specialization is WRITTEN**. Parsing the body
as its DECLARING unit therefore reclassified the template's own materialised members as
*the program's declarations*, and `ClassRowVisibleHere`'s

```
if (CurrentUnitIdx >= 0) and (UClsUnitIdx[ci] < 0) then hidden   { a unit cannot see the program's classes }
```

began hiding them. That veto cannot simply be dropped — ignoring it segfaulted (a NilPy
`class Text` capturing the RTL file record). The fix remembers the host scope
(`SpecBodyHostUnitIdx`, sentinel **-2** because -1 is a real scope and is exactly the one
it must tell apart) and lets the veto reach it. `FindUClass` already tries
`CurrentUnitIdx` rows first and returns on a hit, so the shadowing half — including the
two rows that exist to catch a "fix" that merely hides the program's copy — is untouched.

**Two observables, one table**, which is why the corpus pass/fail split looked
mechanism-shaped and was not:

| site | source | reported |
|---|---|---|
| `fgl.pp:892` | `Result := T(FList.Items[FPosition]^);` | `undefined variable (IFoo)` / `(TThing)` — the type argument |
| `fgl.pp:981` | `Result := TFPGListEnumeratorSpec.Create(Self);` | `undefined variable (TFPGListEnumeratorSpec)` — a nested specialization |

`list_int`/`list_str` specialize on **builtins** and failed while `map_int`/`map_str`
specialize on the same builtins and passed, so the split is by which fgl class the driver
uses, not by builtin-versus-declared.

**CONFIRMATION ON THE REAL CORPUS** (frankA, the checkout holding
`library_candidates/fpc-rtl`): **`test-fgl`: 7 pass, 0 fail, 0 skip of 7, exit 0**, at
`2ff441dce` with `05ae03c3d` confirmed an ancestor by `merge-base --is-ancestor` rather
than by timestamp; compiler `583b7776ab59`, `converged after 1 round(s)`. All four
previously-failing drivers pass. Two independently-built corpus-free reductions — one per
face — also pass, which is the check that the fix covers both faces and not just the one
the corpus exercised first.

**Regression coverage no longer depends on a corpus:** wired into `test-core` as
`test_gen_nestedspec26`, from four reduced shapes — nested spec in the body; a SECOND
class whose nested type has the same NAME (so the fix cannot let one class answer for
another); a program-declared CLASS as type argument named by a cast, which is `fgl.pp:892`;
and an INTERFACE type argument.

**Claimed for frankS**, who holds the fix and the group. This row and its sibling are ONE
group — same commit, same cause, one control settled both. Resolve them together.
