---
prio: 70
track: P
status: done
owner: frankA
---

> **Re-laned T → P on 2026-08-30** by the Track T agent (face 2). The `track: T`
> the watcher stamped was its no-lane-inferable FALLBACK, not a finding. The
> defect is in the Pascal frontend's generic sweep (`pasparser_generic.inc`);
> Track T owns the tool, never the bug. Triage below; nothing here is a fix.

# regression: `^specialize T<Args>` in a TYPED CONST no longer parses (tgeneric87)

- **Type:** regression. Auto-filed by the Track T watcher (host seven) as
  `test-pascal-conformance#shard0/6` red; triaged and root-caused 2026-08-30.
- **Found:** 2026-08-29T21:47:17Z · **Triaged:** 2026-08-30
- **Culprit:** `f12a62815` *fix(P): a generic argument that is another
  template's parameter is not concrete* (2026-08-29) — in range, see below.
- **Still present at HEAD** `6461c9bfc0c3`, in the successor mechanism
  `CollectSpecializationBoundNamesFromTokens` (`6019d980f`, which is NOT in the
  range — it inherited the discriminator rather than introducing it).

## Reproduced at HEAD

Binary built in-tree at HEAD `6461c9bfc0c3`: `converged after 1 round(s)`,
self-host fixedpoint verified, sha256 `1055347eb44a` (≠ pinned).

```
$ ./compiler/pascal26 a_const.pas
Expected: =, but got: TTest (Kind: 1, Line: 4)
pascal26:4: error: unexpected token
  near:  const P   specialize >>> TTest  LongInt
```

Minimal repro — 7 lines, no unit, no corpus:

```pascal
program a_const;
type generic TTest<T> = record x: T; end;
const
  P: ^specialize TTest<LongInt> = Nil;    { <-- fails }
begin
  if P = Nil then writeln('ok');
end.
```

The **only** difference that matters is the `=`. Both of these compile clean at
the same binary:

| form | verdict |
| --- | --- |
| `const P: ^specialize TTest<LongInt> = Nil;` | **FAIL** — `Expected: =, but got: TTest` |
| `var P: ^specialize TTest<LongInt>;` | ok |
| `var P: ^specialize TTest<LongInt>;` + an unrelated `const K = 1;` | ok |

## Root cause — the header discriminator is false for a typed const

`f12a62815` added `CollectTemplateParamNamesFromTokens` (today
`CollectSpecializationBoundNamesFromTokens`, `compiler/pasparser_generic.inc`
~line 581) to harvest every template PARAMETER name out of `Tokens[]`, so that
`DelphiRewriteGenericUses` can set `isParamForm` and **decline** to mint an
alias for an argument that is really somebody's type parameter.

It tells a template HEADER from a template USE by one token
(`compiler/pasparser_generic.inc:625-628`):

```pascal
{ a HEADER is followed by `=`; a use never is. Roll the collection back
  when this turned out to be a use or a malformed group. }
if ok and (j + 1 < TokCount) and (Tokens[j].Kind = tkGt) and
   (Tokens[j + 1].Kind = tkEq) then
```

The comment states a property the implementation does not have. **A typed const
is a use followed by `=`:**

```
P : ^ specialize TTest < LongInt > = Nil ;
                 ~~~~~~~~~~~~~~~~~~~~~
                 Ident  <  Ident  >  =     <-- indistinguishable from a header
```

So `LongInt` is harvested as a template parameter name — and the harvest is
**deliberately unscoped** (every such name in the file, by design; see the
commit message). `isParamForm` then goes True for `TTest<LongInt>`, the
pattern-B rewrite that `a38a53361` added for exactly this construct is
suppressed (`if not specB then ... { specB paramform: leave untouched }`), the
`specialize` keyword survives as a bare ident, and the pointer type parse
consumes `^specialize` as the pointed-to type. Hence `Expected: =`.

There is a second consequence on the same line worth fixing together: having
decided it is a header, the collector calls `CollectNestedTypeNames(j + 2, i)`
on the const's INITIALIZER region and **resumes `i` past it** — so a
misclassified typed const also skips the scan forward over whatever follows.

### The mechanism confirmed independently of the `=`

The blacklist is the mechanism, not the `=` shape per se. A parameter named
`LongInt` anywhere in the file breaks a use that has no `=` at all:

```pascal
program d_poison;
type
  generic TTest<T> = record x: T; end;
  generic TOther<LongInt> = record y: LongInt; end;   { poisons the name }
var
  P: ^specialize TTest<LongInt>;                       { now fails }
begin P := Nil; if P = Nil then writeln('ok'); end.
```
```
pascal26:6: error: unknown type: TTest
  near:  var P   specialize >>> TTest  LongInt
```

This second case IS the cost `f12a62815` knowingly accepted ("a real type that
happens to share a name with somebody's type parameter"). The typed-const case
is not — it is a use being read as a declaration, and it is the shape
tgeneric87 exists to test.

## Direction (for whoever takes it — not prescriptive)

The narrow repair is to make the discriminator actually discriminate: a header's
`Name` is preceded by a type-section context and its group contains only bare
parameter idents and constraints, whereas the const's group is a specialization
argument list sitting after `:` / `^` / `specialize`. Note `> =` lexes as two
tokens here, so `>=` is not the confusion.

The deeper one is the whitelist the culprit's own message names as the concept
("mint only what is concrete at sweep time") and files as a successor —
`bug-p-a-nested-type-of-the-enclosing-template-is-minted-as-a-concrete-generic-argument`.
That successor and this regression are two symptoms of the same blacklist, so
read `devdocs/dev/root-cause-over-microfix.md` before choosing; two mechanisms
for one concept is already the smell the culprit's message flags.

## History

`a38a53361` (2026-07-12, *inline `specialize T<Args>` in non-binder positions*)
is what made this construct work: it added the `specB` arm to
`DelphiRewriteGenericUses` and **removed** the skip line

```
tgeneric87.pp	gap: `^specialize TTest<T>` pointer-to-specialize in typed const
```

from `test/pascal-conformance/pxx.skip`. That is why the test is unskipped and
now red rather than silently skipped. Do not re-add the skip line as the fix.

## Range

bad `30c06db1ae4e`, last good `b26e7ed366f3`, 14 commits. Three touch the Pascal
frontend: `625991d20`, **`f12a62815`**, `d6cb27a9a`. Attribution to `f12a62815`
is by mechanism (it introduces the collector; `git log -S
CollectTemplateParamNamesFromTokens -- compiler/` returns it and its successor
only), not by a build bisect — no build at `f12a62815^` was performed.

> The named sha `30c06db1ae4e` cannot itself be the cause — it touches no
> buildable file. It is the sha that was TESTED.

## A sharding artefact was considered and REJECTED

`shard0/6` is the only red of the six; the other five last passed later, at
`0b6f1ffe9419`. That asymmetry is not a sharding bug: `list_tests` yields 550
tests over the `CATEGORIES` prefix globs, tgeneric87 is entry 337 → index 336 →
`336 mod 6 = 0` → shard 0, and shard 0 holds exactly 92 tests, matching the
report's `(of 92)`. The shard containing the failing test is the shard that is
red, which is the expected behaviour.

## Original watcher log tail

```
FAIL tgeneric87.pp — compile error:
    Expected: =, but got: TTest (Kind: 1, Line: 11)
    pascal26:11: error: unexpected token
      near:  const TestLongIntNil   specialize >>> TTest  LongInt
test-pascal-conformance: 60 pass, 1 fail, 26 skip, 5 auto-gated (of 92)
test-pascal-conformance: FAILURES: tgeneric87.pp(compile)
```

The failing job is `test-pascal-conformance#shard0/6`, a Track T sweep job —
the 7-line repro above is what a dev lane should work from.

---

## Bisect verification, 2026-08-30 (frankB, Track B — verification only, no fix)

pxx-a5 scoped its own claim: *"attribution is by mechanism, not by a build
bisect at `f12a62815^` — I did not build the parent."* That check has now been
run. **The attribution holds, at the exact commit.**

Three compilers built from source in a throwaway worktree, each seeded from
`stable_pinned` with the seed dated `2000-01-01` so `make` could not no-op.
Each printed `converged after N round(s)` and each sha differs from the seed —
both conditions required, because a fresh tree seeded with a copied-in binary
makes `make compiler/pascal26` a silent success that proves nothing.

| commit | built sha | `a_const` | `b_var` | `c_varconst` | `d_poison` |
| --- | --- | --- | --- | --- | --- |
| `be9198402` = `f12a62815^` | `01c38a6304db` | ok | ok | ok | ok |
| `f12a62815` | `a6bc37164f3d` | **FAIL** | ok | ok | **FAIL** |
| `3ab056a36` (HEAD) | `1bca19929e04` | **FAIL** | ok | ok | **FAIL** |

Seed for all three: `1d69760deabe` (pin v393). Rounds: 2, 2, 2.

Parent clean and the commit itself red is a **one-commit bisect** — no room for
a neighbour, and no 400-commit bracket. The diagnostic at HEAD is character-for-
character the one this ticket recorded (`Expected: =, but got: TTest (Kind: 1,
Line: 4)`), so nothing in the error path has drifted since filing.

**`d_poison` was also clean at the parent.** The `LongInt`-named-parameter case
is described above as the cost `f12a62815` knowingly accepted, and that is right
about intent — but it is a behaviour change introduced by that commit, not a
pre-existing limitation being documented. Accepted-and-new can be un-accepted by
whoever fixes the typed const; accepted-and-always-was cannot. Worth knowing
before someone treats it as out of scope.

### Unexplained rows — data, not a characterization

While the three compilers were on disk, the boundary was probed further. These
are **observations, not a mechanism**, and they do not fit "any single-argument
typed const". They are recorded because one of them has a direct consequence for
the fix's test, below. All run against `f12a62815`; all compile at the parent.

```pascal
{ the argument's NAME decides, and not in an obvious way }
const S: ^specialize TSolo<LongInt>  = Nil;   FAIL
const S: ^specialize TSolo<Int64>    = Nil;   FAIL
const S: ^specialize TSolo<QWord>    = Nil;   FAIL
const S: ^specialize TSolo<SmallInt> = Nil;   FAIL
const S: ^specialize TSolo<Cardinal> = Nil;   FAIL
const S: ^specialize TSolo<TMyAlias> = Nil;   FAIL   { any user alias, whatever it aliases }
const S: ^specialize TSolo<Boolean>  = Nil;   ok
const S: ^specialize TSolo<Integer>  = Nil;   ok
const S: ^specialize TSolo<Byte>     = Nil;   ok
const S: ^specialize TSolo<LongWord> = Nil;   ok
```

```pascal
{ the poison is file-scoped and reaches declarations that do not themselves
  match the header shape -- and it reaches BACKWARDS }
type generic TSolo<A> = record u: A; end;
     generic TPair<A, B> = record u: A; v: B; end;
const
  Q: ^specialize TPair<LongInt, Boolean> = Nil;   { line 6 }
  S: ^specialize TSolo<LongInt> = Nil;            { line 7 -- the poisoner }
                          { -> FAIL, reported at LINE 6, on TPair }
```

Two arguments alone (`TPair` without the `TSolo` line) compiles. The same file
with `S` as a `var` instead of a `const` compiles — the `=` is required. Put the
poisoner FIRST and the file compiles. A named instantiation
(`TInst = specialize TSolo<LongInt>;` then `const K: TInst = ...`) compiles, so
the inline `^specialize T<Arg>` in the const's type is needed.

### The consequence, and it is the reason these rows are here

**A regression test for this written with `Integer` passes on a broken
compiler.** Four of the ten type names above compile today. `tgeneric87` uses
`LongInt` and catches it; a test author reaching for the more idiomatic
`Integer` would have written a test that is green against the defect. Whatever
fix lands should be gated on the failing SET, not on one name — and the split
itself wants explaining, because a mechanism that harvests by token shape has no
business caring whether the token is `Integer` or `Int64`.

No files touched outside this note; the worktree was removed.

---

## RESOLVED, 2026-08-30 (frankA, Track P)

Fixed in `CollectSpecializationBoundNamesFromTokens`
(`compiler/pasparser_generic.inc` ~line 673). The header test keeps the `=` and
gains a **whitelist** on what may precede the group's name:

```pascal
if ok and (j + 1 < TokCount) and (Tokens[j].Kind = tkGt) and
   (Tokens[j + 1].Kind = tkEq) and
   ((i = 0) or (Tokens[i-1].Kind = tkType) or
    (Tokens[i-1].Kind = tkSemicolon)) then
```

A declaration's left-hand side can only follow the `type` keyword or the `;`
that ended the previous declaration. That is a closed list of two. The
alternative — enumerating how a *use* can be spelled — is not closed, and this
session already shipped and reverted the blacklist version of exactly that
mistake (`97b45aabe`, live on origin for about an hour, caught by frankB's
boundary table; the repair added `test_generic_ptr_specialize_const.pas` as the
control the blacklist lacked).

### The `Integer`-vs-`LongInt` split, which the ticket asked to have explained

frankB's unexplained rows have a mechanism, and it is not about types at all.
**The harvest only ever records a token of kind `tkIdent`.** `lexer.inc` gives a
dedicated type-name kind to exactly ten spellings —

```
boolean  byte  char  double  extended  integer  longword  real  single  string
```

— ten spellings over nine kinds (`byte` shares `tkInteger_T` with `integer`).
Those ten are *structurally unable* to enter the bound-name set. Every other
type name — `longint cardinal int64 qword smallint word shortint`, and any user
alias whatever it aliases — stays `tkIdent` and is harvested. The failing set
and the passing set are two disjoint lists of **names**, which is why a harvest
that works by token shape appeared to care which type it was.

This was stated as a prediction before it was measured: it says `Word` and
`ShortInt` must fail and `Char`, `Double` and `Single` must pass. **Measured 8
of 8**, including four rows the ticket had recorded only as `ok`.

It also accounts for the backwards-reaching row (poison at line 7 reported at
line 6): the harvest is a whole-file pre-pass into one flat unscoped array, so
there is no "later" — offered as consistent with the data, not separately proven.

### `d_poison` is un-accepted

frankB's note flagged that the `LongInt`-named-parameter case was a behaviour
change `f12a62815` introduced rather than a pre-existing limitation, and that
"accepted-and-new can be un-accepted by whoever fixes the typed const."
Measured at the fix: **`d_poison` now compiles** (`ok:`). So does the
backwards-reaching two-template file. Both are un-accepted, as hoped.

### Regression test — gated on the failing set

`test/test_generic_bound_name_harvest.pas`, wired into `test-core`, asserts
`boundharvest 45 A 1111111111`. It carries all eight `tkIdent` names plus
`Integer` and `Char` as controls, per the ticket's closing instruction that a
test spelled with the idiomatic `Integer` is green against the live defect.

**One honest limit, recorded in the file header too.** Run against the pre-fix
compiler this file stops at the *first* typed const (line 41, `LongInt`), so by
itself it demonstrates one row and merely asserts the other seven. The per-name
split was therefore measured separately, one name per program, baseline
`a60f92ba830a` (HEAD with the fix reverted) vs fixed `22c67e5ea61e`:

| set | names | before | after |
| --- | --- | --- | --- |
| harvestable (`tkIdent`) | LongInt Cardinal Int64 QWord SmallInt Word ShortInt TMyAlias | **8 fail** | 8 ok |
| dedicated kind | Integer Char Byte LongWord Boolean Double Single | 7 ok | 7 ok |

Forward protection is still per-name — any one of the eight regressing alone
makes the file fail.

Oracle: FPC prints `boundharvest 45 A 1111111111` for the same source, and
agrees on the 7-line `a_const` repro (`trap 42 111` on a runnable variant).

### Verified

- `make compiler/pascal26` — `converged after 1 round(s)`, self-host fixedpoint
  verified, `22c67e5ea61e` (≠ pinned).
- The 14-row trap table (frankB's ten names + LongInt/Int64/QWord/TMyAlias):
  all ok.
- frankB's two boundary files: backwards-reaching poison `ok:`, `d_poison` `ok:`.
- This session's own earlier regressions intact: `shadow 12 10`,
  `ptrspec 7 1`.
- Corpus bound-name harvest unchanged at `names=293 cap=512 overflow=0` — the
  whitelist removed spurious entries only, it did not shrink the real set.

### Successor

`bug-p-a-nested-type-of-the-enclosing-template-is-minted-as-a-concrete-generic-argument`
is the same unscoped harvest seen from the other side and is **not** closed by
this change: the whitelist fixes *what may enter* the set, not the fact that the
set is file-scoped and unscoped. Left open deliberately.

## Log
- 2026-08-30 — resolved, commit 8b85e4881.
