---
slug: bug-p-a-method-parameter-typed-through-a-forward-pointer-alias-never-matches-its-own-body
title: "A method parameter typed `PItem` where `PItem = ^TItem` sits above `TItem` never matches its own implementation"
track: P
type: bug
prio: 60
status: done
found: 2026-09-11
found-by: frankS
owner: frankS
blocked-by: []
tags: [fpc-corpus, forward-pointer, overload-matching, umbrella-pxx-compiles-fpc-itself]
summary: "FIXED 2026-09-11. A METHOD DECLARED IN THE SAME `type` SECTION AS A FORWARD POINTER ALIAS, taking that alias as a parameter, registered a signature the implementation header could not match -- so the body created a SECOND proc and the declaration's entry never got an address. A call reached BEFORE the body bound to the bodiless entry and died at CODEGEN with `unresolved forward: TL.Cb`, reported against builtinheap.pas with a note suggesting an unterminated comment. CAUSE, measured not reasoned: while `PItem = ^TItem` waits for ResolvePendingPointerAliases its element carries the pending arm's PLACEHOLDER, tyInteger. A field (UFldPtrAlias), an array element (ArrTypePtrAlias) and a function result (ProcRetPtrAlias) are all repaired by that pass; a PARAMETER has no such column, so the declaration kept 1 and the implementation -- parsed after the pass -- recorded 5 (tyRecord). Instrumented FindProcOverloadRec printed exactly that: `p1 tk=17/17 ptrelem=5/1`, and the typed-pointer split arm separated them. FIX: ParamPtrElemOf answers tyUnknown while the alias is an unresolved forward, which is the claim the split arm's own both-sides-must-positively-name guard was written for. DECLARATION ORDER IS THE WHOLE TRIGGER -- record above the alias, class in a second type section, or the body written before its caller, and none of it reproduces. Found on FPC's cclasses.pas (`PViHashListItem = ^TViHashListItem`, eleven lines above its record); it was the LAST defect between pxx and that unit, which now stops only on `Finalize(x, n)`."
---

# The declaration and the body were two different routines

## The repro, 20 lines, and every line of it is load-bearing

```pascal
program m;
type
  PItem = ^TItem;                  { alias ABOVE its record -- trigger 1 }
  TItem = record Data: Pointer; end;
  TL = class(TObject)              { same type section -- trigger 2 }
  public
    FC: Integer;
    procedure Rehash;
    procedure Cb(Item: PItem);
    procedure Go;
  end;
procedure TL.Rehash; begin Cb(nil); end;   { call BEFORE the body -- trigger 3 }
procedure TL.Cb(Item: PItem); begin FC := 7; end;
procedure TL.Go; begin Rehash; WriteLn('fc=', FC); end;
var l: TL;
begin l := TL.Create; l.Go; end.
```

`pascal26:2: error: unresolved forward: TL.Cb`, `in: ./compiler/builtin/builtinheap.pas`.
fpc 3.2.2 prints `fc=7`.

Remove any one of the three triggers and it compiles:

| variant | result | why |
| --- | --- | --- |
| `TItem` above `PItem` | compiles | the alias is never a forward |
| class in a SECOND `type` section | compiles | `ResolvePendingPointerAliases` has already run |
| `Cb`'s body written before `Rehash`'s | compiles | the call binds to the body's proc, which has an address |
| free procedures with `forward;` | compiles | that path matches by NAME, not by proc identity |

That table is the diagnosis: nothing about the pointer, everything about **when
the alias was read**.

## What the instrument said, rather than what the shapes suggested

A temporary print in `FindProcOverloadRec`, on the candidate it rejected:

```
PROBE find TL.Cb n=2 cand=146 match=FALSE
   p0 tk=6/6   rec=0/0  ptrelem=0/0  alias=-1/-1
   p1 tk=17/17 rec=0/0  ptrelem=5/1  alias=-1/-1
```

`ptrelem=5/1` is the whole bug: the implementation says `tyRecord`, the
declaration says `tyInteger`. Everything else on both params is identical,
`ProcParamAliasIdx` included — so the alias-identity arm could never have
separated them and the typed-pointer arm did.

`tyInteger` is not a type anyone wrote. It is the placeholder
`ParseTypeKind` leaves when a `^T` names a type that does not exist yet
(`RecordPendingPtrTarget(lo); Result := tyInteger`).

## The fix, and why it is at `ParamPtrElemOf` and not one layer up

`symtab.inc`, `ParamPtrElemOf` — the single funnel every parameter registration
path reads, declaration and implementation alike:

```pascal
else if (LastTypePointerAlias >= 0) and
        (AliasElemRec[LastTypePointerAlias] = REC_NONE) and
        (AliasTargetNLen[LastTypePointerAlias] > 0) then
  ParamPtrElemOf := Ord(tyUnknown)
```

The guard is exactly `ResolvePendingPointerAliases`'s own row predicate, so the
two agree by construction about what "still pending" means.

`tyUnknown` is the right answer and not a workaround. The split arm this feeds
already requires **both** sides to positively name a pointee, and says so in its
own comment — precisely so a registration path that never recorded one cannot
manufacture a phantom overload. *"Not resolved yet"* is the same claim as *"not
recorded"*. This function was handing that guard a placeholder that looked like
a real type.

**The obvious place to fix it is wrong, and that was measured too.** Answering
`tyUnknown` from the alias arm of `ParseTypeKind` reads better — it is where the
placeholder is introduced — and it **breaks the compiler's own self-host**:
`make compiler/pascal26` dies at `EmitAsmX64: unknown 0-operand mnemonic`. Other
readers of `LastTypePointerElemTk` depend on the placeholder and are repaired
later through columns the parameter path does not have. The narrow site is the
one whose answer is durable and unrepaired.

## Not a regression risk in the direction it looks like one

Two same-arity overloads whose pointer parameters are both still-pending
forwards now collide at declaration time rather than splitting. Measured: they
**already** collided — `procedure P(x: PA)` / `procedure P(x: PB)` with `PA`,
`PB` both forward gives `duplicate definition of 'TL.P' ... the later body wins`
and runs the later body for both calls, and the PINNED compiler gives the
identical wrong answer. So this fix does not create that case and does not
widen it; it is the one already filed shape of
[[bug-pascal-overload-impl-decl-signature-match]]'s family and is unchanged
here. fpc refuses that program outright, which is why it is not in the fixture.

## Guard

`test/test_p_a_forward_pointer_alias_parameter_matches_its_own_body.pas`, wired
beside the bracket-slot rows. Four rows, byte-identical to fpc 3.2.2.

- **Positive control, verified:** the PINNED compiler refuses the fixture —
  `unresolved forward: TAdder.Later`.
- **Negative control inside the file:** `Earlier`, the same routine with its
  body written first, which compiled before the fix and must keep compiling.
- **And one row that is not about matching at all:** `Fetch` returns a `PItem`
  and the caller reads `^.Next`, which is at offset 8. A pointee that had been
  forgotten answers on `p^.V` (offset 0) and fails there — the offset-0 tell
  this repo has now paid for three times.

## Provenance

Found by pointing the corpus probe at `cclasses.pas` with the
`Finalize(x, n)` refusal made RECOVERING rather than fatal, which is the
instrument [[umbrella-pxx-compiles-fpc-itself]]'s attempt 6 asked for in its own
words: *"the honest unit of work is 'make cclasses.pas compile', not 'clear the
150'."* The first thing past that wall was this bug. cclasses.pas now reports
**two errors, both the same wall** (`Finalize(x, n)` at 1726 and 1893) and
nothing else.
