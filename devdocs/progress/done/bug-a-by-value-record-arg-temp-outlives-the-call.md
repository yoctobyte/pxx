---
track: A
prio: 25
type: bug
blocked-by: []
summary: "A by-value record argument is copied into a caller-frame temp that is released at the CALLER's scope exit, not when the call returns. FPC finalizes a value parameter in the callee, so an observable destroy (an interface field) happens later here — at program exit when the caller is the main body."
status: done
owner: frank1-A
---

# A by-value record arg's temp outlives the call

Found while resolving
[[bug-a-a-record-copy-does-not-retain-an-interface-field]]; it is the one
remaining FPC divergence in that ticket's differential, and it is NOT
interface-specific — interfaces only make it observable, because a destructor
prints and a string refcount does not.

## Measured (FPC 3.2.2 vs pxx HEAD, same source)

```pascal
type TRec = record a: Integer; f: IFoo; end;
procedure ByValue(r: TRec); begin writeln(r.f.Name); end;
var g: TRec;
begin
  g.f := TFoo.Create('B');
  ByValue(g);
  g.f := nil;
  writeln(destroyed);      { FPC: 1     pxx: 0 (the temp still holds a ref) }
end.
```

Inside a PROCEDURE the two agree, because the caller's scope exit happens right
after the call. In the MAIN body they diverge until program exit.

## Cause

`IRLowerCallArg` (`compiler/ir.inc`, the `RecordHasManagedFields(argRecId)` arm)
copies the argument into a hidden `skLocal` temp with `IR_COPY_REC_MANAGED`,
which retains. Nothing releases it at the call's end; `EmitManagedLocalCleanup`
gets it at the caller's epilogue. FPC's convention is that the CALLEE finalizes
a value parameter.

## Fix sketch

Either release the temp immediately after the call returns (a per-call cleanup,
which is what the interface-argument path already does for a scalar interface
temp), or move the finalization into the callee to match FPC. The first is
smaller and does not change the ABI; the second is the FPC-parity answer and
would need every backend's prologue/epilogue to agree.

Not urgent: the reference is dropped, just late — a lifetime divergence, not a
leak. It becomes urgent if a program relies on destruction timing (a lock held
by an interface, an RAII-ish handle).

## Gate

`make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`, plus the program
above as a test with FPC-matched counts.

## Resolved 2026-08-22

Took the **first** option in the fix sketch — release the temp on the caller's
side — and did it by extending the queue that already existed rather than
inventing a mechanism.

### The queue was already there, one arm short

`IRLowerCallArg` has two neighbouring arms for a by-value managed argument:

- `isComIntfArg` — a bare interface value. Copies with `PXXIntfAssign` and then
  **queues the temp on `PostCallIntfSym`**, which `IRFlushPostCallIntf` drains
  at the end of the enclosing statement.
- `RecordHasManagedFields(argRecId)` — a record with managed fields. Copies
  with `IR_COPY_REC_MANAGED` and queued **nothing**.

Same construct, same lifetime question, adjacent arms, and only one of them
answered it. `normalise-dont-special-case` again: the second copy is the one
that stayed broken.

So the queue now carries a record id alongside the symbol — `REC_NONE` meaning
"a bare interface temp, release with `PXXIntfRelease`", a real id meaning "a
record temp, finalize it". One queue, one boundary, one drain.

### Finalizing without a new IR op

There is no "finalize this record" IR op — scope-exit cleanup is emitted
directly by each backend's epilogue, so adding one would mean six backends. It
is not needed: `IR_COPY_REC_MANAGED` **from a zeroed source** already does
exactly a finalize, because its documented order is *retain source, release
destination, copy*. With an all-nil source the retain is a no-op, the release is
the finalize, and the copy leaves the temp nil.

That last part is what makes the change safe to land partially, the same way the
interface arm's nil-store does: a temp this flush has zeroed is still visited by
the caller's epilogue pass, and releases nothing a second time. A call site whose
statement never flushes keeps precisely the old behaviour.

Target-independent, no backend touched.

### Timing, precisely

End of the enclosing STATEMENT, not the instant the callee returns — the reason
is on `IRFlushPostCallIntf` already: the IR is a linear append list and a call is
emitted through its statement root, so anything appended between the two would
run *before* the call. One step later than FPC, and observationally identical in
every shape measured, including the loop row.

### Verification

`test/test_byvalue_record_arg_lifetime.pas`, byte-identical to fpc 3.2.2 and
unchanged under `-dPXX_HEAP_DEBUG`:

```
main   1     the ticket's own case
two    2     two record args in ONE call — both temps drain at the same boundary
inproc 1     inside a procedure, where the two never diverged (the control)
loop   1     three calls in a loop destroy ONCE, not per iteration
nested 0     an RVALUE argument (Ident(g)) — still holds its reference, as in FPC
```

`nested 0` is the row that would catch an over-eager fix: FPC does not destroy
there either, and a finalize that fired on the wrong temp would print 1.

Gate: `make compiler/pascal26` (fixedpoint, converged after 1 round) +
`tools/gate.sh quick` GREEN.

## Log
- 2026-08-22 — resolved, commit PENDING-COMMIT.
