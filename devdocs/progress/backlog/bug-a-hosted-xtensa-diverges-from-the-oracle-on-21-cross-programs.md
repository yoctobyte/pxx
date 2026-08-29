---
track: A+S
type: bug
prio: 40
status: open
found: 2026-08-30
found-by: frankS
---

# Hosted xtensa diverges from the x86-64 oracle on 21 of 142 cross programs

The first differential sweep xtensa has ever had. Of the 142 sources
`test-riscv32` uses, **55 match the x86-64 oracle exactly** (now wired as
`make test-xtensa`), **66 fail to compile** for xtensa at all, and **21 compile,
run, and produce the wrong answer.** This ticket is the 21.

Sweep conditions: `--target=xtensa --platform=posix --xtensa-soft-mulhigh`,
Call0, `qemu-xtensa` 10.2.1, compiler at `e866cc16d4fe`. Both flags are
load-bearing: without `--platform=posix` syscalls lower to `PAL_ERR_UNSUPPORTED`,
and without `--xtensa-soft-mulhigh` any numeric output SIGILLs.

## The 21

| program | xtensa | x86-64 |
| --- | --- | --- |
| `test_arm32_record_byval_wide` | `1 0` | `1 2` |
| `test_array_of_const_types` | `vt0: 42` | `vt0: 42` |
| `test_asm_ifdef_multiarch` | `0` | `42` |
| `test_cross_aggregate_stackargs` | `qemu: uncaught target signal 7 (Bus error) - c` | `3 7 5` |
| `test_cross_dynarray` | `10 20 30 len=3` | `10 20 30 len=3` |
| `test_cross_float` | ` qemu: uncaught target signal 7 (Bus error) - ` | ` 3.5000000000000000E+000` |
| `test_cross_float_return` | `qemu: uncaught target signal 7 (Bus error) - c` | `2.5000` |
| `test_cross_managed_aggregate_locals` | `\x05hello\x06 world\x04text\xac#\t\x08\x04\xc6\x1b\t\x08\x04\xcc#\t\x08\xbc#\t\x08L%\t\x08\x04\x03d%\t\x08` | `hello 42` |
| `test_cross_multidim3d` | `var3d=1476000000 c123=123000000` | `var3d=1476000000 c123=123000000` |
| `test_cross_openarray_string` | `count=2` | `count=2` |
| `test_cross_param_2darray` | `vsum=14` | `vsum=14` |
| `test_cross_stack_params` | `six=123456` | `six=123456` |
| `test_cross_syscall` | `0` | `1` |
| `test_cross_trunc_round_saturate` | `t+1e30=2147483647 r=2147483647` | `t+1e30=9223372036854775807 r=92233720368547758` |
| `test_cross_var_string_param` | `varlen=545267744` | `varlen=5` |
| `test_interface_arc` | `hello` | `hello` |
| `test_interfaces_multi_secondary` | `direct` | `direct` |
| `test_managed_local_release_reuse` | `ok   ansistring local` | `ok   ansistring local` |
| `test_shortstring_trunc` | `aaaa 4` | `aaaa 4` |
| `test_single_in_aggregate` | `qemu: uncaught target signal 7 (Bus error) - c` | `1.5 2.5 3.5` |
| `test_u64_to_double` | `assign-ok` | `assign-ok` |

(First line of output only; several diverge further down.)

## Three clusters, and the first one is a known signature

**1. A heap handle leaking where an integer belongs.** `test_cross_var_string_param`
prints `varlen=545267744` against the oracle's `varlen=5` — and `545267744` is
the *same shape of value* that ansistring `=` returned before
[[bug-a-xtensa-has-no-ordered-string-compare-and-sorts-by-heap-handle]]: a live
heap address rendered as a number. `Length()` of a `var string` parameter is
handing back the handle instead of the length. Start here — it is the cluster
with a known cause nearby, and `firstchar` being garbage in the same run says
the parameter's indirection is what is wrong, not `Length` itself.

**2. Bus errors and segfaults, all involving aggregates or floats:**
`test_cross_aggregate_stackargs`, `test_cross_float`, `test_cross_float_return`,
`test_single_in_aggregate`, and `test_cross_multidim3d` (which prints its first
line correctly, then segfaults on a 3-D array *parameter*). A crash is the cheap
case and these have locations; take them before the quiet ones.

**These are NOT Track F.** They are crashes and wrong control flow that happen to
live in float code — `rank the mechanism, never the datatype`. Float *accuracy*
would be F; a bus error is an ordinary bug.

**3. Quiet wrong values:** `test_cross_syscall` answers `0` where the oracle says
`1`, `test_cross_stack_params` loses arguments past the register set,
`test_shortstring_trunc`, `test_u64_to_double`, the two interface tests. These
are the expensive class — no crash, a plausible number, far from the cause.

## Deliberately not skipped

The 21 are excluded from `make test-xtensa` by NAME, not by a silent filter, and
this ticket is cited in that target's header. A differential that quietly drops
its own failures is precisely how xtensa reached 2026 with a backend nobody had
ever executed.

## Bound

Object-level plus observable output, hosted profile, Call0 only, at
`e866cc16d4fe`. Windowed is a separate and worse story —
[[bug-a-xtensa-windowed-abi-faults-on-frozen-strings-copy-and-dynarray-setlength]].
The 66 compile failures are not covered here; they are missing features rather
than wrong answers, and want their own scoping pass.
