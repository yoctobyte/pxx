# Triage: the backlog-shrink push (2026-08-19)

**Standing goal set by the user.** Pause NilPy. Work the pure **A / C / P** lanes,
preferring tickets that touch **IR or AST**, and **deliberately avoid high-ranked tickets**
— they cost more on average, and the aim of this push is *count down*, not value up.
Reason given: with this many open reports the user has lost oversight, and a lot of them
look trivial.

## The user's premise is correct, measured

Filed vs resolved per day, from git:

| day | filed | resolved | net |
| --- | --- | --- | --- |
| 2026-08-15 | 84 | 115 | **-31** |
| 2026-08-16 | 66 | 71 | -5 |
| 2026-08-17 | 46 | 27 | **+19** |
| 2026-08-18 | 45 | 29 | **+16** |
| 2026-08-19 | 43 | 26 | **+17** |

Three consecutive days of net growth, ~+17/day. **265 open** (243 backlog, 16 unfinished,
5 blocked, 1 working) against 2056 done.

Open by track: **N 77**, A 50, P 17, T 15, B 15, D 12, C 6, M 4, O 3, U 2, S 1, E 1.
Pausing N takes the single largest block out of the intake, which is most of why the
instruction works.

**A/C/P open = 73, of which 46 sit at p<=40.** That tail is the working set for this push.

## The tension to name up front

`tools/progress.sh next` / `ready` rank by **effective prio descending**. This push wants
the opposite. So **the self-dispatch tool actively fights the goal** — a worker running
`next --track A` gets handed exactly the ticket it is supposed to skip. Until this push
ends, take work from the clusters below, not from `next`.

**This is a temporary inversion, not a re-rating.** A `prio:` field that everyone
permanently ignores is worse than no field at all, because it keeps *looking* authoritative.
When the push ends, either resume ranking by prio or re-rank the survivors deliberately —
do not let "ignore prio" become the silent default.

## Clusters — related tickets that should be done in ONE context

Both clusters marked VERIFIED were checked by reading the tickets, not inferred from slugs.

### 1. Indexing a call result — VERIFIED one gap, two lanes
- `feature-a-index-an-array-returning-call-directly` (A, p40)
- `compat-pascal-index-a-function-call-result` (P, p40)

Same gap: `f(...)[i]` where the result is an array/string. The A ticket is explicitly
**split from** `bug-a-indexing-a-function-call-result-drops-the-field-selector`, which fixed
the silent half and left these refused with a diagnostic. pxx accepts exactly one spelling
"by accident of routing" — the shape `normalise-dont-special-case` describes. Parser + IR.
*(Filing note: the A ticket has no `summary:` frontmatter, so it renders blank on the board.)*

### 2. `Write`/`Str` of a real — VERIFIED one formatter
- `compat-pascal-write-fixed-huge-magnitude-differs-from-fpc` (p40)
- `compat-pascal-writeln-of-a-single-uses-double-width` (p30)
- `bug-b-write-of-a-real-ignores-the-field-width-without-decimals` (p20)

All three are the real->text formatter: huge magnitudes print debris, a `Single` prints its
full `Double` expansion, and `write(r:W)` ignores the width. Mechanical, oracle-checkable
against FPC, three tickets from one code path — the best count-down-per-change in the tail.

> **CORRECTION 2026-08-19, and it was my error.** This cluster was published as *"does not
> touch `lexer.inc`/`parser.inc`/`ir*.inc`, so it is safe to run concurrently"*. **That was
> asserted from the tickets' topic, not measured.** frank3 traced the code before touching
> it and it is **Track A**: the formatters are `EmitWriteFloatNat` /
> `EmitWriteFloatFixed` / `EmitWriteFloatFixedNative` / `EmitWriteFloatSci` in
> **`compiler/symtab.inc`** (~6940-7479), and the width/decimals dispatch that selects
> between them is **`compiler/ir_codegen.inc:4708-4710`**. `symtab.inc` is shared A/P
> ground and `ir_codegen.inc` is the IR — the literal trigger in this document's own
> coordination rule.
>
> Same failure I have been naming in others all day: I verified the *cluster* by reading
> the tickets (that part held — it is one code path) and then inferred the *file location*
> from plausibility. Verifying one property does not license asserting a second one.
>
> **Consequence:** cluster 2 is NOT concurrency-safe with cluster 1, whose IR lowering
> reaches the same ground. It is sequenced, not parallel — see the coordination rule below.

### 3. Pascal directives (lexer / directive parser)
- `feature-p-assertions-directive-and-position` (p40)
- `feature-p-defineglobal-a-define-that-crosses-unit-boundaries` (p40)
- `compat-pascal-directive-in-comment-ignores-nested-comments-off` (p25)
- `compat-pascal-unit-deprecated-hint-directive` (p25)

One mechanism (directive scanning/handling) reached four ways. `defineglobal` already has a
design conversation behind it from this session.

### 4. Calling convention / procedural types
- `feature-cdecl-bodied-sysv-prologue` (A, p40)
- `compat-pascal-calling-convention-directives-uneven` (P, p35)
- `bug-p-cannot-call-directly-through-a-procedural-type-cast` (P, p35)

Read `feedback_calling_convention_decorators_are_decoration` first: decorators mean nothing
**except on a procedural TYPE**, where `cdecl` is load-bearing for indirect C calls. That
exception is exactly what two of these three sit on.

### 5. C pair
- `bug-c-crtl-utoa-digit-loop-is-unbounded` (p25)
- `bug-c-header-with-a-body-compiles-twice-across-the-macro-reset` (p25)

The second has a decided diagnosis already (the real cause is `stdarg.h`'s six `static`
function bodies, not the macro reset the title names — read the ticket's LAST dated section).

### Deferred, deliberately
- **NilPy `**` pair** (`bug-a-nilpy-leading-double-star-in-a-call-is-not-detected` p40,
  `bug-a-nilpy-double-star-in-a-mixed-argument-list` p35): filed under A but NilPy work.
  Paused with the rest of N.
- **Optimization / threading** (`feature-opt-*`, `idea-adaptive-heap-growth`,
  `feature-a-why-threadsafe-needs-45pct-more-global-fixups`, the p55 alloc-under-threads
  item): open-ended by nature. Wrong shape for a count-down push regardless of prio.

## The one hard coordination rule for this push

**A and P share `lexer.inc` / `parser.inc`, and `symtab.inc` / `ir*.inc` are shared core
ground** — none may be edited by two agents at once. The original split assumed cluster 2
was disjoint; it is not (see the correction above), so the rule is now **sequencing, not
partition**:

- **Cluster 5 (C: `clexer`/`cparser`/`lib/crtl`) is genuinely disjoint** and runs
  concurrently with anything.
- **Clusters 1, 3, 4 and 2 all reach shared A/P ground** and are ordered, not parallel.
  Cluster 3 (directives) is `lexer.inc`-only, so it is the safest thing to run alongside
  cluster 2's `symtab.inc`/`ir_codegen.inc` work — but that pairing needs the A/P holder to
  confirm its actual file footprint first, not to be assumed. **Assuming a footprint is what
  produced the correction above.**

**The stop-and-hand-off rule worked and is why this was caught.** A worker traced the code
before editing, found it landed in shared ground, and escalated rather than proceeding on
its own reading of a rule written to prevent exactly that. That is the behaviour to keep:
when a lane boundary is ambiguous, the cost of asking is one message and the cost of
guessing is a corrupted shared file.

## Gate — unchanged

`make compiler/pascal26` + the repro + `tools/gate.sh quick`, then push. Do not widen it
because a change "touched something shared". Small tickets landing often is the entire point.
