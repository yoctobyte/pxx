---
track: P
prio: 70
type: bug
blocked-by: []
summary: "Two generic specializations that require each other (`TP<A,B>` with a member typed `TP<B,A>`) hung the compiler: 100% CPU, growing memory, no diagnostic, no end. Now a compile error naming both sides, in half a second."
status: done
owner: frank1-ACP
---

# Mutually recursive generic specialization hangs the compiler

- **Track P** (`compiler/parser.inc`, `ParseSpecialization`).
- Found 2026-08-20 by an FPC differential probe over generics.

## The measurement

```pascal
type
  generic TP<A, B> = record
    l: A; r: B;
    function Swap: specialize TP<B, A>;
  end;
function TP.Swap: specialize TP<B, A>;
begin Result.l := r; Result.r := l; end;
type TIP = specialize TP<Integer, string>;
```

| | result |
| --- | --- |
| FPC 3.2.2 | rejects (syntax error at the return type) |
| pxx at `e18d01cef` | **spins** — killed at 3 minutes, 97% CPU, 117 MB and climbing |

A hang is the worst failure mode a compiler has: no location, no message, no
progress, and in a build script no way to tell it from a slow file.

## Root cause

`ParseSpecialization` handles a specialization whose body names a nested one
that is not a type yet by **deferring**: it re-emits its own declaration behind
its prerequisites' declarations, into the token stream, and re-parses. That
terminates only while the unmet-prerequisite set shrinks.

`TP$Integer$string` needs `TP$string$Integer`; `TP$string$Integer` needs
`TP$Integer$string`, which has not been registered because it deferred. Neither
set ever shrinks, and each round inserts a fresh copy of both declarations, so
the token stream grows without bound.

The self-referential case already worked, and shows the shape of the missing
guard — the prerequisite scan skips an alias whose name equals the one being
declared:

```pascal
if (not CaseEqual(aliasNm, specName)) and (not NestedSpecKnown(aliasNm)) then
```

so `generic TNode<T>` with a `next: specialize TNode<T>` field (the ordinary
linked list) is fine. A *swapped-argument* self reference mints a different
alias name, so it misses that check and falls into the cycle.

## The fix

A deferral is only progress while the unmet set shrinks, and it cannot
legitimately take more rounds than there are specializations in the whole
program. So count deferral rounds per specialization NAME and error past
`MAX_SPECIALIZATIONS`:

```
error: circular generic specialization: TP$string$Integer requires
       TP$Integer$string, which requires TP$string$Integer back
```

Both sides are named, because the cycle — not either declaration alone — is
what the author has to break. 0.5 s to the diagnostic.

This makes the failure loud; it does not make the program compile. Two
mutually recursive specializations are finite under memoisation (there are
exactly two of them), so a future change could register a specialization before
streaming its prerequisites and let the cycle close. FPC does not accept this
program either, so that would be a dialect extension rather than parity work,
and it is not what this ticket is for.

## Not affected

A wider generics differential probe run alongside this matches FPC line for
line: generic classes with typed fields and constructors, a generic class with
a `array of T` field driven by `SetLength`, specializations over Integer /
string / Boolean, a nested specialization (`specialize TList<TIBox>`), generic
records, and a self-referential generic class.

## Test

`test/test_generic_cycle_fail.pas` — a negative test: the compile must fail and
the log must contain `circular generic specialization`.

## Gate

`make compiler/pascal26` fixedpoint converged after 1 round; `tools/gate.sh
quick` GREEN.
