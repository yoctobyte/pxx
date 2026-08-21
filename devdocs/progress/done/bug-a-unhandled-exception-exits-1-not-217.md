---
track: A
prio: 45
type: bug
blocked-by: []
summary: "A program killed by an UNHANDLED exception exited 1 instead of FPC/Delphi's 217, so no shell, Makefile or test harness could tell an unhandled raise from a program that deliberately returned failure. RunError(217) was already correct — only the exception runtime's own terminal path disagreed. Fixed for all seven backends at once. Found by an exception-semantics differential against FPC 3.2.2."
---

# An unhandled exception exited 1, not 217

- **Type:** bug (silent wrong EXIT STATUS; the message on stderr was right) —
  Track A (`compiler/exception_emit.inc`, all backends).
- **Status:** done
- **Opened:** 2026-08-21, from a 35-program exception-semantics differential
  against FPC 3.2.2 (raise/finally/re-raise/handler-filter/unwind cross product).
- **Closed:** 2026-08-21.

## Symptom

```pascal
program x1;
uses SysUtils;
begin
  WriteLn('before');
  raise Exception.Create('unhandled');
end.
```

```
$ ./fpc_x1; echo $?      -> 217
$ ./pxx_x1; echo $?      ->   1
```

Both print a sensible message; only the status differs. The same 1-vs-217 split
showed for an exception raised two frames down, and — the case that actually
bites — for a **division by zero in a program that uses SysUtils**, where the
fault is converted into `EDivByZero` and therefore leaves through this same
terminal path. FPC exits 217 there; pxx exited 1.

Why it matters: 217 is the documented FPC/Delphi runtime-error code for
"unhandled exception", and 1 is the single most common "I failed" status a
normal program returns. Collapsing the two makes `prog || handle_crash` and
every harness that branches on `$?` unable to distinguish a crash from an
ordinary failure. Nothing was wrong with the *diagnosis*, so this could sit
unnoticed indefinitely — it is only visible to a caller, never to a reader of
the output.

## Root cause

`EmitExceptionRuntime` (`compiler/exception_emit.inc`) ends each backend's
unhandled path with a bare `EmitExit(1)` — seven of them, one per backend arm
(x86-64, i386, arm32, aarch64, riscv32, xtensa Call0, and the windowed-xtensa
stub). The literal was never revisited after the message-printing block was
added around it, and each new backend copied the number from the one before.

`RunError(217)` exits 217 correctly, and `--fpc-mem-errors` exits 216 correctly,
which is why the gap survived: the two *neighbouring* status paths were both
already FPC-faithful, so nothing pointed at this one.

## Fix

One named constant, seven call sites:

```pascal
{ compiler/defs.inc }
EXITCODE_UNHANDLED_EXCEPTION = 217;
```

Every `EmitExit(1)` in `exception_emit.inc` now reads
`EmitExit(EXITCODE_UNHANDLED_EXCEPTION)`. Naming it is the point — the number
had to be right in seven places, which is exactly the shape that drifts
(`normalise-dont-special-case`). The bare-metal arms (xtensa Call0, ESP
riscv32) are included even though an exit status is meaningless there: one
constant beats one exception to the rule.

## Verification

`test/test_unhandled_exception_exit_code.pas`, wired into `test-core`, runs one
binary in three modes and requires 217 from each:

| mode | shape |
| --- | --- |
| `plain` | `raise` in the main body |
| `proc` | `raise` two frames down |
| `divzero` | `a div 0` with SysUtils linked, i.e. the fault-to-exception path |

All three match FPC 3.2.2 exactly (status *and* the stderr line beginning
`before`). Gate: `make compiler/pascal26` fixedpoint + `tools/gate.sh quick`
GREEN.

## Notes for later

The same differential turned up two more, filed separately:

- `ExceptObject` is not implemented (`undefined variable (ExceptObject)`), even
  though `ExceptAddr` is, and `BSS_EXC_OBJ` already holds exactly what it needs
  — see `feature-a-exceptobject-intrinsic`.
- Assertions are ON by default in pxx and OFF by default in FPC (`-Sa`), so
  `Assert(False)` raises here and vanishes there. With `-Sa` the two agree line
  for line. That is a dialect default, not a defect — recorded in
  `decide-assertion-default-vs-fpc` for the owner to rule on.
