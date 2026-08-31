# Pre-reboot session state — 2026-08-31

Written by `frank-user-a2` (Track U) immediately before an owner-ordered reboot
of all sessions, taken to pick up a `crossSessionInbound: "accept"` settings
change. **This is a record of what each session was holding at that moment**, so
the post-reboot sessions do not rediscover it.

Per CLAUDE.md's precedence rule: this is a HISTORICAL RECORD of what sessions
actually held, not an instruction. Do not gate anything on it.

## Who had work in progress

| session | checkout | state at reboot | confirmed? |
| --- | --- | --- | --- |
| **frankC** | `~/frankC` | **landed green, tree clean, nothing parked** | YES — said so explicitly |
| **frankB** | `~/frankB` | landed, tree clean, mid-flow on next measurement | YES — clean as of `7244299d4` |
| **frankA** | `~/frankA` | **33 uncommitted lines in a ticket** — a diagnosis in progress | **NO — outcome unknown** |
| **franks-4b** | `~/frankS` | idle, clean, no known work in flight | swept clean |
| **frank-user-a2** | `~/frank-user` | all decisions written and pushed, clean | YES |

### The one genuine unknown: frankA

`~/frankA` held 33 uncommitted lines in
`devdocs/progress/backlog/bug-a-p-caret-index-is-only-correct-when-the-pointer-is-a-plain-identifier.md`
— a diagnosis being written. It was asked to commit before the deadline and
**no confirmation arrived**. Nothing on disk is lost by a reboot, so the diff is
still in that working tree if it did not commit. **Whoever picks up `~/frankA`
should check `git status` first and read that diff before doing anything else**,
and treat its content as unverified: it was mid-thought, and nobody marked which
parts were established versus still hypothesis.

## What each session was PUT ON

Confidence is marked, because `owner:` is attribution and `working/` is a status
hint — neither is a claim, and both go stale. Only the frankB line is a task
this session actually assigned and can vouch for.

| session | put on | how I know |
| --- | --- | --- |
| **frankB** | the **compiler string-building cluster** — `perf-a-the-compiler-parses-at-12k-lines-per-second-find-out-why`, with the owner's directive *"minimize the use of appendchar() in the first place"* | **assigned by this session**, brief sent and acknowledged |
| **frankC** | started on the **C ABI** work (`decide-does-a-c-function-always-use-the-c-abi` ruled option A — the EBX fix first, then the flip); ended the session on the **`shr` family** and the `-O2` result-narrowing bug | owner launched it for the C ABI; the SHR/narrowing work is what it reported landing |
| **frankA** | the tickets in `working/` — holds `feature-opt-heap-per-thread-cache` and `refactor-a-carve-the-nilpy-arms-out-of-the-shared-pascal-argument-loops`; was last seen writing a diagnosis into `bug-a-p-caret-index-is-only-correct-when-the-pointer-is-a-plain-identifier` | owner said *"i told frankA and S to work on those tickets in working"*; the ticket is from its dirty tree |
| **franks-4b** (frankS) | same instruction — the `working/` tickets. `owner: frankS` also sits on three backlog bugs: cloned-thread sigaltstack, static-array-of-managed-field-records, and cross-backend variant retain/release | owner's instruction + `owner:` fields |
| **frank-rust** | `feature-pascal-corpus-oop` (in `working/`) | `owner:` field only — **not confirmed live** |
| **frank-user-a2** | Track U — going through the `decide-*` queue with the owner | this session |

**Do not read the `owner:` fields below as holds.** Per CLAUDE.md they are
attribution, not claims, and a ticket in `unfinished/` or `backlog/` carrying one
is free to take. Recorded here only so a post-reboot session knows who had
context on what, and who to ask.

Other `owner:` fields standing at reboot, unverified: `frankA` on
`feature-a-build-a-reduced-compiler…` (repriced to 25 today),
`feature-pascal-corpus-generics`, `feature-threadsafe-heap-optimize`, and
`perf-a-cache-the-compiled-nilpy-runtime-unit-image` (**that last one is CLOSED
by today's rejection — do not resume it**); `frankC` on
`bug-c-a-header-reached-by-uses-discards-function-bodies…` and
`feature-c-diagnostics-name-the-module-they-are-in`; `frankB` on
`bug-b-fprecv-and-fpsend-silently-discard-their-flags-argument`; `frank2` on
`bug-n-a-subpackage-directory-does-not-resolve-as-a-module`; `frank-optimize` on
`bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython`.

## What landed in the final hour — all verified on origin/master by merge-base

**frankC** — four fixes and a rename, all green, self-host converged:

| commit | what |
| --- | --- |
| `191af3440` | the -O2 inliner dropped the narrowing store, so a function RESULT kept its full width |
| `5c6459e18` | board: resolved, and corrected — it was the inliner, NOT the assignment |
| `243ff4a29` | an untyped literal shift is 64-bit on EVERY target, not the target's width |
| `5b12e6a5e` | a constant expression containing `shr` did not fold |
| `314481dd7` | the IR's logical shift-right gets a name — `tkShrLogical`, not `tkIdent` |

**frankB** — the compiler-throughput cluster:

| commit | what |
| --- | --- |
| `4b3d34f74` | `GetTokenStr` built every token string a char at a time — **13.8% off a self-compile** |
| `7244299d4` | playbook: the symbol map exists, and a sampling aggregator needs a positive control |
| `7ef9c2204` | the FPC oracle says **1.28x**, so that ticket is much smaller than it looked |

## Three findings that outlived their tickets — carry these

**1. The -O2 result-narrowing bug was far wider than its repro.** frankC's
correction: it is not the assignment, it is `inline_expand.inc`'s **shape 1** —
for a body that is exactly `Result := E` the inliner retains `E` and DROPS the
assignment, and the narrowing lived in that store. Shape 3 (any body with a
second statement) was always right, which is why `ViaLocal` looked like a
working "other arm" — a different inline SHAPE, not a different assignment arm.

The ticket's `Int64` parameter **hid the blast radius**:

```pascal
function AddOne(a: Integer): Integer; begin AddOne := a + 1; end
```

returned **2147483648** for `MaxInt` at `-O2`. Integer arithmetic promotes to 64
bits, so *every* Integer-returning function whose body is a single arithmetic
expression was returning an unwrapped value. FPC and our own `-O0` both say
`-2147483648`. **Anything measured or gated against a pre-`191af3440` `-O2`
binary is suspect.**

**2. The compiler writes its own `.map` file beside every binary** — 3846
entries, base address in the header. TWO independent profiling write-ups
concluded ".symtab is empty, nm reports nothing" and stopped there. That
statement is TRUE and reads like the end of the road, which is exactly why it
cost two sessions. With the map, the `??` frames resolve: `PXXStrFromLit` 17.1%,
`PXXAlloc` 10.0%, `PXXFree` 8.6%, refcount thunks 8.6% — **managed-string plus
heap runtime is ~47% of a self-compile.**

**3. "12,000 lines/sec" is LOAD-DEPENDENT and should not be quoted as a
property of the compiler.** The identical operation measured **18,303 lines/s**
on a quieter box — ~40% from load alone. This very likely dissolves the
`3.406s`-vs-`19.7s` item flagged as possibly-a-regression in
`perf-a-the-compiler-parses-at-12k-lines-per-second-find-out-why`: **treat it as
load until someone re-measures both under known load.** And with FPC at only
1.28x, that ticket de-escalates by its own written criterion.

## Where the open work sits

- `perf-o-string-literals-still-allocate-at-11329-call-sites-despite-the-static-handle-pass`
  (p65, filed by frankB) — `EmitStaticLitHandle` is active at `-O2`, yet objdump
  counts 11,329 `call PXXStrFromLit` sites in the `-O2` compiler binary. The pass
  runs and the sites remain; that gap is the ticket.
- The `AppendChar` call-site conversion campaign is **closed as a measured
  negative**. Post-fix, `Append*` is 6/70 samples across six sites at one sample
  each — no second concentration. `cpreproc.inc`'s 72-site census was misleading
  twice over: that file does not execute in a Pascal self-compile, *and* its hot
  loops already use its own `CPAppendRange`. Do not re-run this campaign.
- One Track U question and one Track N bug were filed by frankC from the SHR
  work; two SHR tickets resolved.

## Decisions ruled this session (all in `devdocs/progress/decided/`)

`-O0` dead-branch pruning · the C ABI · Track R on master · NilPy random seeding
· pin-number reuse · QEMU/FreeBSD on plexus · GTK 3 as default · `SetTextBuf` ·
the managed-string kind · the reduced compiler's self-host obligation · the
NilPy runtime tax (rejected).

**Still unruled and waiting on the owner:**
`decide-nilpy-ranking-is-shaped-by-a-low-dependency-sample` — recommendation is
option 3, stated explicitly, on the grounds that mechanism walls are Track N
(`pyparser.inc`/`pylib.pas`) and stdlib shims are Track B
(`lib/rtl/mimic_*.py`), so they never compete for a worker and ranking them in
one queue was the error rather than the numbers being wrong.
