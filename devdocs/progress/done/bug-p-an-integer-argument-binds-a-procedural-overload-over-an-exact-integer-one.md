---
slug: bug-p-an-integer-argument-binds-a-procedural-overload-over-an-exact-integer-one
track: P
prio: 45
type: bug
blocked-by: []
status: done
found: 2026-09-07
found-by: frankS
owner: frankA
summary: "`SetCmp(c: TCmp)` and `SetCmp(n: LongInt)` in one class: `SetCmp(4)` runs the PROCEDURAL body, not the exact LongInt one. fpc 3.2.2 picks LongInt. Measured on the pinned compiler too, so it predates the 2026-09-07 multi-candidate gate. The value reaching the procedural parameter is the integer 4 -- benign only while nobody calls through it; a call would jump to address 4."
---

# An integer argument binds a procedural overload over an exact integer one

## The fact

Measured 2026-09-07, and on pin v407, against fpc 3.2.2:

```pascal
type TCmp = function(a, b: Pointer): Integer;
  TC = class
    procedure SetCmp(c: TCmp);     overload;
    procedure SetCmp(n: LongInt);  overload;
  end;
...
  SetCmp(4);
```

| | |
| --- | --- |
| fpc 3.2.2 | `cmp n 4` — the LongInt overload |
| pxx | `cmp set` — the PROCEDURAL overload |

An **exact** parameter match lost to a procedural one. Both candidates have the
same arity, so this is a ranking question and not an arity one.

## Why it is worse than a wrong branch

The integer is bound to a parameter the callee may CALL. Here the body only
tests `c = nil`, so 4 is merely printed as "set"; a body that invoked `c(a, b)`
would jump to address 4. Nothing in the chain is checked — no diagnostic, and
the failure surfaces as a wild jump far from the call site, which is this repo's
expensive class.

## Where to look

`OverloadArgRank` (pasparser_call.inc) ranks by TTypeKind pair. A procedural
parameter's stored kind and an integer argument evidently do not reach rank 3,
and an exact `tyInteger`/`tyInteger` pair should be rank 0 — so either the
procedural parameter's stored kind is not what the ranker thinks, or both
candidates tie and declaration order decides. Print the two ranks before
theorising; that is what `PXXDBG` exists for.

Note the class-identity and pointer-element refinements immediately below the
rank call: both were added for exactly this shape (two parameters that tie at
rank 0 and get picked by declaration order). A procedural parameter looks like
a third instance of that pattern, which would make the fix a third refinement
in the same place rather than a new mechanism.

## How it was found

Writing the positive half of
`bug-p-a-bare-method-overload-call-accepts-any-argument-type-and-runs-the-first-body`,
where a same-arity sibling had to be put beside a procedural parameter to force
the multi-candidate path. The row is deliberately ABSENT from
`test/test_method_overload_arg_typecheck_ok_multi.pas` with a comment saying
why: recording today's wrong answer as expected output would turn that fixture
RED the day this is fixed.

## Log
- 2026-09-07 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit ba5ce95f6.
