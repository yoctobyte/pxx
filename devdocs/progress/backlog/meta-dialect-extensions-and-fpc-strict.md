---
prio: 5  # standing index, not dispatchable work — see the note below
---

# Meta: pxx dialect extensions ⟷ FPC compatibility (two aims, switch-guarded)

- **Type:** meta (governance / index / epic) — Track A; tag: compat (this is the Pascal-compat charter: dialect-vs-FPC-parity policy, strict-flag family — see parallel-tracks.md)
- **Status:** backlog (standing index — never "done"; new dialect work links here)
- **Not dispatchable — do not claim this ticket.** It is a charter/index: there is
  no green state it can reach, so an agent that "works" it has nothing to land.
  `prio:` here only controls where the ranker prints it, and ranking a
  never-completable item above real work is how it sat at the head of
  `next --track A` on 2026-08-20. Hence prio 5: it stays visible at the tail of
  the queue and out of the dispatch slot. Rate the *linked* tickets instead —
  they are the work.
- **Owner:** — (Track A; language-design calls go to the user)
- **Opened:** 2026-06-30
- **Origin:** crystallised while designing the inline-var / auto-locals family
  ([[feature-inline-loop-var-rio]], [[feature-implicit-locals-sloppy-switch]]) —
  features bumped into by accident, but worth pursuing deliberately.

## The two aims (deliberately distinct)

pxx pursues **two goals at once**, and they pull in opposite directions:

1. **pxx's own dialect — lax, ergonomic, boilerplate-eliminating.** Type
   inference (`var x := expr`, the `auto` type), Delphi-10.3-Rio inline vars
   (`for var i := ...`), optional sloppy locals, forward-visible decl order, etc.
   This is *our* language; it may extend beyond standard Pascal where the design
   is good (Delphi set real precedents worth stealing).
2. **FPC compatibility — on request.** When asked (`--strict` / `--mimic-fpc`),
   pxx must compile standard FPC/Delphi-classic source and **reject** the pxx-only
   extensions, so FPC-targeted code stays portable and the cold FPC seed builds.

These are not in conflict **because they are guarded by switches.** Neither aim is
sacrificed: lenient is the productive default; strict is one flag away.

## The contract (rule for every dialect extension)

Any feature that diverges from standard FPC/Delphi-classic MUST:

1. **Be available by default** (lenient) *or* behind an explicit opt-in switch —
   never silently mandatory.
2. **Be disabled / rejected under the strict family** (`--strict` /
   `--mimic-fpc` / the relevant `{$...}` strict directive), so a strict compile is
   FPC-faithful. A dialect-only construct under strict must error with a clear
   "not valid in strict/FPC mode" message.
3. **Keep the self-build honest.** The compiler's own source must compile under
   the chosen default profile, and the strict path must stay reachable (so strict
   can become a profile without breaking bootstrap). Self-host byte-identical.
4. **Have a test on both sides** — the extension works in lax; the same source
   errors under strict.

A new dialect ticket should state, up front, *which switch guards it* and *what
strict does*.

## The BOUNDARY of aim 2 — strict emulates FPC's behaviour, never FPC's bugs

**Decided by the user, 2026-08-16.** The rule above ("a strict compile is
FPC-faithful") has a limit that was never written down, and an agent walking
`decide-forin-mixed-int-float-ctor-vs-fpc` read the rule literally and
recommended reproducing an FPC defect for parity.

> "no, we will not strictly emulate obvious bugs. that'd be wrong. strict mode
> is to compile valid programs that rely on FPC's behaviour, not on FPC's bugs."
> — user

So the target of the strict family is **the set of valid FPC programs and the
FPC behaviour they legitimately depend on** — not the observable output of the
FPC binary in every case. When those two come apart, the program wins.

### How to tell a behaviour from a bug (the test that actually separates them)

The distinguishing question is **can a program depend on it?**

- **Behaviour → emulate under strict.** Deterministic and derivable from the
  source: evaluation order, overload-resolution ties, integer promotion rules,
  default float formatting. Working code can and does rely on these, so a strict
  compile must reproduce them even where pxx's own default is nicer.
- **Bug → never emulate, and do not put the correct answer behind a flag.**
  Undefined, non-deterministic, or dependent on state the program did not write
  — uninitialised memory, a value that changes with the preceding statement, a
  silently dropped write. No valid program can rely on it, so there is nothing
  for strict mode to preserve, and "matching" it is not implementable anyway.

The worked example is `decide-forin-mixed-int-float-ctor-vs-fpc`: FPC 3.2.2's
`for d in [1.5, 2, 3]` prints values left over from the *previous* statement's
array. That is the bug side of the line — it is not a semantics, it is a read of
memory nobody wrote.

### Consequences for filing

- A pxx/FPC difference where **pxx is correct and FPC is defective** is NOT a
  deliberate divergence and must not go in that index. It belongs in the compat
  notes as an FPC bug pxx does not reproduce. The two lists answer different
  questions for someone judging whether their FPC code will port, and conflating
  them makes pxx look like it wanders from the reference when it does not.
- Where the FPC defect is confirmed **still present in current trunk**, the
  courteous and useful step is to **report it upstream** (user, same date) rather
  than only recording it locally. Check trunk before assuming; a bug fixed
  upstream is a footnote about current FPC stable, not a divergence at all.
- This cuts the other way too: it is **not** licence to call an inconvenient FPC
  behaviour a bug. If a valid program can observe it deterministically, it is
  behaviour, and strict mode owes it — however ugly.

## Index — dialect extensions (the lax aim)

**Strict-flag family additions (2026-07-14/15 night):**
- `--strict-operator` / `{$STRICT_OPERATOR ON}` — FPC-parity operator-overload
  rejections (`=`/`<>` on class operands, toperator71). PXX's lax default
  keeps value-equality operators on classes (test_op_overload.pas); the
  conformance sweep runs the flag ON next to `--strict-case`. Landed 693b4da4
  after b369 briefly made the rejection unconditional and broke the dialect.
- `{$Q+}` / `{$OVERFLOWCHECKS ON}` — NOT a strict flag but the same
  contract shape: default-off runtime semantics change, lexically scoped
  per token (TokQChecks), FPC-faithful when on (RE 215 / catchable
  EIntOverflow via the sysutils hook). x86-64 + aarch64 full; 32-bit pairs
  add/sub (see feature-overflow-checks-cross-and-intrinsics).
- Contract note reinforced by b369's lesson: an FPC-parity REJECTION added
  for a %FAIL test must land behind its per-feature strict flag, never
  unconditionally — the sweep runs with the flags on, the dialect stays lax.

**Shipped:**
- Type inference: inline `var x := expr` statement (`tyAuto`, default on,
  `--no-auto-var` off). The foundation; `var` without a type == `auto`.
- `for var i := a to b` — Rio inline loop counter (counted form).
  [[feature-inline-loop-var-rio]] (counted done; for-in inline remains).
- Forward-later-global opt-out: `--lax-decl-order` / `{$DECLORDER OFF}`
  ([[feature-implicit-identifier-binding-strictness-switch]]).

**Planned:**
- `for var x in coll` — Rio inline loop var, for-in form (element-type inference).
  [[feature-inline-loop-var-rio]].
- Implicit/sloppy locals (`i := 0` undeclared) behind `{$IMPLICITVARS}` /
  `--auto-locals`. [[feature-implicit-locals-sloppy-switch]].
- **Research more Delphi / modern-Pascal extensions deliberately** (inline `var`
  in any block, `var`-section inference, anonymous methods, etc.) — pick the
  good-design, forward-compatible ones. Future; file individually under this index.

## Index — FPC-strict / compatibility (the compat aim)

- `--mimic-fpc` / `{$MIMIC FPC}` — install the FPC define set
  ([[project_mimic_fpc_done]], done).
- `--strict` umbrella — [[feature-require-forward-strict-mode]].
- `{$DECLORDER ON}` (default) — declare-before-use gating, FPC-parity
  ([[feature-implicit-identifier-binding-strictness-switch]], done).
- `make test-fpc` / cold FPC seed — the compatibility gate (the compiler source
  stays FPC-buildable).

## Open governance question (for the user)

Should `--strict` be a single master switch that turns **all** dialect extensions
off at once (simplest mental model), or per-feature directives that `--strict`
merely *defaults* on? Recommendation: a master `--strict` / `--mimic-fpc` that
sets the strict default for every guarded extension, with per-feature `{$...}`
overrides for fine control. Decide before the second dialect feature lands so the
switch wiring is uniform.

## 2026-08-07 — `AnsiString + UCS4Char`: an EXTENSION, not an ambiguity (low prio)

Logged so it is on the record, not because anything needs doing. Reached via
NilPy ([[feature-nilpy-text-string-kind]]); the Pascal side is fine.

**Measured against FPC 3.2.2:**

| expression | FPC |
| --- | --- |
| `AnsiString + AnsiChar` | OK |
| `UnicodeString + WideChar` | OK |
| `AnsiString + WideChar` | OK |
| `UCS4String + UCS4Char` | **rejected** |
| `UnicodeString + UCS4Char` | **rejected** |

`UCS4String` exists (`array of UCS4Char`) but **no FPC string type concatenates
with a `UCS4Char`, not even its own** — in FPC the type is inert for string
building and you go through the conversion functions. pxx converts it to the
code point's UTF-8 encoding (`feat(A) b0cbeba60`).

### Why it does NOT go behind `--strict-fpc`

The classification is the point, and it is the general rule this instance
illustrates:

> **Ambiguity** — the same source compiles under both and *means something
> different*. Dangerous, silent, and exactly what the strict flags exist for.
>
> **Extension** — pxx accepts source FPC *rejects*. Harmless to forward
> compatibility: no FPC program can contain it, so no FPC program changes
> meaning. Nothing to disambiguate, so nothing for a strict flag to do.

`AnsiString + UCS4Char` is squarely the second. FPC rejects it outright, so
there is no FPC program it can affect. Gating it under `--strict-fpc` would be
category error — and would make the type nearly unusable in strict mode, since
FPC offers no concat path at all, so strict code would need an explicit
`UCS4ToUTF8(c)` spelling first.

(A previous draft of this reasoning proposed a rule that *every* new laxness
gets a strict gate. That is wrong for the same reason: only laxness that creates
**divergent meaning** needs one.)

### The one thing genuinely open

**We do not know what a newer FPC does here.** 3.2.2 is what was measured; a
nightly or the next stable may grow a `UCS4Char` concat path, and if it does,
this stops being an extension and becomes a place where the two disagree — which
*would* be strict-flag territory. Worth re-measuring when a new FPC stable lands
(or refreshing a nightly if one is already pulled). No action before then.

### Idea (NOT a ticket): a future `--ultra-strict-fpc` — the portability guarantee

Recorded as a design note only, at the user's request. No work item.

The strict family so far is about **meaning**. A third, different guarantee is
about **acceptance**:

> **`--ultra-strict-fpc`**: if this is set and pxx compiles it, FPC compiles it.

That is not another parity switch, it is a *closed-world property* — "there
exists no construct pxx accepts here that FPC rejects" — which is why it is a
separate mode rather than another `--strict-*` flag.

**The two guarantees compose, and both are needed for the use case:**

| flag | guarantees | prevents |
| --- | --- | --- |
| `--strict-fpc` | same source, same **meaning** | ambiguity (silent divergence) |
| `--ultra-strict-fpc` | FPC also **accepts** it | extensions (pxx-only syntax) |

Either alone is insufficient for the real target: a program that compiles under
FPC but *behaves* differently is worse than one FPC refuses outright. So
ultra-strict would imply strict, not replace it.

**Why it has real-world value** (the user's point, and it is the strongest
argument for eventually building it): a **library or application meant to build
under both compilers**. Develop against pxx — fast, self-hosting, better
diagnostics — and retain the guarantee that FPC users can still build the
result. That is a concrete audience, unlike parity-for-its-own-sake.

**It can only be verified, never asserted.** A closed-world claim needs a
differential: compile the corpus with the flag, feed the same sources to FPC,
and require FPC to accept everything pxx accepted. The machinery largely exists
(`tools/fpc_diff_probe.sh`, the FPC seed canary in `gate.sh`) — Track T-flavoured
when it happens. Anything short of that is a promise nobody checked.

Cost to note before starting: every existing pxx extension needs a decision
(gate it, or declare the mode incompatible with it), which is an audit of the
whole dialect surface — not a flag one afternoon.


## 2026-08-16 — set literal vs `array of const` at one overload slot (decided: leave it)

A row for the divergence table, from
`decide-set-vs-array-of-const-at-the-same-overload-slot` (decided by the owner,
2026-08-16).

**Divergence:** when an overload set offers both a `set of T` and an
`array of const` at the same parameter slot, `f([x])` binds differently under pxx
and FPC — and *both* compilers are order-dependent, so neither is a rule.

- **FPC**: in `para_allowed` a `setdef` parameter rates a bracket literal
  `te_equal`, and so does `array of const`. Two exact matches is a genuine TIE,
  broken by candidate collection order (i.e. `uses` order). Verified present
  verbatim in trunk as well as 3.2.2, so this is FPC's design and not a stable
  bug awaiting a fix.
- **pxx**: resolves from the binding candidate's parameter shape, decided at
  parse time before the brackets are read.

**Decision: leave it.** Don't overload on a set and an `array of const` at one
slot — give the function a decisive name. A cast-style disambiguator
(`somefunc((set)[x,y,z])`) was considered and **rejected as non-standard
Pascal**. `--strict-fpc` has a real target for the bracket shapes where FPC *is*
consistent (ranges, mixed-type elements, empty) and nothing coherent to match on
the genuine tie.

**Not covered by that decision, and still open:**
`bug-p-set-literal-elements-are-not-type-checked` (P, p60) — pxx never checks a
set literal's elements against the element type, so `[cGreen]` (a different enum)
silently becomes `dTue` and `[99]` silently yields the empty set. That is a real
divergence with a silent wrong value, and per the compat escape rule it is a
`bug-`, not a compat row.
