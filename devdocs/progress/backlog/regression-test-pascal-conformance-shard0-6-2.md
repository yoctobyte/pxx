---
prio: 70
track: P
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
