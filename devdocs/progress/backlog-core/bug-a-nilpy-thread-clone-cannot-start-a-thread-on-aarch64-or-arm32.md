---
prio: 40
track: A
type: bug
status: open
summary: "test_nilpy_thread_clone.npy prints `tid nonzero = False` on aarch64 and arm32 -- __pxxclone returns <= 0, so no thread is created and the child never runs. Reproduces on the PINNED compiler too, so it is not a regression; the Makefile wires this test on x86-64 and i386 only, which is why nothing reports it."
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
