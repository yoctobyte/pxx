---
track: A
prio: 35
type: bug
blocked-by: []
summary: "`procedure Outer(var d: TDA); procedure Inner; begin d := e; end;` — the assignment does not reach the caller (Length stays 5 where FPC gives 2). Sibling of bug-a-a-whole-dynarray-assignment-to-a-var-parameter-is-discarded, which fixed the direct case: the nested body reaches `d` through the capture/display path rather than as an skParam, so the by-ref deref added there does not apply. Every backend, not just x86-64."
---

# A dynarray `var` param written from a NESTED routine is discarded

- **Type:** bug (silent wrong value across a call boundary) — Track A
- **Status:** backlog
- **Opened:** 2026-08-22, from the same 13-shape differential that found
  [[bug-a-a-whole-dynarray-assignment-to-a-var-parameter-is-discarded]]

## Measured

```pascal
type TDA = array of Integer;
procedure P_nested(var d: TDA; const e: TDA);
  procedure Inner; begin d := e; end;
begin Inner; end;
...
SetLength(d, 5); SetLength(e, 2); P_nested(d, e);   { FPC: 2   pxx: 5 }
```

Unlike its sibling this is **not** x86-64-only — i386, aarch64, arm32 and
riscv32 all give 5 as well.

## Why it is a separate ticket

The direct case was fixed by giving x86-64's `IR_STORE_SYM` dynarray arm the
by-ref deref it was missing: for an `skParam` with `IsRef`, the frame slot holds
the address of the caller's handle. A nested routine does not see `d` as an
`skParam` at all — it reaches the enclosing frame through the capture/display
mechanism — so the symbol it stores into has different `Kind`/`IsRef`, and the
new arm does not fire.

Worth checking in the same pass whether the AnsiString equivalent
(`EmitPublishManagedString`, which has had its by-ref arm for much longer) has
the same nested-routine hole, since it keys on exactly the same two fields. If
it does, that is the real ticket and this is one symptom of it.

## Gate

Track A's, plus the nested row matching fpc 3.2.2 and the ARC check the sibling
ticket's test uses (the enclosing variable must survive with its contents).
