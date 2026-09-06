---
track: A
prio: 30
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankA
tags: [erlang, cross-target, i386, aarch64, arm32, skeleton]
blocked-by: []
summary: "test_erlang_skeleton.erl now REACHES main on i386/aarch64/arm32 and computes a WRONG VALUE before faulting -- i386 prints `fact(5) is 1` where native prints 120, then SIGSEGVs partway through the next line; aarch64 and arm32 SIGILL. Measured 2026-09-06 on the compiler built by `refactor(A): one mirror pair for the entry stub, adopted by the three skeleton drivers`, with the frontend's x86-64-only refusal temporarily lifted. THIS IS A NEWLY VISIBLE DEFECT, NOT A NEW ONE: until the entry-stub extraction landed, every non-x86-64 Erlang binary died on a hand-written x86-64 program tail before its first syscall, so nothing it printed could be observed. Rust and Zig came out of that same experiment producing output IDENTICAL to their native runs on all three targets, which is what makes this Erlang's own defect and not a shared one. The refusal in eparser.inc stays in place and is load-bearing until this is fixed."
---

# The Erlang skeleton computes a wrong value cross-target

## Measured 2026-09-06, compiler sha256 `70aadc213f6d`

On the tree carrying `refactor(A): one mirror pair for the entry stub, adopted by
the three skeleton drivers` — cited by SUBJECT rather than by a sha, because at
the time of writing that commit was local and unpushed, and `tools/sync.sh`
rebases nearly every sync, so any sha quoted here before the push is the doomed
one.

Taken with `eparser.inc`'s `if TargetArch <> TARGET_X86_64` refusal replaced by
`if False then` in the working tree, rebuilt, measured, then reversed by
re-editing that one line. The post-experiment rebuild reproduced the
pre-experiment binary digest exactly (sha256 `e38b3d05b304`), which is the control on the
restore.

| target | `test_erlang_skeleton.erl` |
| --- | --- |
| x86-64 | `fact(5) is 120` / `fib(10) is 55` / `classify: 1 2 3 4` / `div gives 5 rem 1` |
| i386 | `fact(5) is 1`, then `fib(10) is ` and **SIGSEGV** (rc 139) |
| aarch64 | **SIGILL** (rc 132) |
| arm32 | **SIGILL** (rc 132) |
| riscv32 | does not compile |

`fact(5)` answering **1** rather than 120 is the interesting row, and it is a
WRONG VALUE and not a crash: the program got into `main`, ran a recursive
multi-clause function to completion, and printed a plausible number. The fault
arrives on the next line. So there are at least two things here and the quiet
one is first.

## Why this is only visible now, and why that matters for ranking

Before that commit, `eparser.inc:543` emitted four literal x86-64 instructions
(`call main; xor edi,edi; mov eax,231; syscall`) as the whole program tail,
unconditionally, with no `case TargetArch of` around them. Every non-x86-64
binary therefore died on an illegal instruction **before its first syscall** —
so no output existed to be wrong. The tail was not masking a subtle case; it was
masking the entire program.

**Rust and Zig are the control, and they came out clean.** Same experiment, same
compiler, same three targets: `test_rust_else_if` exits 20 everywhere,
`test_rust_advanced` and `test_zig_skeleton` produce output byte-identical to
their native runs on i386, aarch64 and arm32. Three frontends shared one broken
tail; with the tail shared and correct, two of them work and one does not. That
is what makes this Erlang's own defect rather than a residue of the extraction.

## Do not lift the refusal to work on this

`eparser.inc`'s x86-64-only refusal stays. It is the reason this has never
shipped as a wrong binary, and the honest sequence is fix-then-narrow — the same
ordering the entry-stub ticket used, and for the same reason: a refusal removed
before the thing it refuses works turns a loud stop into a plausible wrong
answer. `fact(5) is 1` is exactly what that looks like.

## Acceptance

**Assert the CROSS-TARGET RELATION, not a per-target constant**: the skeleton's
output must be identical on every target the frontend accepts, compared whole
against the native run. That row carries no expected text, cannot pass by
agreeing with a default, and prints the same thing everywhere when it is right.

**And it must be able to fail.** Today it does, on three targets — take the
reading before the fix and keep it in the ticket, because a row added afterwards
that passes on the broken compiler is not testing what it claims.

## The riscv32 compile failures — HALF OF THIS IS NOW ANSWERED, AND IT WAS NOT ZIG

This section originally said `test_zig_skeleton.zig` and
`test_erlang_skeleton.erl` both fail to compile for riscv32, undiagnosed. The
Zig half is fixed and its cause was not the Zig frontend: riscv32 calls
builtinheap's `PXXWriteDecW` for every integer write and the driver pulled no
unit at all
(`bug-a-a-frontend-cannot-see-that-a-backend-calls-library-routines-it-never-mentions`).
Zig now runs identically to its native output on i386, aarch64, arm32 AND
riscv32.

**Worth keeping because I nearly wrote the wrong ticket from it.** The
measurement "Zig does not compile for riscv32" was true, and a per-target
exclusion drafted from it would have recorded riscv32 as the Zig frontend's
problem. A per-target exclusion written from a failing compile records the
target the defect was VISIBLE on, which is not the same as the target — or the
component — it is about.

`test_erlang_skeleton.erl` is very likely the same missing unit pull, since
`eparser.inc` pulls nothing either and the program prints integers. NOT fixed
and NOT confirmed: Erlang is separately broken cross-target (this ticket), and
fixing its unit pull would only let it reach the wrong value faster.

## A second Zig finding from the same matrix, undiagnosed

`test_zig_advanced.zig` SIGILLs on aarch64, arm32 and riscv32 — dies before any
output, where `test_zig_skeleton.zig` and `test_zig_structs.zig` are identical
to native on all four. So something in the wider Zig surface still emits an
instruction those targets do not have. Noted, not diagnosed; it is not covered
by `test-skeleton-frontends-cross-target`, which carries only the two green Zig
programs, and that omission is deliberate rather than accidental.
