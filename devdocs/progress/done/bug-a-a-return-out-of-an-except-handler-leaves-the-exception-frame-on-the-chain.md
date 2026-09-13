---
slug: bug-a-a-return-out-of-an-except-handler-leaves-the-exception-frame-on-the-chain
title: a return out of an except handler leaves the exception frame on the chain
summary: >
  FIXED 2026-09-14. An `except`/`on E: T do` handler BODY is a protected region
  of its own -- it gets an IR_EXC_ENTER so the caught object survives a raise
  from inside it -- but the region was pushed with no codegen depth, so
  IRLowerCleanupToDepth could not see it and `exit`/`return`, `break` and
  `continue` out of the handler emitted no IR_EXC_LEAVE, no free and no clear.
  The chain head then pointed at a frame in DEAD STACK, and the next UNHANDLED
  raise longjmped into whatever was there -- on a fresh stack, zeroes, so the
  process died at rip=rsp=rbp=0 with NO DIAGNOSTIC AT ALL. Both frontends, no
  --threadsafe needed. The fix registers the handler region on
  ExceptionCodegenDepth with two new parallel arrays carrying the caught-object
  temps, so the early-exit path emits exactly what the fall-through emits.
track: A
type: bug
prio: 80
owner: frank-user
status: done
---

## What it looked like

`lekkerzeilen` died on SIGSEGV at `rip=rsp=rbp=0` after printing its whole
startup banner. Line-stepping under `-g -O2` put the last executed line at
`app.py:834`, `sys.setswitchinterval(0.0005)` -- a `sys` attribute we did not
have, so the correct behaviour there was an AttributeError. The refusal is what
crashed, not the call: the raise read a stale chain head.

The two-line version of the same call refuses cleanly (`rc=217`, the right
message). So did a package-shaped one, and one with `threading` imported, and
one inside a method inside an `if`. **The route mattered and the shape did
not** -- the discriminator was that lekkerzeilen had already returned out of an
`except` handler somewhere earlier in its startup.

## The measurement

At the breakpoint, `gs:` slot 8 (`TLS_SLOT_EXC_TOP`) held `0x7fffffff8760` --
0xb30 bytes BELOW `rsp`, i.e. inside stack that had already been popped. The
frame there was all zeroes, so the unwinder's restore loaded 0 into rip, rsp
and rbp. `rdi` at the fault was `0x7fffffff8768`, the frame address plus 8,
which is what named the restore as the faulting step rather than a `call 0`
(a `call` through a null pointer leaves `rsp` valid).

Reduced to five lines, both frontends:

```python
def h():
    try:
        raise ValueError("x")
    except ValueError:
        return 1            # <-- the leak
print("A", h())
raise KeyError("boom")      # <-- rc=139, nothing printed
```

```pascal
function H: Integer;
begin
  try raise Exception.Create('x');
  except on E: Exception do begin H := 1; Exit; end; end;
end;
begin WriteLn('A ', H); raise Exception.Create('boom'); end.
```

`break` out of the handler does it too. `except: pass` falling out the bottom
does NOT -- the fall-through arm always emitted its EXC_LEAVE.

## Why nothing caught it for so long

**An enclosing `try` hides it completely.** Entering any try overwrites the
chain head, so `try: h(); raise ...; except: ...` around the identical calls
passes on the broken compiler. The stale head is only ever READ by a raise with
nothing above it -- and by then the failure is a silent segfault, so the
observable is the ABSENCE of a diagnostic, which no `expect_same` row over
stdout can see. Every value the reproducers print was correct throughout.

The second defect is a leak on the same path, and it is the same blindness in
the other direction: pin v409 gives `allocs=5411 frees=408 live=5003` where
HEAD gives `frees=5408 live=3` on byte-identical output.

## The fix

`compiler/ir.inc`, `AN_TRY_EXCEPT`: the handler body's `IR_EXC_ENTER` now also
sets `ExceptionFinallyBody[depth] := -1` and `Inc(ExceptionCodegenDepth)`, with
`Dec` before the matching `IR_EXC_LEAVE`. `IRLowerCleanupToDepth` gained the
free and the clear, driven by two new arrays in `defs.inc`
(`ExceptionCaughtObjTmp` / `ExceptionCaughtClsTmp`) that are -1 for every region
that is not a handler body. So an early exit now emits EXC_LEAVE, then
`IREmitCaughtExcFree`, then `IR_EXC_CLEAR` -- exactly the fall-through's
sequence, in the fall-through's order.

## Rows

- `test/test_handler_early_exit_pops_the_exception_frame.pas` -- the crash.
  Asserts the DIAGNOSTIC, not the exit code, because a segfault is nonzero too.
- `test/test_handler_early_exit_frees_the_caught_object.pas` -- the leak, under
  `-dPXX_ALLOC_CENSUS` with `tools/assert_no_leak.sh`. Carries a plain
  fall-out-the-bottom handler as the control against a double free.
- `test/test_nilpy_early_exit_from_except_pops_the_frame.npy` -- return, break,
  continue, `as e`, and a nested handler; values checked against CPython.

All three fail on pin v409 and pass at HEAD.
