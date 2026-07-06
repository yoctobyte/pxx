---
prio: 60  # auto
---

# Port cdecl indirect calls (dynamic library loading) to the other targets

- **Type:** feature (Track A — cross codegen / call ABI)
- **Track:** A — `compiler/**`
- **Status:** backlog
- **Owner:** — (Track A)
- **Opened:** 2026-06-25
- **Relation:** follow-up to [[feature-real-dynlib-loader]] (route A landed,
  x86-64). Consumed by any cross-target use of `dynlibs` / `-dPXX_DYNLIB_LIBC`
  and the OpenSSL/TLS path of [[feature-tls-provider-abstraction]].

## Context

`cdecl` on proc types + System V indirect-call marshalling landed on **x86-64**
(c461fce): a `dlsym`'d C function called through a `function(...): R; cdecl`
pointer marshals int->rdi.., float->xmm0.., 16-byte aligned, float return
bridged. Verified live (sqrt/pow/ldexp; OpenSSL loads and reportedly works).

The `ProcCdecl` signature flag and the parser are **target-independent** — they
are already set on every target. Only the **x86-64 `IR_CALL_IND` emitter** honours
the flag; the other backends still use PXX's internal all-integer indirect-call
convention. So a cdecl proc-type call on a cross target silently uses the wrong
ABI (works for int/ptr args that happen to coincide, miscompiles floats / >N args).

## Scope

For each of `i386`, `aarch64`, `arm32` (and later `riscv32`/`xtensa`), teach the
backend's `IR_CALL_IND` to branch on `ProcCdecl[cpi]` and marshal that target's C
ABI for an indirect call:

- **i386:** cdecl = all args on the stack, caller cleans up, result in eax/edx
  (st0 for float). The direct extern path already does this — mirror it through a
  register-held callee.
- **aarch64:** AAPCS64 — int/ptr in x0..x7, float/double in v0..v7, indirect
  result via x8 (sret), stack spill beyond.
- **arm32:** AAPCS — r0..r3 (+ stack), softfp vs hardfp float passing per the
  target's convention; result in r0(:r1).

Reuse each backend's existing **direct external** marshalling (it already encodes
the per-target C ABI); the only delta is obtaining the callee from a runtime
value and a register-indirect call instead of a PLT/GOT call.

## Also: real library-loading test matrix

x86-64 has `test/test_dynlib.pas` + `test/test_cdecl_indirect.pas`. Add
cross-target runs (under each `test-<arch>` once the ABI lands), and a broader
"load a real `.so` and call it" smoke (e.g. libm sqrt/pow, and an OpenSSL
`libcrypto` digest round-trip) to prove the loader end to end. First signal is
good: OpenSSL loads on x86-64.

## Done when

- A `cdecl` proc-type indirect call with float and >6/>4 args marshals correctly
  on i386/aarch64/arm32 (matching each direct-extern ABI), under `make test-*`.
- `test/test_cdecl_indirect.pas` (or a cross variant) passes on each target.
- ESP targets explicitly out of scope here (no real loader yet); note status.

## Not in scope

- Stack spill / by-value structs / varargs through indirect cdecl (also still
  open on x86-64 — track in [[feature-real-dynlib-loader]]).
- PAL `PalDlOpen` primitive abstraction (Track B / dynlib-loader ticket).
