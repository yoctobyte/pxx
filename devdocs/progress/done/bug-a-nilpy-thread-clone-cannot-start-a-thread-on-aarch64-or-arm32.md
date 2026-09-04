---
prio: 40
track: A
type: bug
status: done
summary: "THREE defects, one report. Two were in the test source -- `SYS_mmap = 9` is x86-64's number (link/linkat elsewhere) and the flag set omitted CLONE_SYSVSEM, which Linux does not require and qemu-user does -- and fixing both makes the two clone rows pass on x86-64, i386, aarch64 and arm32. The third is a real compiler bug on EVERY target: a computed NilPy expression passed to __pxxrawsyscall / __pxxclone / __pxxcoswitch / __pxxatomic_* arrived as the ADDRESS of its promo-int or Variant slot, not as a machine word. The clone rows cannot see that one -- they pass on the unfixed pin on all four targets -- so it has its own row now. FIXED."
owner: frankb-78
---

# NilPy thread-clone cannot start a thread on aarch64 or arm32

Measured 2026-09-03, HEAD and the pin, same result on both:

| target | output |
| --- | --- |
| x86-64 | `tid nonzero = True` / `child ran = 7` |
| i386 | same, 20/20 |
| aarch64 | **`tid nonzero = False`** / `child ran = 0` |
| arm32 | **`tid nonzero = False`** / `child ran = 0` |

`tid > 0` is false, so `__pxxclone` itself returned <= 0 — the failure is at or
before the syscall, not in the child.

**NOT the raw `SYS_mmap = 9` in the test source**, which was the first guess:
9 is the x86-64 mmap number and aarch64 wants 222, arm32 192. Rebuilt with the
right numbers per target and the answer is unchanged, so the mmap is not what
fails (or not the only thing).

**Reproduced on `stable_linux_amd64/default/pinned`**, so nothing recent caused
it and no bisect will find it.

Not diagnosed further. The likely places are `__pxxrawsyscall`'s argument
marshalling on those targets and the clone flag set, but that is a guess and it
is written here as one.

**Pascal threading on both targets is fine** — `test_tthread`,
`test_parallel_for_lang` and `test_clone_entry_with_a_hidden_result` all pass
there, so the trampoline and the PAL work; this is specific to the NilPy
program's raw-syscall route.

## Wiring

`test-nilpy` compiles this source natively only. Adding aarch64/arm32 rows is
part of the fix, not a separate ticket — a target with no row is a target with
no report.


## Resolved 2026-09-04 (frankb-78)

**Three defects, and the report named none of them.** `tid nonzero = False` on
two targets was the visible half of a two-target TEST bug; the compiler bug it
was standing next to is on all four and was invisible here.

### 1 + 2 — the test source (why aarch64 and arm32 said False)

`SYS_mmap = 9` is the x86-64 number. On i386 and arm32 mmap2 is 192, on aarch64
mmap is 222, and 9 there is `link`/`linkat`, which answers -EFAULT for these
arguments — so `stk` was -14 and the "stack" was 1048562. **The row still
PASSED on i386**, because Linux accepts any writable address as a child stack.
Both files now probe 9 / 192 / 222 and take the first answer that looks like a
mapping; every wrong number in the list answers -EFAULT or -EINVAL for these
arguments, so probing costs an errno.

The flag set omitted `CLONE_SYSVSEM`. Linux is happy without it; **qemu-user is
not** — it implements `clone` only for the complete thread flag set and answers
EINVAL for any subset. aarch64 and arm32 are the emulated targets, which is the
whole of the "cross-target split". `lib/rtl`'s `PXX_CLONE_THREAD` has carried
SYSVSEM all along, which is why Pascal threading worked on those two and this
did not.

The ticket body's *"rebuilt with the right numbers per target and the answer is
unchanged"* was true and misleading: the mmap number is necessary and not
sufficient, and testing it alone exonerated it.

### 3 — the compiler bug, all targets (`compiler/pyparser.inc`)

Each of these intrinsics takes a **raw machine word** per argument. A NilPy
expression that has been through arithmetic, or that came back from a function,
is a promotable-int or Variant SLOT, and its machine word is the slot's
address. `PyUnboxRangeBound` already did exactly the needed coercion for `range`
bounds, so it is renamed `PyUnboxToMachineInt` and applied at every argument
site of the five intrinsics; a range bound is now one caller of five.

### The two clone rows cannot guard the compiler fix — measured, not assumed

On **pin v403** (`c31d03b202da`, no fix), with the two test bugs repaired, both
clone rows print their expected output on **all four targets**. The bogus slot
address works as a child stack. So the fix gets its own row,
`test_nilpy_intrinsic_arg_is_a_machine_word.npy`, built on an atomic counter
rather than a syscall (syscall numbers are per-target; atomics are not).

Its positive control, drawn from the whole population — the same source under
the pin:

| target | pin v403 | fixed |
| --- | --- | --- |
| x86-64 | rc=139 (SIGSEGV) | `a = 0 / b = 5 / c = 10` |
| i386 | `a = 2 / b = 7 / c = 136206839` | same |
| aarch64 | rc=139 (SIGSEGV) | same |
| arm32 | `a = 2 / b = 7 / c = 137542135` | same |

**The first probe for this was a guard that could not fail** and is recorded in
the test's header: `__pxxrawsyscall(SYS_exit, 42 + zero)` read through the exit
status. A slot address is 16-byte aligned, so its low byte is 0 — and 0 is also
"exited normally". Broken and correct produced the same number on both
compilers, and it read as *"the fix does nothing"*. `dup(0)` separated them
(-9 vs 3) because there the failure value cannot be the success value.

### Wiring

`test-threads` now runs both clone rows on x86-64, i386, aarch64 and arm32, and
the new row on the same four.

### Gate

`make compiler/pascal26` converged; `tools/gate.sh quick` GREEN with the FPC
seed canary RUN (gated before the commit, on a dirty `compiler/**`);
`PXX_ALLOW_FULL_SUITE=1 make test-threads` green end to end — the quick tier
does not run `test-threads`, and every row added here lives in it.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 43a8f2470.
