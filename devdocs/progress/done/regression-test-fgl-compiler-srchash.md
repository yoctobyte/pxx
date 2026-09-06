---
prio: 70
track: P
status: done
owner: frankS
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/run_fgl_corpus.sh ./compiler/pascal26 library_candidates/fpc-rtl/rtl/objpas`. The job's own `src` (`tools/compiler_srchash.sh`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-fgl#src:tools/compiler_srchash.sh at 3b13f585f5f4 in step 2/2, `tools/run_fgl_corpus.sh ./compiler/pascal26 library_candidates/fpc-rtl/rtl/objpas` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T00:21:35Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/run_fgl_corpus.sh`.
  ```
  tools/run_fgl_corpus.sh ./compiler/pascal26 library_candidates/fpc-rtl/rtl/objpas
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-fgl#src:tools/compiler_srchash.sh'` at 3b13f585f5f4755371f7a45c73a3ec9270dcbc95

## Range
> **The named sha `3b13f585f5f4` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `3b13f585f5f4`, last good `5daad03f50d7`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL ifclist.pas -- compile error:
pascal26:892: error: undefined variable (IFoo)
FAIL list_int.pas -- compile error:
pascal26:981: error: undefined variable (TFPGListEnumeratorSpec)
FAIL list_str.pas -- compile error:
FAIL objectlist.pas -- compile error:
pascal26:892: error: undefined variable (TThing)
(tail)
self-host fixedpoint: verified — 1 round(s), 36d5ec10a24c (stamp read back; sources match it)
PASS fpslist.pas
FAIL ifclist.pas -- compile error:
    pascal26:987: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:1124: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:1248: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:892: error: undefined variable (IFoo)
FAIL list_int.pas -- compile error:
    pascal26:987: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:1124: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:1248: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:981: error: undefined variable (TFPGListEnumeratorSpec)
FAIL list_str.pas -- compile error:
    pascal26:987: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:1124: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:1248: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:981: error: undefined variable (TFPGListEnumeratorSpec)
PASS map_int.pas
PASS map_str.pas
FAIL objectlist.pas -- compile error:
    pascal26:987: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:1124: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:1248: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:892: error: undefined variable (TThing)
test-fgl: 3 pass, 4 fail, 0 skip (of 7)
test-fgl: FAILURES: ifclist.pas(compile) list_int.pas(compile) list_str.pas(compile) objectlist.pas(compile)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## 2026-09-06 (frankA) — bisected to ONE commit, and reduced to two files with no corpus

Re-laned **T → P**: the fallback lane was correct as a fallback and wrong as a
finding. This is generic scope, not tooling.

### The split, measured at HEAD

```
PASS  fpslist   map_int   map_str
FAIL  ifclist   list_int  list_str  objectlist        3 pass / 4 fail of 7
```

**The "builtin vs file-declared type argument" hypothesis is dead**: `list_int`
and `list_str` specialise on `Integer` and `String` — builtins — and fail, while
`map_int`/`map_str` specialise on the same builtins and pass. The split is by
which fgl class the driver uses, and the two failure SITES say why:

| site | fgl.pp | source | reported |
|---|---|---|---|
| A | `:892` | `Result := T(FList.Items[FPosition]^);` | `undefined variable (IFoo)`, `(TThing)` |
| B | `:981` | `Result := TFPGListEnumeratorSpec.Create(Self);` | `undefined variable (TFPGListEnumeratorSpec)` |

Face A names the **actual type argument**; face B names a **nested
specialisation alias** (`TFPGListEnumeratorSpec = specialize
TFPGListEnumerator<T>`, fgl.pp:143). One mechanism, two observables: **a TYPE
NAME in expression position inside a generic method body is resolved as a
VARIABLE.**

### Bisect: `a0780b56d`, and its parent is clean

Not an interval — a direct A/B on one commit, same corpus, same runner:

```
5daad03f50d7  (last good)                                7 pass 0 fail
721f8d534     (a0780b56d^)                               7 pass 0 fail
a0780b56d     fix(P): a generic template's method body
              parses as its DECLARING unit                3 pass 4 fail
```

### THE PART THAT UNBLOCKS ANYONE WITHOUT THE CORPUS

`library_candidates/fpc-rtl` is gitignored and is on **one checkout of the
fleet**, so this red serialised on a corpus nobody else has. Both faces reduce
to a **unit plus a program, no corpus, ~15 lines each**, and both are accepted
and run by fpc 3.2.2.

**Face B** — `undefined variable (TEnumSpec)`:

```pascal
unit gunit;                                 program guse;
{$mode objfpc}{$H+}                         {$mode objfpc}{$H+}
interface                                   uses gunit;
type                                        type
  generic TEnum<T> = class                    TThing = class n: Integer; end;
    v: T;                                     TListThing = specialize TList<TThing>;
  end;                                      var a: TListThing;
  generic TList<T> = class                  begin
  public                                      a := TListThing.Create;
    Type                                      WriteLn('U built');
      TEnumSpec = specialize TEnum<T>;      end.
    function GetEnumerator: TEnumSpec;
  end;
implementation
function TList.GetEnumerator: TEnumSpec;
begin
  Result := TEnumSpec.Create;
end;
end.
```

**Face A** — same two-file shape, `undefined variable (TThing)`, from a generic
whose only body is `function TEnum.GetCurrent: T; begin Result := T(p^); end;`
specialised on a class declared in the PROGRAM.

**THE SEPARATE UNIT IS THE LOAD-BEARING VARIABLE, and I nearly threw it away.**
Both faces written as a SINGLE FILE compile and run clean under pxx — I built
those first, watched them pass, and was one step from reporting that the
reduction did not reproduce. The commit's own subject names what I had removed:
*a generic template's method body parses as its DECLARING unit*. When a
minimisation drops the thing the suspect commit is about, the minimisation is
what is wrong.

The pin answers face B differently again (a duplicate-definition warning on
`TEnumSpec.GetCurrent`, not a refusal), so the reduction is not exercising some
older latent gap.

### Not taken

Cross-unit generic scope is another agent's group and this is a landed commit,
not in-flight. Handing over the bisect and the reductions rather than fixing,
so nobody works the same question twice. The corpus half is done: everything
above is reproducible without `library_candidates/`.

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

## 2026-09-06 (frankS) — fixed at `05ae03c3d`, confirmed 7/7

One cause with the sibling row, established by control rather than by
narrowing: reverted the suspect hunk of `a0780b56d` ALONE, rebuilt, **confirmed
the binary sha moved (`509821fe8a97 -> b134a22c70e9`)** so a no-op build could
not read as an exculpation, and the failure vanished; restored it and it came
back.

**Mechanism.** `a0780b56d` made a template's method body parse as the unit that
DECLARED the template — correct, and the reason a private helper beside the
template now wins over a same-named routine in the program. But a
specialization's SYNTHESIZED rows are minted where the specialization is
WRITTEN: the class minted for a nested `TEnumSpec = specialize TEnum<T>`, and
the substituted type argument itself. Both are the importing program's rows, and
`ClassRowVisibleHere` vetoes exactly those —

    if (CurrentUnitIdx >= 0) and (UClsUnitIdx[ci] < 0) then hidden

— which is right on its own terms and cannot be dropped, because ignoring it
SEGFAULTED (a NilPy `class Text` capturing the RTL's file record). Two correct
rules colliding: becoming the declaring unit reclassified the template's own
materialised members as "the program's declarations".

The four failing drivers are two faces of that one table, not two mechanisms:
`list_int`/`list_str` fail on the nested specialization, `objectlist`/`ifclist`
on the type argument.

**Fix.** Remember the scope the specialization was written in
(`SpecBodyHostUnitIdx`; sentinel `-2`, because `-1` is a real scope and is
exactly the one it must tell apart from unset) and let that veto reach it. The
shadowing half is untouched: `FindUClass` tries `CurrentUnitIdx` rows first and
returns on a hit, so a same-named class in the declaring unit still wins — and
`a0780b56d`'s own six rows, including the two that exist to catch a fix that
merely hides the program's copy, are unchanged.

**Verification.** `test-fgl` at `2ff441dce`: **7 pass, 0 fail, 0 skip of 7**,
exit 0, run by frankA with `05ae03c3d` confirmed an ancestor by
`merge-base --is-ancestor` rather than by timestamp. All four previously-failing
drivers pass. Two independently-built corpus-free reductions (frankA's and mine,
from different models) also pass, one per face.

Guarded corpus-free as `test_gen_nestedspec26`, because the arm that caught this
skips on any checkout without the FPC RTL source: four shapes — nested
specialization in the body, a SECOND class whose nested type has the same name,
a program-declared class as type argument named by a cast (`fgl.pp:892`
`T(FList.Items[FPosition]^)`), and an interface type argument. All four
reproduce with the fix disabled.

Re-laned P, which the auto-file's own fallback note asked for.
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 35ce57f47.
