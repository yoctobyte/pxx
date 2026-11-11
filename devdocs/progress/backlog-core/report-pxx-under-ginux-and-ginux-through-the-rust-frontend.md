---
track: A
prio: 20
type: feature
blocked-by: []
summary: "Side quest 2026-11-11, both halves. (1) pxx binaries run under Ginux, a Rust userspace kernel that intercepts Linux syscalls (github.com/gmkurtzer/ginux, HEAD e16946a). Every sampled single-threaded program, Pascal and NilPy, matched native output. Ginux denies clone, so threads fail, and with a read-only root, file writes fail. (2) Ginux's own Rust does not go through pxx's Rust frontend yet: 7 of 35 construct probes pass; ginux-core (705 lines) parses whole, then stops at `const fn`. The ranked gap list is below."
status: open
owner: unassigned
---

# pxx under Ginux, and Ginux through pxx's Rust frontend

Ginux began as a bootable UEFI kernel, kept on its `bootable-kernel`
branch. It is now a **userspace kernel**: an ordinary Linux process that runs
a workload under ptrace (or a small interpreter) and, for each syscall,
decides whether to emulate it, mediate it, or deny it under a versioned
per-instance "contract". It has no external crates and is 27 k lines of
`no_std`-style Rust. It builds with rustc 1.99 in 26 s.

Scratch work, not in this repo: `~/ginux-side/` (src = Ginux checkout,
pxx/run.sh = the run harness, rs/probes/run.sh = the Rust probes).

## (1) pxx programs under `ginux launch` (ptrace-native backend)

How it was run: `ginux launch CONFIG ROOT`, where ROOT is a directory holding
the pxx binary as init. Launch chroots. On plexus,
`kernel.apparmor_restrict_unprivileged_userns = 1` strips that capability
from `unshare -r` and from bwrap, so the working route is
`podman unshare ginux launch ...` (newuidmap; setgroups allowed). On borg,
`unshare -r` chroots but its setgroups drop fails, and borg has no newuidmap.

| program | result |
|---|---|
| hello, test_x64_register_hole_paths | same output as native |
| test_exception_finally, _typed, _unhandled (rc 217) | same |
| three NilPy programs (classes, str.format, exception str) | same |
| test_thread_heap (--threadsafe) | same (copes with clone failing) |
| test_thread_clone | rc 1: clone denied, reported |
| test_thread_sigaltstack | SIGSEGV: sigaltstack denied, so a stack overflow is a raw kill |
| test_exception_threads_race | hangs: the TEST spins on `ready` without checking BeginThread's result |
| NilPy write to /tmp | PermissionError: openat for write is denied (root is host-path-read-only) |
| reading a file in the root, os.listdir, os.getpid | work |
| time.time() | 0.0: clock_gettime is denied |

Syscalls pxx issues that this contract DENIES (ENOSYS): getrlimit (97),
gettid (186), sigaltstack (131, twice at start-up), clock_gettime (228),
clone (56), openat for write (257). pxx tolerates the first three silently,
which is right. arch_prctl and rt_sigaction are mediated; write is mediated
to the console.

For pxx:

- `mimic_time.ReadClock` returns 0.0 on a failed clock read. That is a
  documented choice ("revisit when something actually wants the error").
  Ginux is the first real environment where the clock is denied. A NilPy
  program measuring time there gets 0.0 with no error. CPython would raise
  OSError. Revisit when someone runs under Ginux, not before.
- Threads: BeginThread's failure path works (test_thread_clone reports it).
  Nothing to fix in pxx.

For Ginux (NOT reported upstream; posting needs the owner's yes):

- `ginux launch` writes audit lines with `[audit] enabled = false`, into
  the same stderr stream as the workload, mid-line.
- `ginux runtime ELF` (the interpreter) has a 256 KB address space at
  0x10000 and a 16 KB stack, so a normal static binary (pxx links at
  0x400000) is rejected as `invalid-segment`. That is by design: it is a
  gate-3 demonstrator.

## (2) Ginux's Rust through pxx's Rust frontend (compiler/rparser.inc)

The first error per crate (each is a single no_std `lib.rs`):

| crate | lines | stops at |
|---|---|---|
| ginux-core | 705 | parses whole; then `const fn` (with a test main) |
| ginux-vfs | 1101 | enum variant form |
| ginux-process, -devices, -runtime | 1903/689/906 | `[T; N]` with a const N |
| ginux-contract | 2614 | field type |
| ginux-kernel-views | 637 | `impl` on a non-name type |
| ginux-instance | 2879 | attribute form |

35 one-construct probes, each compared against rustc 1.99. OK: const
arrays, `#[derive(PartialEq)]` compare, tuple enum variants, if let, `as`
shadowing, `[x; N]` struct arrays. NOT compiling, ranked by rough use count
in Ginux:

| construct | Ginux uses (grep, rough) |
|---|---|
| byte strings `b"..."` / `b'x'` | ~2600 |
| `?` on Result | ~980 |
| closures | several hundred (the grep overcounts) |
| raw pointers (`as_ptr`, `.add`, `*const`) | ~350 |
| slice ranges `x[a..b]`, `copy_from_slice` | ~290 |
| `.ok_or` / `.map_err` / `.unwrap_or` | ~260 |
| `.iter()` and friends on slices | ~250 |
| `checked_` / `wrapping_` / `saturating_` | ~130 |
| `matches!` | ~90 |
| `match` as an EXPRESSION | ~80 |
| `const fn` | ~70 |
| `from_le_bytes` / `to_le_bytes` | ~60 |
| `try_from` | ~55 |
| `[T; N]` with a const N | ~45 |
| generic fns with trait bounds | ~40 |
| `asm!` | 21 |
| `static mut`, trait impls | 14 each |

Also failing: methods with `&self` in some shapes (impl_method and trait_impl
probes, "expected ')'"), tuple return types, struct update syntax, loop with
break value, while let, labelled break.

What it would take: `match`-as-expression, `const fn` and const-N array
lengths are frontend-local. `?`, Option/Result combinators, slice methods
and closures are a runtime-and-typing job.

## Acceptance (if this is ever picked up)

- ginux-core's 9 tests, flattened into a main (`~/ginux-side/rs/flatten.py`),
  give the same output under pxx as under rustc.
