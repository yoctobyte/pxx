---
prio: 55
track: A
type: bug
status: open
summary: "A NilPy `def` used as a __pxxclone entry gets its `arg` parameter as a RAW MACHINE WORD, but a NilPy parameter is a by-reference Variant -- so the callee dereferences the value as an address. `__pxxclone(flags, stk, worker, 41, 0)` + a worker that reads `arg` is a deterministic SIGSEGV; a worker that ignores it is fine, which is why the existing test never saw it."
---

# A NilPy clone entry receives a raw word where it expects a Variant address

The clone trampoline's contract is `entry(arg)` with `arg` a machine word in the
first integer argument register. A NilPy `def` compiles to
`function(const arg: Variant): Variant` and **every Variant parameter is passed
by REFERENCE** (`PyCompileLambdaBody`: `IsRef := TypeKind = tyVariant`), so the
callee reads the word as the ADDRESS of a Variant and dereferences it.

Measured 2026-09-03, native x86-64, HEAD + the hidden-destination fix:

```python
def worker(arg):
    global seen
    seen = arg + 1

tid = __pxxclone(flags, stk + 1048576, worker, 41, 0)
```

3 of 3 runs SIGSEGV (rc=139), nothing printed. The same program with a worker
that never mentions `arg` runs 200/200.

**This is the second half of the entry-ABI mismatch.** The first was the RESULT
(`regression-test-threads-test-nilpy-thread-clone-2`, fixed:
the stub now hands every entry a valid hidden-destination scratch). This is the
ARGUMENT, and the stub cannot fix it — the trampoline has one contract and the
callee has another, so the adaptation belongs where the callee is known.

`test/test_nilpy_thread_clone.npy` passes `0` and its worker ignores `arg`, so
the tree's only NilPy thread test cannot reach this.

## The shape of the fix, not decided here

The trampoline must keep exactly one contract (that is what makes it work for
Pascal, C, Rust and Zig entries alike), so the adaptation is a THUNK: where the
`__pxxclone` arm resolves a bare def name to `AN_PROCADDR`
(`pyparser.inc`, the `nArgs = 2` guard), point it instead at a synthesized
`procedure $pyclonethunk_N(arg: Pointer)` whose body is `realproc(<arg boxed as
a Variant>)`. `PyGetOrMakeCallableWrapper` is the working model: `RegisterProc`
plus the `PyPendLamTok = -1` hand-built-body queue that `PyCompileLambdaBody`
drains. It would need a third body shape (a PROCEDURE with one machine-word
parameter) and a second sentinel.

**Do not "fix" it by making the entry's parameter by-value** — that changes the
ABI of every NilPy def, which is the flip-sized change this is not.

## Acceptance

The program above prints `seen = 42`, on every threading target, plus the
existing `test_nilpy_thread_clone.npy` row unchanged.

[[regression-test-threads-test-nilpy-thread-clone-2]]
