---
track: C
prio: 50
type: bug
blocked-by: []
summary: "test/quickjs/runner.c segfaults with ZERO output on the full smoke.js, and does so identically when built with the PINNED compiler — so it is not a HEAD regression. Small evals work on both. Observed 2026-08-20 in passing while landing the C entry-stub init phase; NOT caused by it, and filed separately so it is not attributed there."
status: done
owner: frank1-ACP
---

# `test/quickjs/runner.c` segfaults with zero output on the full `smoke.js`

- **Track C** — the quickjs corpus target.
- **Observed** 2026-08-20 by frank2 while landing
  [[feature-c-entry-stub-must-run-initializers-for-environ]]. **Not caused by it** — see the
  control below. Filed as its own ticket precisely so it is never attributed to that change.

## What was seen

Running the full `smoke.js` through `test/quickjs/runner.c` **segfaults with zero output**.
Small evals work.

## The control, and it is the part that makes this filable

**The same failure reproduces when the runner is built with the PINNED compiler** — empty
output from both, small evals working on both. So it is pre-existing or environmental, and
in particular it is **not** a regression introduced at HEAD.

That control is what separates "a defect we own" from "a defect this week's work caused",
and it was run before reporting rather than after being challenged. Note the shape: building
with `PXX_STABLE` **removes the variable** rather than arguing about it — see
[[feedback_control_must_actually_remove_the_variable]].

## What is NOT yet known

Deliberately left open rather than guessed, because nothing here has been measured:

- Whether it is a pxx defect at all, or environmental on this box.
- Whether it is a stack-depth / recursion issue in the runner, a codegen defect, or a crtl
  gap that `smoke.js` reaches and small evals do not.
- Which construct in `smoke.js` first triggers it. **Bisecting the INPUT** — feed progressively
  larger prefixes of `smoke.js` — is the cheap first move and needs no compiler work.

**Zero output with a segfault is itself a clue**: it suggests the crash lands before any
buffered stdout is flushed, which points earlier than the first `print` rather than at
whatever statement is "last" in the file. Do not assume the failing construct is near the end.

## First moves

1. Prefix-bisect `smoke.js` to find the smallest input that crashes.
2. `-g -O2` + gdb (`source tools/pxx-gdb.py`) on the reduced case; the rbp chain answers
   whether it is a runaway recursion or a wild pointer. See
   [[project_debug_toolkit_playbook]].
3. Only then decide the lane: a codegen or IR fault routes to **Track A**, a crtl gap stays
   **C**, an environmental cause gets recorded and closed.

## Gate

The reduced case runs; `smoke.js` produces output. C tests green + self-host byte-identical.

---

## FIXED 2026-08-20 (frank1-ACP) — one line of IR, and it was not a quickjs problem

`make test-quickjs`'s smoke is **byte-exact** now. The ticket's three open
questions are answered: it IS a pxx defect (the gcc oracle built from the same
source and the same box is correct), it is **not** a stack-depth or crtl issue,
and the construct is not in `smoke.js` at all.

### It is worse than reported, which is what made it findable

The ticket says "small evals work". On this box they did not:

    pxx  1+2 -> 2      1 -> 0      3*4 -> 0      'x' -> 0      10+5 -> 5
    gcc  1+2 -> 3      1 -> 1      3*4 -> 12     'x' -> x      10+5 -> 15

Every answer wrong, and a **plausible** wrong — never a crash at the cause. The
segfault is the same defect at `-O2` only; `-O0`, `-O1` and `-O3` produce the
wrong values without crashing.

### The bisect that mattered took one step

quickjs can dump its own compiled bytecode (`JS_SetDumpFlags(rt,
JS_DUMP_BYTECODE_FINAL)`, `-DENABLE_DUMPS`). The dump for `1+2` is **identical**
under gcc and pxx:

    push_1 / push_2 / add / set_loc0 / return

So quickjs's JS *compiler* is fine under pxx and the defect is in the
*interpreter* — half the engine eliminated in one run, without reducing
anything. The bytecode then reads the answer out: `OP_return` is
`ret_val = *--sp`, so returning **2** means `sp` was one slot too high, i.e. a
push had advanced the stack pointer without the value landing where the pop
would look. `1` returning 0 says the same thing for a single push.

quickjs pushes with `*sp++ = <JSValue>` and JSValue is a 16-byte STRUCT.

### Root cause

    typedef struct { long long a, b; } S;
    S buf[4], v = {1, 11}, *p = buf;
    *p++ = v;
    /* gcc: p - buf == 1     pxx: p - buf == 2 */

`ir.inc`'s AN_ASSIGN made a struct assignment yield the stored value — the C
rule that [[bug-c-a-struct-assignment-used-as-a-value-runs-its-rhs-twice]]
landed — by lowering the LHS a **second time** for the result. Re-lowering
re-emits the LHS's SIDE EFFECTS, so that fix traded a doubled RHS for a doubled
LHS. The IR shows it plainly (`PXXDBG=a.ir:f`): the entire post-increment
sequence appears twice, and the statement's value is the second one's.

Measured, all of them doubling: `*p++ = v`, `*++p = v`, `buf[i++] = v`,
`*f() = v`.

The fix is to reuse the destination operand the copy already carries
(`Result := IRA[Result]`) instead of lowering the LHS again. The **scalar arms
had always done exactly this** — one `leftAddr` node feeding both the store and
the load-back — which is also the proof that one IR node with two consumers is
emitted once. Sibling case, one arm right and one wrong, exactly the shape
`devdocs/dev/normalise-dont-special-case.md` describes.

C-mode only; the Pascal self-host build is byte-identical.

### Test

`test/cstruct_assign_dest_side_effects.c` — the DESTINATION half of the rule
`cstruct_assign_value_side_effects.c` pins for the source. Post/pre-increment,
post-decrement, an index with a side effect, a struct smaller than a pointer,
and the two shapes that must NOT regress (the assignment still yields the
destination, including through a stepping destination). Verified against gcc on
the same source; wired into the Makefile beside its sibling.

### Two side findings, filed separately rather than folded in

Both were found by the same probe and neither is this bug:

- [[bug-c-a-dereferenced-call-on-the-left-of-an-assignment-runs-twice]] —
  `*f() = x` calls `f` twice, for a **scalar destination as well as a struct**.
  Pre-existing and untouched by this fix.
- [[bug-c-pointer-difference-on-a-long-long-element-type]] — `q - p` on
  `long long *` answers 0 and `q - a` answers garbage, while `char`, `short`,
  `int`, `float`, `double`, `void *` and both struct widths are all correct.
  Looks like the operands are being read as VALUES rather than pointers.

### Note on the ticket's control

The ticket's control was sound and its conclusion stands — the pinned compiler
fails identically, so this was never a HEAD regression. It has been latent
since the RHS fix.

## Log
- 2026-08-20 — resolved, commit PENDING-COMMIT.
