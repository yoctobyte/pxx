---
slug: bug-p-a-distinct-type-declaration-is-parsed-but-is-not-distinct
track: P
prio: 40
type: bug
status: backlog
blocked-by: []
created: 2026-09-04
found-by: frankB
owner: ""
summary: "`T = type Base` now PARSES (compat-pascal-distinct-type-declaration, 2026-09-04) but the type it declares is an ordinary alias: pxx has no type-IDENTITY channel for aliases at all, so a value declared through the name reaches overload matching as its base kind. FPC binds `P(b)` and `P(x)` to different bodies; pxx warns `duplicate definition of 'P' with the same parameter types` and binds both to one. Loud, not silent, and the same thing it already does for a plain `= byte` alias -- so the parse fix reached an existing behaviour rather than adding a new one. The missing piece is one channel, not one predicate: no LastTypeAlias, no Syms[].AliasIdx, no ProcParam alias carrier."
---

# A distinct-type declaration is parsed but is not distinct

## Measured 2026-09-04 (binary `51f7aaf4a27d`, vs fpc 3.2.2)

```pascal
type TMyB = type byte;
procedure P(b: byte);  begin WriteLn('base'); end;
procedure P(m: TMyB);  begin WriteLn('distinct'); end;
var x: TMyB; b: byte;
begin x := 5; b := 1; P(b); P(x); end.
```

| | |
| --- | --- |
| fpc 3.2.2 | `base` then `distinct` |
| pxx | `warning: duplicate definition of 'P' with the same parameter types` — then `distinct` twice |

A `var` parameter of the base type also accepts a value of the distinct type,
which FPC refuses.

**It is LOUD, and it is not new.** pxx says exactly the same thing for a plain
`type TMyB = byte;` — the two overloads collapse there too. So this is not
fallout from the parse fix: that fix made an existing behaviour reachable
through one more spelling.

## Why — the channel that is missing, not the predicate

The distinctness cannot be expressed today because **an alias has no identity
anywhere downstream of its declaration**:

```
$ grep -n 'LastType[A-Za-z]*' compiler/defs.inc | grep -o 'LastType[A-Za-z]*' | sort -u
... LastTypeEnumId, LastTypeRecId, LastTypeProcSig, LastTypePointerAlias ...   # no LastTypeAlias
$ grep -n 'AliasIdx\|SymAlias' compiler/defs.inc
(no output)
$ grep -o 'ProcParam[A-Za-z]*' compiler/defs.inc | sort -u
... ProcParamRecId, ProcParamSetEnumId, ProcParamPtrElemTk, ProcParamStrElemTk ...   # no alias carrier
```

`ParseTypeKind` reports a record through `LastTypeRecId`, an enum through
`LastTypeEnumId`, a procedural type through `LastTypeProcSig` and a POINTER
alias through `LastTypePointerAlias` — but a general alias resolves to its base
`TTypeKind` and nothing carries which name produced it. So by the time a
parameter is registered, `TMyB` and `byte` are the same three fields.

## What to add

The same shape the four identity channels above already have, all the way
along one chain — and it is a chain, which is why this is not a one-line fix:

1. `AliasIsDistinct[]` beside `AliasTk[]`, set where the `type` keyword is
   consumed in `ParseTypeSection` (`compiler/pasparser_decl.inc`, the arm added
   by compat-pascal-distinct-type-declaration).
2. `LastTypeAlias` out of `ParseTypeKind`, the general-alias twin of the
   pointer-alias one that already exists.
3. `Syms[].AliasIdx` (or a parallel `SymAliasIdx[]`, the convention the other
   carriers use), so a VAR remembers the name it was declared through.
4. `ProcParamAliasIdx[]`, a parallel array for the reason `ProcParamRecId`'s
   own comment gives: param syms are reused across procs, so a caller cannot
   read it back off the param symbol.
5. `MatchParamCompatible` / the duplicate-signature check comparing them, with
   `AliasIsDistinct` deciding whether a mismatch matters.

**Step 5 is where the risk is, not step 1.** Making aliases compare by identity
everywhere would break every ordinary `type TInt = Integer`, which must keep
accepting an `Integer`. Only an alias whose declaration carried the `type`
keyword is distinct — so `AliasIsDistinct` has to be read at the COMPARISON,
never at the registration.

## What is NOT wanted

Do not make the parse reject the overload pair as FPC does when the alias is
NOT distinct (`overloaded functions have the same parameter list`). pxx warns
and continues on purpose; that is
feature-a-error-does-not-halt-so-a-parse-can-be-speculative, not a gap.

## Survey 2026-09-05 (frankB) — step 5 is one function on the PARAMETER side and a missing channel on the ARGUMENT side

Surveyed before starting, and NOT started, because the answer is that the chain
is longer than the five steps above suggest and a half-plumbed alias identity is
worse than none.

**The good half.** `MatchParamCompatible` (`compiler/symtab.inc:9227`) is, by its
own header, *"the ONE place the compatible phases of overload matching ask"*
whether an argument fits a parameter — and it says so because the previous two
additions were made at the seven call sites instead and drifted. So the
parameter side of step 5 is one function, not seven.

**The half the ticket did not name.** Its signature is

```pascal
function MatchParamCompatible(i, j: Integer; aTk: TTypeKind): Boolean;
```

The argument arrives as a bare `TTypeKind`. There is nowhere in that call to put
"and it was declared through TMyB", so step 5 needs the argument's identity
threaded in as well — which means either a signature change carrying the
argument NODE, or an `ASTAliasIdx` channel. `Syms[].AliasIdx` (step 3) answers
it only for an `AN_IDENT` argument; a field, an index, a call result or any
expression has no symbol to ask.

**And there is a second decision point.** The duplicate-signature warning in
`pasparser_proc.inc:2100` fires only *"when FindProcOverloadRec matched an
IDENTICAL signature"*, so making two overloads distinct means teaching
`FindProcOverloadRec` as well, not only the compatibility test. Two places, and
they must agree — the seam shape that produced
bug-p-a-specialization-minted-in-a-units-implementation-is-seen-by-the-importers.

**Revised step 5, replacing the one above:**

5a. thread the argument's alias identity into `MatchParamCompatible` — signature
    change, or an AST channel if expressions are to be covered at all;
5b. teach `FindProcOverloadRec` the same rule, in the same commit, because a
    permissive answer in one and a strict answer in the other is the seam;
5c. read `AliasIsDistinct` at BOTH comparisons and never at registration, so an
    ordinary `type TInt = Integer` keeps accepting an `Integer`.

**Scope estimate: six sites and a signature change**, not five appends. Worth
doing, worth doing in one pass, and not worth beginning at the end of a session.

