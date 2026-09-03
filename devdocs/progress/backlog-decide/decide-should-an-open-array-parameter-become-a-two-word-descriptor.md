---
slug: decide-should-an-open-array-parameter-become-a-two-word-descriptor
title: "Should an open-array parameter become a two-word (pointer, high) descriptor, or does the one-word `[ptr-8]` convention stand with its one observable consequence?"
track: U
prio: 55
type: decide
status: open
created: 2026-09-03
found-by: frankB
owner:
blocked-by: []
summary: "THREE SESSIONS HAVE NOW STOPPED AT THE SAME WALL and each stop looked like the ticket being hard rather than mis-filed, so nobody escalated. `bug-a-address-of-an-open-array-element-points-at-the-marshalling-temp` is not a bug someone can attempt: its own body says the fix is a representation change across 633 `IsArray` sites in 27 files and 6 backends, and that the only cheaper arm is impossible for a record field or a 2-D row. That is a design fork and it belongs here. THE FORK: pxx passes an open array as ONE word -- a pointer whose length sits at `[ptr-8]`, the same convention AnsiString handles and dynamic arrays share -- so an argument that already carries that header is passed by reference and one that does not (a static array, a record field, a 2-D row) must be copied into an adjacent-header temp. FPC passes TWO words, `(pointer, high)`, and therefore aliases everything. The temp is a faithful, writable, correctly-strided view whose writes are copied back on return, so element access, write-through, `Length` and `High` are all correct; THE ONLY OBSERVABLE IS AN ADDRESS THAT ESCAPES THE CALL. My recommendation is arm C: keep the one-word convention, record the divergence as chosen, and revisit only on real source that needs the address to outlive the call -- nobody has produced any. Deciding this closes the bug ticket one way or the other; leaving it open at p55 guarantees a fourth session reads the same summary and stops in the same place."
---

# Why this is a decision and not a ticket

`bug-a-address-of-an-open-array-element-points-at-the-marshalling-temp` (A, p55)
is correctly diagnosed and correctly parked. It has been read by three sessions
independently — the author (twice, the second time to correct its own claims
against FPC), franka-29, and frankuser — and every reader stopped at the same
sentence: *"633 `IsArray` sites across 27 files, so do not start it casually."*

**Each stop looks like the ticket being hard rather than the ticket being
mis-filed**, so nobody escalates, and a p55 slot in `ready --track A` guarantees
the next arrival repeats the pass. That is the failure this lane exists to catch.

# The measured facts, so the decision needs no re-derivation

All rows measured 2026-09-03 beside `fpc -Mobjfpc -O2`, pinned in
`test/test_open_array_param_aliasing.pas` (which runs unmodified under FPC and
is identical there on every row, plus i386/aarch64/arm32/riscv32):

| shape | pxx | FPC |
| --- | --- | --- |
| `@a[0]` = `@caller[0]`, DYNAMIC argument, `var` and `const` | TRUE | TRUE |
| `@a[0]` = `@caller[0]`, STATIC argument, `var` and `const` | **FALSE** | TRUE |
| `@a[0]` = `@caller[0]`, by VALUE | FALSE | **FALSE** |
| element read, write-through, `Length`, `High`, stride | correct | correct |

The by-value row is not a divergence — a by-value open array is a copy by
definition, and asserting `=` there would be asserting the language is something
else. The dynamic rows already alias. **The whole of the question is the static
row**, and its consequence is bounded: the temp is written back on return, so an
address that stays INSIDE the call (`Move(a[0], …)`, handing `@a[0]` to a C
routine for the duration) behaves correctly. It bites only when the address
**escapes** — stored in a field, returned, retained past the call.

# The arms

**A — the descriptor.** Pass `(pointer, high)`, FPC's shape. Correct for every
row, and it is the answer the language's own idiom expects. Cost: the `[ptr-8]`
convention is *shared* with dynamic arrays and managed strings, so this is not a
local change to open arrays — it is a wire-format change touching **633 `IsArray`
sites across 27 files, 6 of them backends**. Weeks, and it serialises anyone
working in the backends while it lands.

**B — prefix the argument's own storage with 8 bytes.** Then a static array
carries the header and can be passed by reference. Works for a local or a global,
whose slot layout the compiler owns outright. **Impossible for a record field or
a 2-D row**, whose offsets are observable. Leaves two behaviours for one
construct with the second still broken *and looking fixed*. Rejected on that,
not on difficulty — and worth keeping visible precisely because it is the arm
that looks cheap.

**C — keep one word, record the divergence as chosen.** The one-word convention
is a genuine simplification, not an accident: one representation serves open
arrays, dynamic arrays and AnsiString handles. The cost is the escaping-address
row, and the correct rows are already pinned by a test that deliberately does
NOT assert today's wrong answer, so a future change cannot silently take the
right ones away.

# Recommendation — C, revisit on real source

CLAUDE.md's test is what the source MEANT, and the evidence that settles a compat
question is real source that wants the behaviour. **Nobody has produced any.**
Every use of `@a[i]` on an open-array parameter found so far is confined to the
call, where pxx is already correct. Against that, arm A is weeks of work across
every backend for one observable that no known program reaches, and it would
also spend the simplification that makes three different array-ish things one
representation.

So: keep the convention, mark the divergence chosen rather than tolerated, and
reopen this decision on a program that needs the address to outlive the call —
which is a cheap trigger to state and a clear one to recognise.

**What I am NOT recommending:** filing it to `known-incompat/` unilaterally. That
folder means "true, reproducible, and ours is chosen", which is exactly what arm
C asserts — but the assertion costs a real FPC-compatible idiom, and choosing to
spend that is above a worker's line. That is why this is here.

# What each answer does

- **A** → the bug ticket becomes a multi-session representation project with an
  owner and a landing order, not a p55 queue item.
- **B** → do not; recorded so the next reader does not re-derive it.
- **C** → the bug ticket moves to `known-incompat/` with the test as its record,
  and `ready --track A` stops offering a wall.
