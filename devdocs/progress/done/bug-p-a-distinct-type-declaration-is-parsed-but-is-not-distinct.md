---
slug: bug-p-a-distinct-type-declaration-is-parsed-but-is-not-distinct
track: P
prio: 40
type: bug
status: done
blocked-by: []
created: 2026-09-04
found-by: frankB
owner: ""
summary: "FIXED 2026-09-06. `T = type Base` declared an ordinary alias, so `P(b: byte)` and `P(m: TMyB)` collapsed into one row with `duplicate definition of 'P'` and both calls ran the last body; FPC binds two. Built the identity chain the ticket asked for -- AliasIsDistinct, LastTypeAlias, SymAliasIdx, ProcParamAliasIdx, MatchArgAliasIdx -- and ONE predicate, AliasIdentityMismatch, read from both decision points. TWO OF THIS TICKET'S OWN PREMISES WERE WRONG. Its var-parameter claim (`which FPC refuses`) is false: measured three ways, fpc accepts a distinct value through a base-typed var parameter, so distinctness is an overload PREFERENCE and belongs in MatchParamExact, not in the compatibility test where the first implementation put it and refused working code. And its survey said the argument side needed a signature change or a new AST channel; FillMatchArgChannelsAt already existed and takes the NODE."
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

**CORRECTED 2026-09-06, and this sentence was FALSE — see the resolution
section.** It read: *"A `var` parameter of the base type also accepts a value of
the distinct type, which FPC refuses."* Measured three ways, FPC accepts it, and
believing this put the first implementation in the wrong function.

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


## RESOLVED 2026-09-06 (frankB) — and TWO of this ticket's own premises were wrong

### The survey above was wrong about the argument side, and wrong in the way that matters

It said: *"The argument arrives as a bare `TTypeKind`. There is nowhere in that
call to put 'and it was declared through TMyB', so step 5 needs the argument's
identity threaded in as well — which means either a signature change carrying the
argument NODE, or an `ASTAliasIdx` channel."*

The signature observation is true. The conclusion is false, because **the channel
already exists**: `FillMatchArgChannelsAt(i, node, argTk)` in
`pasparser_call.inc` is a single entry point that takes the NODE and fills seven
side channels for exactly this reason — `MatchArgRec`, `MatchArgNil`,
`MatchArgScalar`, `MatchArgArray`, and three more, every one of them added
because *"the kind pair alone gave a WRONG ANSWER"*. `MatchArgAliasIdx` is the
eighth, filled beside them, read the same way.

I reasoned from the SIGNATURE instead of looking for the channel — and the
extraction that created that entry point (`refactor-p-the-overload-probe-cannot-
see-the-argument-match-channels`) landed on **2026-09-05, the same day I wrote
the survey**. The scope estimate ("six sites and a signature change") was
therefore pessimistic about the hard part and silent about the real one.

### THE VAR-PARAMETER CLAIM IN THIS TICKET IS FALSE, AND IT SENT THE FIX TO THE WRONG FUNCTION

This ticket said: *"A `var` parameter of the base type also accepts a value of the
distinct type, which FPC refuses."*

Measured against fpc 3.2.2, three shapes, all with a SINGLE candidate:

```
procedure V(var v: byte);  var x: TMyB;  V(x)   -> fpc compiles, prints 6
procedure V(var v: TMyB);  var b: byte;  V(b)   -> fpc compiles, prints 1
procedure V(v: TMyB);      var b: byte;  V(b)   -> fpc compiles, prints 3
```

**FPC accepts all three.** A distinct type stays assignment-compatible with its
base, in both directions, by reference as well as by value. So distinctness is an
overload **PREFERENCE**, not a compatibility rule.

The first implementation followed the ticket and put the check in
`MatchArgRecMismatch` — a hard refusal — and it refused all three. That is
rejecting working code, which is strictly worse than the bug it fixes. Moved to
`MatchParamExact`, whose own header already states the rule for the identical
mistake one type family over: *"passing a WideString to the only overload that
takes an AnsiString is a legal, real conversion, and FPC compiles it. What FPC
does NOT do is prefer it when a width-exact candidate exists. Blocking it
outright would refuse working code; ranking it below exact is the rule."*

The precedent was already in the file. The ticket's sentence is what stopped me
reading it.

### The chain, as built

1. `AliasIsDistinct[]` beside `AliasOwnerCi`, stamped by `AliasCommit` from
   `DeclDistinctNow` and **consumed** there, so one keyword marks one row.
   `ParseTypeKind` saves/restores the flag around the RHS, because the RHS
   commits alias rows of its own (`EnsureBuiltinPtrAlias`) that would otherwise
   eat it.
2. `LastTypeAlias` out of `ParseTypeKindInner`'s general-alias arm — the twin of
   `LastTypePointerAlias`, reset at the top with every other `LastType*`.
3. `SymAliasIdx[]`, stamped from `VDAliasIdx`, which `ParseDeclTypeDesc` captures
   at the end of the routine that ran `ParseTypeKind` rather than at the
   allocation site.
4. `ProcParamAliasIdx[]`, staged as `ptypesAlias` and persisted at all three
   registration sites, for the reason `ProcParamRecId`'s own note gives.
5. `MatchArgAliasIdx[]` + `MatchArgAliasValid`, filled in
   `FillMatchArgChannelsAt`.
6. `AliasIdentityMismatch(a, b)` — ONE predicate, read from both decision points:
   `MatchParamExact` (call-site preference) and `FindProcOverloadRec`
   (declaration-time splitting). The ticket was right that both are needed and
   right that they must agree; the argument-side fix alone produced
   `candidates: P(Byte)` — a call refused against a candidate list that never had
   the second declaration in it.

### Stated boundaries, not omissions

- Only an `AN_IDENT` argument carries an alias identity today. A field, an index
  or a call result stays -1, which means *unconstrained* and matches exactly as
  before — the conservative default `MatchArgScalar` and `MatchArgArray` already
  take, and for the same reason: a channel that GUESSES is worse than one that
  abstains, because the guess is believed.
- The class-method declaration path (`pasparser_decl.inc`) passes -1 for every
  parameter, so a distinct type as a METHOD parameter still collapses with its
  base. -1 is today's behaviour, so the boundary costs nothing.
- `P(5)` with both overloads live: fpc answers *"Can't determine which overloaded
  function to call"*; we bind the base. Accepting what fpc rejects is not a
  defect, so the row carries no oracle and is not in the test.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 3cfb35bc7.
