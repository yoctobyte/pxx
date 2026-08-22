---
track: A
prio: 35
type: bug
blocked-by: []
summary: "`procedure Outer(var d: TDA); procedure Inner; begin d := e; end;` — the assignment does not reach the caller (Length stays 5 where FPC gives 2). Sibling of bug-a-a-whole-dynarray-assignment-to-a-var-parameter-is-discarded, which fixed the direct case: the nested body reaches `d` through the capture/display path rather than as an skParam, so the by-ref deref added there does not apply. Every backend, not just x86-64."
owner: frank1-A
---

# A dynarray `var` param written from a NESTED routine is discarded

- **Type:** bug (silent wrong value across a call boundary) — Track A
- **Status:** done
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

## Resolved 2026-08-22

**The ticket's own guess was wrong in an instructive way, and the fix is not
about nested routines at all.**

The guess: *"A nested routine does not see `d` as an `skParam` — it reaches the
enclosing frame through the capture/display mechanism — so the symbol it stores
into has different Kind/IsRef."* There is no display. A nested routine here is
**lambda-lifted to top level, with its captures appended as ordinary by-ref
parameters** (`pasparser_proc.inc`: `pbyref[nparams] := True; { captured by
reference }`), and the enclosing body calls it with the captured names as
actuals. Inside `Inner`, `d` is an `skParam` with `IsRef` — exactly what the
ticket assumed it was not.

So the failing construct is one level plainer than the ticket, and needs no
nesting to show:

```pascal
procedure Sink(var d: TDA); begin SetLength(d, 3); d[0] := 8; end;
procedure Fwd(var d: TDA);  begin Sink(d); end;
...
SetLength(d, 5); Fwd(d);   { fpc: 3 8    pxx: 5 -1971322792 }
```

**Forwarding a by-ref dynamic-array parameter onward as another by-ref argument
was broken.** Every nested write to a captured var-param dynarray was that same
call, generated.

### The reasoning that was wrong, and why it read as right

`IRLowerCallArg`'s by-ref dyn-array arm passed `IR_SLOTADDR` for an ident — and
explicitly excluded a forwarded by-ref param:

```pascal
not ((Syms[...].Kind = skParam) and Syms[...].IsRef) then
  { ... A forwarded by-ref param already holds &caller_slot in its
    slot, so it takes the IRLowerAddress path. }
```

The first half is true: the slot does hold `&caller_slot`. The second half does
not follow. `IRLowerAddress` reaches `IR_LEA`, and **IR_LEA's dyn-array arm
derefs TWICE on a read** — once to `&caller_slot`, once more to the data
pointer — because in a value context reading a by-ref dyn param means the
handle. So the callee received the DATA pointer, treated element 0 as a handle,
and produced garbage or a fault.

The comment even points at the AnsiString arm below it as its model. That arm
excludes the same case, states the same reason, **and is correct** — because
IR_LEA's *string* arm derefs only once. Two arms, one sentence of reasoning,
opposite truth values, decided by a detail three files away.

### One helper instead of three sites reasoning about IR_LEA's modes

```pascal
function IRDynHandleSlotAddr(symIdx: Integer): Integer;
begin
  Result := IRAppend(IR_SLOTADDR, symIdx, -1, -1, 0, Ord(tyPointer));
  if (Syms[symIdx].Kind = skParam) and Syms[symIdx].IsRef then
    Result := IRAppend(IR_LOAD_MEM, Result, -1, -1, 0, Ord(tyPointer));
end;
```

Used by the by-ref argument path and by the `IR_DYNUNIQUE` base
([[bug-a-setlength-on-a-2d-dynarray-var-param-is-lost]], fixed an hour earlier
with the same two lines inline). Both bugs were one node used where the slot was
wanted; the helper is the place that answers "where does this array's handle
live" once, so a fourth site cannot re-derive it wrongly.

`devdocs/dev/normalise-dont-special-case.md`, and note which half repeated: not
the code — the *reasoning*.

### Also answered: the AnsiString question the ticket asked

*"Worth checking whether the AnsiString equivalent has the same nested-routine
hole, since it keys on exactly the same two fields."* It does not, and the test
pins it: `procedure NestStr(var s: AnsiString)` with `s := s + 'x'` in the
nested body gives `ax`. Same exclusion, same two fields, correct — for the
reason above.

### Verification

`test/test_dynarray_var_param_forwarded.pas`, 7/7, identical under fpc 3.2.2 and
under `-dPXX_HEAP_DEBUG`: bare forwarding with no nesting, a local forwarded the
same way as the control, the ticket's own nested assign, nested `SetLength`,
the nested 2-D form (which used to segfault), the AnsiString capture, and a
nested routine writing an enclosing LOCAL rather than a param.

Gate: `make compiler/pascal26` (fixedpoint, converged after 1 round) +
`tools/gate.sh quick` GREEN.

## Log
- 2026-08-22 — resolved, commit PENDING-COMMIT.
