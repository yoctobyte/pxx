---
prio: 55
track: A
type: bug
status: done
summary: "A NilPy `def` used as a __pxxclone entry gets its `arg` parameter as a RAW MACHINE WORD, but a NilPy parameter is a by-reference Variant -- so the callee dereferences the value as an address. `__pxxclone(flags, stk, worker, 41, 0)` + a worker that reads `arg` is a deterministic SIGSEGV; a worker that ignores it is fine, which is why the existing test never saw it."
owner: frankb-78
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

## FIXED (frankB, 2026-09-03) — a thunk, because the trampoline keeps ONE contract

`__pxxclone`'s trampoline is reached by Pascal, C, Rust and Zig entries as well
as NilPy ones, so its contract — `entry(arg)`, a raw machine word in the first
integer argument register — is the thing that must not move. The adaptation goes
where the callee is KNOWN, which is the `__pxxclone` arm of the NilPy factor
parser.

`PyGetOrMakeCloneThunk(realPi)` registers (and caches by name) a
`procedure $pyclonethunk_N(arg: Pointer)` whose body is `REALPROC(Int64(arg))`,
hand-built on the same pending-body queue as the callable-value wrappers
(`PyPendLamTok = -2`, a second sentinel beside the wrapper's `-1`) and drained by
`PyCompileLambdaBody`. Three things it deliberately does NOT do:

- **The parameter is `tyPointer`, not `tyInt64`.** One machine word on every
  target; an Int64 parameter is two stack slots on i386 and arm32 and the second
  would be read out of whatever follows the staged word.
- **The cast to Int64 in the body is what makes the coercion ordinary.** From
  there the Int64 → by-ref-Variant argument conversion is the same one a written
  `worker(41)` gets. Nothing here unboxes anything itself.
- **It is a PROCEDURE, so its call is not wrapped in `AN_EXIT`.** The callee's
  Variant result is discarded on purpose: the child never returns, so a result
  has nowhere to go.

**A proc that already fits the contract is passed straight through.** The gate is
"its first parameter is a Variant, or it returns via the hidden destination" —
i.e. it is a NilPy def — so a Pascal `procedure(arg: Pointer)` resolved through a
`uses`d unit still gets its raw address, unchanged. A def with more than one
parameter is now a compile error naming the arity rather than a miscall.

### Verified

New `test/test_nilpy_thread_clone_arg.npy`, wired native + i386.

| | HEAD | pinned (pre-fix) |
| --- | --- | --- |
| `worker` reads `arg` | `child saw = 12346` | **3/3 SIGSEGV**, `tid nonzero = True` already printed |
| i386 | `child saw = 12346` | — |

**The asserted value is 12345 (+1) and not 0 or 1 on purpose.** A thread entry
handed the wrong word almost always gets 0 — the clone stub's own registers are
full of zeroes — so a row expecting 0 could not tell a delivered argument from an
undelivered one. The worker adds one so the printed number is not the literal
either: copying the constant into the wrong place still fails the row.

Regression cover re-run: `test_nilpy_thread_clone.npy` 0 bad in 100 native runs
and 0 in 20 i386 runs; `make test-nilpy` full; `gate.sh quick` GREEN with
`compiler/**` uncommitted.

### The stub fix stays and is not made redundant by this

`CLONE_RETBUF_SIZE` still matters: it covers a computed entry pointer, a C or
Rust entry returning a struct, and anything else the parser cannot resolve to a
proc index. This thunk makes the NilPy path *correct*; the scratch makes every
other path *survivable*.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
