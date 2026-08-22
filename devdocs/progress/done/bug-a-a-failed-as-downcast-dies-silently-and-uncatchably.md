---
slug: bug-a-a-failed-as-downcast-dies-silently-and-uncatchably
track: A
prio: 60
status: done
commit: 0a40b8a14
---

# A failed `as` downcast exits 1, prints nothing, and cannot be caught

```pascal
type TA = class end; TB = class(TA) end; TC = class(TA) end;
var a: TA;
begin
  a := TB.Create;
  try
    WriteLn((a as TC).ClassName);
  except
    on E: Exception do WriteLn('caught ', E.ClassName);   { never runs }
  end;
end.
```

FPC prints `caught EInvalidCast`. PXX printed **nothing at all** and exited 1.

## The whole family was already built; this was the one member left out

`compiler/ir.inc`'s `AN_AS_CAST` lowering computes the match, then on mismatch:

```pascal
IRAppend(IR_TERMINATE, IRAppend(IR_CONST_INT, ..., 1, ...), -1, -1, AN_HALT, 0);
```

An inline `Halt(1)`. Meanwhile every other checked operation in this compiler
goes through a builtin trap with a sysutils-installed hook — `PXXNilRef`,
`PXXDivZero`, `PXXOverflow`, `PXXRangeChk`, `PXXVariantError` — each of which
prints an FPC-shaped runtime-error line on its own and *raises a catchable
exception* once sysutils is linked. Five members, one design, and the sixth site
never joined it.

That it was `as` and not one of the others is the part worth stating: a nil
deref or a divide by zero is a mistake, and dying is a defensible answer. **A
failed downcast is not a mistake — it is the outcome `as` exists to let you
handle.** So the one construct in the family whose failure is *expected* was the
one whose failure could not be observed. A program that wrote exactly the right
handler died with no message and an exit code that says nothing.

Note what is and is not FPC parity here. `devdocs/dev/`-level policy (CLAUDE.md,
user 2026-08-21) is that *how a program dies* stays ours — error numbers, exit
codes and fault text are not parity targets. **Catchability is not how it dies,
it is whether it dies**, and that is language semantics: `try ... except` around
an `as` either works or the language does not have safe downcasts. The message
and the 219 follow FPC only because the surrounding family already does.

## The fix

```
compiler/builtin/builtinheap.pas   PXXInvalidCast + PXXInvalidCastHook,
                                   copied from the family: print
                                   "Runtime error 219 (invalid typecast)"
                                   + Halt(219), or a raise past it.
compiler/ir.inc  AN_AS_CAST        the mismatch arm calls it; a build with no
                                   builtinheap keeps the inline terminate, the
                                   same lax fallthrough the nil/range checks take.
lib/rtl/sysutils.pas               EInvalidCast, SysRaiseInvalidCast, and the
                                   hook install beside the other five.
```

Landed as **two commits with a pin between them**, because the hook variable
lives *inside the compiler binary* while the unit that installs it is source the
pinned compiler must be able to compile. Commit 1 (`a687bb877`) is additive to
the builtin unit and needs no pin; `make stabilize-fast && make pin` blessed it
as v374; commit 2 wires sysutils. Getting that order wrong breaks every Track B
build until the next pin.

## Verification

`test/test_failed_as_downcast_is_catchable.pas`, byte-identical to
`fpc 3.2.2 -Mobjfpc -O1`:

```
good TB                                   the success path, unchanged
caught EInvalidCast: Invalid type cast    the typed handler
generic EInvalidCast                      on E: Exception takes it too
deep finally / outer                      the raise crosses a frame and runs its finally
nil ok                                    `nil as T` is nil, NOT a failure
total ok 4 / 4
```

The `nil` row is the one that could regress quietly: the lowering lets nil pass
through *before* the match test, and a trap that fired on nil would turn a legal
idiom into a runtime error.

Found by the type-conversion/cast differential family, not by a ticket.

Gate: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick` GREEN, both
commits.
