---
track: A
prio: 30
type: bug
blocked-by: []
status: done
found-by: frankd-90 (2026-09-28; the only cause of the full-tier red test-skeleton-frontends-cross-target on i386, test_rust_option.rs and test_rust_result.rs)
tags: [rust, i386, exit-status, cross-target]
summary: "A Rust `fn main()` with no `->` exited 81 on i386, with the right output. A unit fn is registered tyInteger with a Result slot nothing writes, and the driver always exited through EmitExitReg, so the status was whatever the result register held: 0 on x86-64, aarch64, arm32 and riscv32, 81 on i386. The driver now asks RMainReturnsUnit (a depth-0 prescan of main's signature, since the exit sequence is emitted before the parse) and exits a constant 0 for a unit main, as the Zig driver does for `fn main() void`."
owner: ""
---

# A Rust unit `fn main()` exits 81 on i386

```
$ printf 'fn main() {\n}\n' > t.rs
$ pascal26 --target=i386 t.rs t && qemu-i386 ./t; echo $?
81
```

It happened on v448, v449 and HEAD. aarch64, arm32 and riscv32 gave 0.

## Cause

`RRegisterFnSignatureAt` registers a unit fn as tyInteger, with an unused
Result slot ("same trick C's void uses"). The driver's tail was
`EmitEntryStubCall; EmitExitReg`, so it exited with main's return register,
which nothing had written. The Zig driver had already solved the same case
with `if mainIsVoid then EmitExit(0) else EmitExitReg`. Rust could not ask the
registered signature, because its exit sequence is emitted before any
signature is registered, so `RMainReturnsUnit` reads main's tail from the
tokens with the same depth-0 walk `RRegisterFnSignatures` uses.

## The other skeleton frontends

Measured 2026-09-28 on i386, exit status against the native run:

- the other 11 programs in test-skeleton-frontends-cross-target agree, or are
  refused on purpose ("the skeleton supports");
- Zig exits a constant 0 for a void main, and Erlang always exits a constant
  0;
- C `int main(void) {}` and `void main(void) {}` exit 0 on x86-64, i386, arm32
  and riscv32. For `int main` that matches gcc.

Rust was the only driver on this path.

## Measured (fixedpoint 1634f6483109)

- `test/test_rust_unit_main_exits_zero.rs` exits 0 on x86-64, i386, aarch64,
  arm32 and riscv32. The pinned v449 exits 81 on i386.
- `fn main() -> i32 { 42 }` still exits 42 on all five.
- The skeleton row's comparison, replicated by hand, one target at a time:
  every (program, target) pair matches its native run, output and rc. With
  the new test that is 52 pairs, and the floor is raised from 48 to 52.
