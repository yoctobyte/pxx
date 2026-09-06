---
prio: 70
track: P
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
