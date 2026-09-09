---
track: P
prio: 60
type: bug
blocked-by: []
status: open
owner: frankS
summary: "Two templates may share a NAME and differ in ARITY in one unit -- legal, and rtl-generics does it four times (`TGStringComparer<T, THashFactory>` beside `TGStringComparer<T> = class(TGStringComparer<T, TDelphiQuadrupleHashFactory>)`). Three sites attribute a generic method IMPLEMENTATION to a template by NAME ALONE, each taking the LAST match, so the two-parameter body is handed to the one-parameter template and streamed under a substitution binding only `T`. A specialization inside such a body then comes out with a PARAMETER NAME as its second argument (`TGOrdinalStringComparer$string$THashFactory`), and the expression-position `<` is read as less-than: `undefined variable (TGOrdinalStringComparer)` at generics.defaults.pas:3250, against a line whose text is fine. This is the current wall of feature-pascal-corpus-generics. FIXING ATTRIBUTION ALONE IS NOT ENOUGH and makes some programs that compile today fail: it exposes a second gap, a `specialize NAME<concrete args>` group in EXPRESSION position inside a streamed body that is never collapsed to its minted alias. Both halves must land together. Diagnosis and a 30-line repro below; a partial patch exists in the frankS checkout ONLY and is not on origin."
---

# A generic method implementation is attributed by name, not arity

**Measured** at binary `417ee5636a72`, HEAD `5acbe362b`, and the age facts by
`git log -S`.

## The wall

```
$ pascal26 -Fu<rtl-generics/src> driver.pas    { driver: uses Generics.Collections; }
generics.defaults.pas:3250: error: undefined variable (TGOrdinalStringComparer)
  near: FOrdinal ) then FOrdinal := TGOrdinalStringComparer >>> < string ,
generics.defaults.pas:3250: error: expected '(' before ','
  near: then FOrdinal := TGOrdinalStringComparer < string >>> , THashFactory >
```

**Read the near-window, not the message.** `T` is substituted to `string` and
`THashFactory` is NOT -- it is still the template's own parameter name. The
source line is

```pascal
class function TGStringComparer<T, THashFactory>.Ordinal: TCustomComparer<T>;
begin
  if not Assigned(FOrdinal) then
    FOrdinal := TGOrdinalStringComparer<T, THashFactory>.Create;
```

and it is fine. `undefined variable` is what the expression parser says once the
`<` stops being a specialization opener and becomes less-than.

## The cause

`generics.defaults.pas` declares, in one unit:

```pascal
TGStringComparer<T, THashFactory> = class(TOrdinalComparer<T, THashFactory>) ... end;
TGStringComparer<T> = class(TGStringComparer<T, TDelphiQuadrupleHashFactory>);
TStringComparer = class(TGStringComparer<string>);
```

Legal, and four families in that file do it. **Three sites pick the template by
name and keep the LAST match:**

| site | file | what it decides |
| --- | --- | --- |
| `EmitLateNestedSpecDecls` | `pasparser_generic.inc` | which template's method impls to SCAN for nested prerequisites |
| `ScanDelphiMethodImplsForNestedSpecs` | `pasparser_generic.inc` | which impl headers belong to that template |
| `ParseSubroutine`'s `X.M` branch | `pasparser_proc.inc` | which template a body is BUFFERED against |

`PXXDBG=p.nspec` says it in one line:

```
reg alias=TGOrdinalStringComparer$string$THashFactory
    under=TGStringComparer$string  tmplName=TGStringComparer  nsub=1  subs=T->string
```

A one-parameter specialization, scanning a two-parameter body, with a
one-entry substitution set. That probe's own header already told us what such a
line means: "an argument that comes out as a template PARAMETER name means the
name was not in SpecSubNames here".

**`SpecTemplateIdx` was added for exactly this** -- `SpecTemplateDeclUnit`'s
header says "a name is not an identity ... which is the bug SpecTemplateIdx
exists to fix" -- and `EmitLateNestedSpecDecls` kept the old lookup. A rule
spelled per caller, failing by an absent copy.

## Not a regression, and a revert will LIE about that

`1c16d4523` (2026-09-09) is the natural suspect because the wall appeared right
after it. It is not the cause: the `EmitLateNestedSpecDecls` loop is
`3a011ed6f`, **2026-08-29**, and the `ParseSubroutine` loop is `951d9c9dd`,
**2026-08-20**. `1c16d4523` moved the wall from `collections.pas:120` to here,
which made this defect REACHABLE for the first time.

**So reverting `1c16d4523` makes the `:3250` error disappear, and that means
nothing** -- the file stops earlier and never reaches the line. An attribution
run over this must compare the CODE's age, not the error's presence.

## What a fixer needs to know before starting

Making attribution arity-aware is straightforward -- the header's arity is
knowable, because `DelphiRewriteGenericUses` deletes the `<...>` group and can
record `na` beside `GenMethImplSOff`. Done that way, the corpus's near-window
goes from `< string , THashFactory >` to `< string , TDelphiQuadrupleHashFactory >`:
**the substitution becomes correct.**

**And the error stays, one layer down, and a program that compiles today starts
failing.** This 30-line unit compiles at HEAD and does NOT with attribution
fixed:

```pascal
unit wunit;
{$MODE DELPHI}
interface
type
  THashA = class end;
  TBase<T> = class end;
  TStr<T, H> = class(TBase<T>)
    class function Ordinal: TBase<T>; static;
  end;
  TOrd<T, H> = class(TStr<T, H>) end;
  TStr<T> = class(TStr<T, THashA>);          { the arity overload }
  TOrd<T> = class(TOrd<T, THashA>);
  TStringComparer = class(TStr<string>);
implementation
class function TStr<T, H>.Ordinal: TBase<T>;
begin
  Result := TOrd<T, H>.Create;               { EXPRESSION position }
end;
end.
```

→ `undefined variable (specialize)`, near `Result := specialize >>> TOrd < string`.

The alias `TOrd$string$THashA` IS minted (`PXXDBG=p.mint:*` shows it), and
`SpecializeToBuffer` collapses such a group only when `NestedSpecKnown(aliasNm)`
holds at splice time. In a type position it does; in this expression position it
does not, the `specialize` token survives into the stream, and no expression
parser arm consumes it. **The two halves must land together** -- attribution
without the collapse trades a wrong substitution for a refused program.

Where to look for the second half: `SpecializeToBuffer`'s `NestedSpecGroup` arm
(`pasparser_generic.inc`), and whether the prerequisite is registered before or
after the body is streamed for that specialization.

## Held state

A partial patch -- arity recorded in a new `GenMethImplNArgs`, all three sites
made arity-aware, `SpecTemplateIdx` used in `EmitLateNestedSpecDecls` -- exists
in the frankS checkout as a scratch patch and **is not on origin**. It is the
first half only, it makes the repro above fail, and it is deliberately unlanded.
Its value is this write-up; do not go looking for the diff.

## 2026-09-09 (frankS, later) — the second half is NOT an expression-position gap, and I said it was

Measured at HEAD `7bbab967c` with the four-site patch applied, probes added for
this question and then removed with it.

### Correction first

I wrote above that the second half is "a `specialize NAME<args>` group in
EXPRESSION position inside a streamed body is never collapsed". **That is the
symptom, not the cause, and the cause is nothing to do with expression
position.** The group never carries the `specialize` marker in the first place,
and `NestedSpecGroup` requires it, so the collapse arm cannot see the group at
all — measured, `gEnd=-1`.

### What the marker is missing FROM: a snapshot

`DelphiRewriteGenericUses` injects `specialize` into the MAIN token stream when
a template is declared. `BufferTemplateMethodsAhead` copies method bodies into
the template arena at SPECIALIZATION time. In `generics.defaults.pas` those two
orders cross:

```
line  994   TStringComparer = class(TGStringComparer<string>);    <- specialization
line 1002   TGOrdinalStringComparer<T, THashFactory> = class(...) <- declaration
line 3250   FOrdinal := TGOrdinalStringComparer<T, THashFactory>.Create;
```

Two probes, one run:

```
PXXDBG p.ahead  buffer tmpl=TGStringComparer hdrline=3247 toks=37
                specialize-tokens=1 atparseline=994
PXXDBG p.dgen   inject specialize before TGOrdinalStringComparer tok=153453 line=3250
```

The body at `:3247` is copied while the parser is at **line 994** — eight lines
before `TGOrdinalStringComparer` exists. Its own sweep injects the marker at
`:3250` afterwards, into the main stream, and **nothing re-visits the copy.** The
arena holds one `specialize` (the return type's, injected by an earlier sweep)
and not the one that matters.

**A copy is a snapshot, and this one is taken mid-rewrite.** The rewrite runs to
a fixed point PER TEMPLATE, so "the stream has been rewritten" is only ever true
of the templates declared so far — and buffering ahead exists precisely to get in
front of the parser, i.e. in front of later declarations.

### What this means for a fixer

- The four-site arity fix is correct and is NOT enough on its own; with it, the
  30-line `wunit` repro above compiles again (the fourth site is
  `BufferTemplateMethodsAhead`, which also matched by name).
- The remaining work is the snapshot: either re-sweep the buffered arena range
  when a template is declared later, or buffer lazily, or record which templates
  a buffered range predates and re-rewrite on use. All three are real changes to
  the rewrite/buffer boundary and none is a one-liner.
- Do not aim at the expression parser. It is behaving correctly on the tokens it
  is handed.

### One number withdrawn

I said earlier that `uses Generics.Defaults` alone compiled while
`uses Generics.Collections` failed. At the current HEAD **both fail at
`:3250`** — I measured the first at binary `417ee5636a72`, the tree has moved
since, and the difference was never mine. Re-measure before quoting a
driver-dependent wall on this rung.
