---
slug: feature-p-threadvar-is-not-supported-at-any-scope
title: "`threadvar` is not supported at any scope"
track: P
prio: 40
type: feature
blocked-by: []
status: working
owner: frankH
created: 2026-09-06
summary: "`threadvar t: LongInt;` at program or unit level is refused with `expected 'begin' before 'threadvar'`. FPC supports it, and it is the language's only spelling for thread-local storage -- so a program that wants per-thread state has no way to ask for it. Measured 2026-09-06 by probe while dispositioning tclass17 and terecs21, two `%FAIL` rows about `threadvar` INSIDE A CLASS whose refusals were being satisfied by this gap rather than by their own subject."
---

# The measurement

```pascal
program p; {$mode objfpc}
threadvar t: LongInt;
begin t := 1; WriteLn(t); end.
```

```
pascal26: error: expected 'begin' before 'threadvar'
```

# What it costs

`threadvar` is the only source-level spelling of thread-local storage in the
dialect. Anything wanting per-thread state — an error code, a current-context
pointer, a per-thread allocator cache — has to reach for a different mechanism
or not have one. Ranked as a feature rather than a bug because nothing miscompiles;
the declaration is simply not accepted.

Two corpus rows (`tclass17`, `terecs21`) assert that `threadvar` is invalid
INSIDE A CLASS. They pass today, and not for that reason — pxx never gets far
enough to have an opinion about the class. Closing this gap turns them into real
assertions, and they should be re-measured then rather than assumed.

`task-t-twelve-syntax-shaped-fail-rows-may-be-refused-by-a-parse-gap-rather-than-their-own-subject`

## PROSE EDGES BY DESIGN

## The same concept fails the OPPOSITE way in the C frontend

`bug-c-__thread-is-accepted-and-silently-ignored-so-thread-local-storage-is-shared`
is this gap one frontend over, and the pair is worth holding together because
the failure modes are inverted: **Pascal refuses loudly and C accepts and
shares the storage silently.** Neither frontend has thread-local storage; only
one of them says so. A program that wants per-thread state gets a diagnostic in
Pascal and a race in C.

Not wired as `blocked-by` in either direction — neither gates the other, and
they will most likely be fixed by one shared TLS mechanism rather than by each
other.

## What it blocks in the corpus, measured 2026-09-06 at compiler 0d77c1e48ea4

`tclass16.pp` and `terecs20.pp` (the `%SKIPTARGET=$nothread` pair, `class
threadvar` in a class and in a record) are gated on THREE things, not the two
their skip rows named:

1. this ticket — plain `threadvar` at any scope,
2. `class threadvar` inside a class/record body, which is the rung above it,
3. the **RTLEvent family** — `PRTLEvent`, `RTLEventCreate`, `RTLeventSetEvent`,
   `RTLeventWaitFor`, `RTLEventDestroy` — absent from `lib/rtl` entirely.

Rung 3 is NOT the general threading surface, which is largely present and
tested: `BeginThread`, `WaitForThreadTerminate`, `TThreadID`, `EndThread` and a
native `TThread` all exist (`lib/rtl/palthreadobj.pas`, `lib/rtl/cthreads.pas`,
`test/lib_fpc_thread_surface.pas`). A first probe of these two rows reported the
whole threading RTL missing and that was the probe's fault — it omitted the
`uses` clause, so `unknown type: TThreadID` was about the program and not about
the RTL. Filed as `feature-b-the-rtlevent-family-is-absent-from-the-threading-rtl`.


## What a taker should know before starting (2026-09-09, frankS)

Not an edge, deliberately — I have not established that this is blocked, and
saying so in prose without the frontmatter edge is how a ticket lies to its
reader. What I did establish is that **the mechanism this feature needs already
partly exists**, which the ticket does not say:

- `thread_emit.inc:142` installs a per-thread block via `arch_prctl(ARCH_SET_GS)`
  — *"GS, not fs: fs belongs to libc, and a pxx program may link one"* — and a
  pxx-native thread gets a DISTINCT non-zero GS base (measured 2026-09-06 by
  frankC on a pxx `BeginThread`: main `42D110`, child `7BDB21FF7A80`).
  `TLS_SLOT_*` / `TLS_BLOCK_SIZE = 1152` has three free map slots plus a 64-slot
  tail, which `ir_codegen.inc:78` records as UNUSED rather than absent.
- So a pure-pxx `threadvar` may be implementable on what is already there,
  without touching ELF TLS at all.

**And the thing that may or may not make it a fork:**
[[decide-pxx-thread-local-storage-is-gs-relative-and-the-x86-64-psabi-is-fs-relative]]
is open. It is about INTEROP — TLS relocations in gcc-built objects are
fs-relative and ours is gs-relative — so it may leave a pxx-only `threadvar`
entirely alone. **That is the question to settle first**, and it is one
measurement, not a design discussion: does anything in the intended
implementation emit or consume an ELF TLS relocation? If no, this ticket is
unblocked and the decide ticket is about a different program. If yes, wire the
edge.

The sibling in C is [[bug-c-__thread-is-accepted-and-silently-ignored-so-thread-local-storage-is-shared]],
and the two frontends fail in OPPOSITE directions on the same missing feature —
Pascal refuses loudly, C accepts and shares one `.bss` object. Whoever builds
the mechanism should close both; the honest failure and the silent one have the
same cause.

## 2026-09-09 (frankH) — the blocking question is SETTLED, and the answer is no

The note above says the fork to settle first is *"does anything in the intended
implementation emit or consume an ELF TLS relocation?"* — one measurement, not
a discussion. Taken:

**`compiler/` contains no ELF TLS machinery of any kind.** A grep across the
whole compiler for `TPOFF`, `DTPMOD`, `DTPOFF`, `TLSGD`, `TLSLD`, `GOTTPOFF`,
`R_X86_64_TLS`, `PT_TLS`, `SHF_TLS`, `.tbss` and `.tdata` returns exactly two
hits and both are PROSE — `cparser.inc:9913` and `:12627`, comments recording
that glibc's `errno` is `.tbss` and ours is not. No emitter, no relocation
table, no section.

**And the access shape structurally cannot need one.** A per-thread access here
is an ordinary instruction with a `$65` segment-override byte in front and a
CONSTANT displacement — `exception_emit.inc:63` (`if t >= 0 then EmitB($65)`)
and its comment: *"`mov rax, gs:[8*k]` is the same instruction as `mov rax,
[abs]` with a 0x65 prefix in front"*. A constant displacement into a block
whose base the runtime installed is not a relocated symbol reference.

So [[decide-pxx-thread-local-storage-is-gs-relative-and-the-x86-64-psabi-is-fs-relative]]
**is about a different program.** Its fork is the `--emit-obj` / `--shared`
BOUNDARY — a gcc object's TLS relocations against ours — and a pxx-only
`threadvar` never reaches it. Not wired as an edge, in either direction, for
exactly the reason the note above gives for not wiring one on prose.

### The mechanism, measured end to end rather than read

    program tls1; uses palthread;
    ... WriteLn(PtrUInt(__pxxTlsBase)) in main, in a PalThreadCreate child, in main again

    main   base 4364032          (the BSS block, ir_codegen.inc:1593)
    child  base 131998540794496  (its own, carved off its stack by the clone stub)
    main   base 4364032          (unchanged after the join)

`AN_TLSBASE`/`IR_TLSBASE` already exist and are already reachable from Pascal as
`__pxxTlsBase`, x86-64 only with an explicit refusal naming the reason on every
other target. **So the address of a `threadvar` is `__pxxTlsBase + <constant>`,
which is ordinary existing IR** — no new backend op, and every type works,
because it is an ADDRESS and not a word-sized accessor.

### Sizing, which the decide ticket demands be done FIRST

The three free slots are not the plan and must not be. `TLS_BLOCK_SIZE = 1152`
is a compile-time constant read by the main-thread BSS reservation
(`ir_codegen.inc:1593`) and by the clone stub (`thread_emit.inc:108/114/158/176`)
— both emitted by the same compiler in the same run, so growing it at EMIT time
needs no negotiation through `__pxxclone`'s signature. That sentence in
`defs.inc` is about a RUNTIME-growable block and does not bind this.

Threadvars go PAST slot 143, so every existing offset — the slot map, the
64-class magazine heads and counts — is unmoved.

**The measured headroom is the stack floor, and it is large.**
`lib/rtl/palthread.pas`'s `PAL_MIN_STACK` is 128 KiB against a stub that carves
1152 + 32768 + 256 ≈ 34 KiB, so roughly 90 KiB of threadvars fit before the
floor itself has to move. That number is a SECOND COPY of the stub's
requirement and palthread.pas says so in its own comment; whatever grows the
block has to move both.

### The funnel census — measured, and it is the reason this is parked rather than done

The mechanism is settled and cheap (above). What is NOT cheap is reaching every
place that turns a variable into an access, and I measured four candidate
layers before parking. **None of them is a funnel**, which is the finding:

| layer | sites | why it is not the door |
| --- | --- | --- |
| the PARSER, at `AllocNode(AN_IDENT)` | ~80 in the Pascal frontend alone (26 `_lval`, 21 `_expr`, 21 `_stmt`, ...) | a rule spelled per caller; the site nobody edits keeps building a plain global reference |
| `ir.inc`, at the lowering | 449 `IR_LOAD_SYM` / `IR_STORE_SYM` / `IR_LEA` appends | most are compiler temps, but there is no one arm an ident must pass through |
| the BACKEND, at `EmitGlobRef` | 42 in `ir_codegen.inc` alone, times seven backends | same shape, one layer down |
| `TSymKind`, a new `skThreadVar` | 175 `skGlobal` tests tree-wide, 20 in `ir_codegen.inc` | **and this one fails DANGEROUSLY** |

**The fourth row is why a storage class is the wrong first instinct.** Every one
of those 175 sites is written as `if Kind = skGlobal then <absolute/RIP> else
<rbp-relative>`. A fourth kind that a site has not been taught falls into the
`else` — so a threadvar would be addressed **rbp-relative**, as a local, at
every site nobody updated. That is a plausible wrong address inside the current
frame, not a crash and not a link error, and it is the failure mode this repo
spends its days on.

**So the shape that survives the census is a FLAG on the symbol, not a kind.**
Keep the symbol `skGlobal` with real storage, add `SymTlsOffset` (-1 = not a
threadvar), and replace `Kind = skGlobal` with a shared "how is this symbol
addressed" helper at the ~20 x86-64 sites that actually compute an address.
Untaught sites then keep answering `skGlobal`, which is wrong but LINKS and is
process-wide — the same failure the C sibling has today, loud enough to find —
rather than pointing into the caller's frame.

The other six targets refuse, which is already the established pattern:
`__pxxTlsBase` refuses off x86-64 with a diagnostic naming the reason
(`pasparser_expr.inc:4286`), and a `threadvar` must refuse the same way rather
than silently becoming a shared global — that IS
[[bug-c-__thread-is-accepted-and-silently-ignored-so-thread-local-storage-is-shared]],
one frontend over.

**PARKED, not abandoned, and re-claim before resuming.** What is banked is the
part that costs an hour to rediscover: the blocking fork is settled, the
mechanism is proven end to end, the sizing route is `TLS_BLOCK_SIZE` at emit
time with ~90 KiB of measured headroom and a second copy in `palthread.pas`,
and the four candidate doors are counted with the dangerous one named. What
remains is an addressing change in the hottest file in the compiler, and the
neighbouring decide ticket's rule applies to it directly: **size the area
first, demonstrate second** — a threadvar that fits in the three free slots
would prove the part that was never in doubt.

## Parked 2026-09-09

banked: the blocking fork is settled and the mechanism proven end to end; what remains is an addressing change at ~20 x86-64 sites plus emit-time block sizing, and the funnel census is in the ticket

**Before resuming:** read the reason above, then the ticket body. If the reason does not tell you what would make this worth picking up again, establishing that is the first step -- a park is a handoff to a stranger who may be you.
