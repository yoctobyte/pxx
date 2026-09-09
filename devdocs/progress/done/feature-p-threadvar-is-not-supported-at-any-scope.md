---
slug: feature-p-threadvar-is-not-supported-at-any-scope
title: "`threadvar` is not supported at any scope"
track: P
prio: 40
type: feature
blocked-by: []
status: done
owner: frankH
created: 2026-09-06
summary: "DONE for scalars at unit and program level, x86-64. A threadvar reference is REWRITTEN at CompileAST into a dereference of __pxxTlsBase + a constant, so no consumer downstream sees a threadvar symbol and no addressing rule is spelled per caller -- the funnel census in this ticket counted 80/449/42/175 sites for the four doors that look like one. Storage is TLS_USER_BYTES past the slot map, a fixed cap because EmitTlsMainInstall runs before parsing. Byte-identical to fpc on the single-threaded language surface; per-thread proven under 4-thread churn with a plain global as the positive control. Refused by name inside a routine, in a class/record body, with an initializer or `absolute`, for non-scalar types, off x86-64 and under --emit-obj. Remaining rungs: managed and aggregate types, `class threadvar`, and the C sibling."
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

---

## 2026-09-09 (frankH) — BUILT. `threadvar` works at unit and program level

Resumed from the park above. The banked half held: the fork was settled, the
mechanism was right, and the funnel census was the part that saved the time —
it named the door that does not exist and the one that does.

### The door, which is none of the four the census counted

Not the parser, not `ir.inc`, not `EmitGlobRef`, not a fourth `TSymKind`. The
door is **`CompileAST`** — the one routine every Pascal AST passes through on its
way to IR — and what happens there is a **rewrite, not an addressing mode**:

```
AN_IDENT(threadvar sym)   ->   AN_DEREF( AN_TLSBASE(+off) )
```

in place, so every parent's pointer stays valid and no parent fixup exists to
get wrong. `AN_DEREF` is already a first-class lvalue — assignment, `@`, a var
parameter, a field, an index all route their address through
`IRLowerAddress`'s `AN_DEREF` arm — so **nothing downstream knows the word
threadvar**. That is `normalise-dont-special-case.md`'s argument applied
literally: reach the construct through a shape that already works instead of
growing a second path that stays broken.

The offset rides on `AN_TLSBASE`'s `ASTIVal` rather than being built out of AST
arithmetic, which sidesteps "does `Pointer + Integer` add bytes or scale" — at
the IR level that question does not exist, `IR_BINOP` on a tyPointer operand is
a raw byte add (the same one `AN_FRAME`'s `frame - 8` uses). One arm in
`ir.inc`, no casts in the frontend, and `__pxxTlsBase` itself is unchanged
because its offset is zero.

`SymTlsOffset` is a FLAG on the symbol, not a kind — exactly as the census
argued. The symbol stays `skGlobal` with real (unused) BSS storage, so a path
nobody taught reads a process-wide global rather than an rbp-relative address
in the caller's frame.

### Storage: a fixed cap, and the ordering reason it is not grown

`TLS_USER_BYTES = 3072` (384 slots) sits past slot 143, so **no existing offset
moves** and the slot map stays the ABI it was. The clone stub already zeroes the
whole block, so a thread's copies start at 0 with nothing added — the language
requires that and a test asserts it.

Fixed rather than grown because **`EmitTlsMainInstall` runs from `compiler.pas`
BEFORE `ParseProgram`** — it emits the entry-point prologue, so it reserves
`BSS_TLS_MAIN` and bakes the size into the clone stub's carve before a single
`threadvar` has been seen. Growing it needs that reservation to move after
parsing, i.e. the entry prologue stops being the first thing emitted. Out of
scope for this rung; the exhaustion diagnostic names the constant and
`lib/rtl/palthread.pas`'s second copy of the carve was raised with it.

### The one-statement bug, banked because it looked right

The first rewrite used a high-water mark on `ASTNodeCount` — "nodes are only
ever appended". **They are not**: the AST arena is rolled back per statement
(`ASTNodeCount := ASTArenaFloor`, twelve sites), so node indices are REUSED and
a monotonic watermark skips any statement whose tree is SMALLER than the
previous one's. After a `uses palthread`, whose unit bodies had pushed the count
high, that was the very first statement of the main body:

```
mine := 7;  WriteLn('A mine=', mine);   ->  A mine=0
mine := 8;  WriteLn('B mine=', mine);   ->  B mine=8
```

`dummy := 1` in front of it made it pass, which is the tell — **a defect that
moves when you add an unrelated line is about node numbering, not about the
feature**. The range is now `[ASTArenaFloor .. ASTNodeCount)` plus the unswept
part of the permanent region below the floor.

### What is refused, and every refusal says what would have to change

| refused | why |
| --- | --- |
| inside a routine | FPC's rule; the fall-through was `expected 'begin' before 'threadvar'` — this ticket's own filing message |
| in a class or record body | two arms, two member loops; see below |
| an initializer | the tables are flushed once, on the main thread, so the value would reach that copy and no other |
| `absolute` | the overlay is process-wide; both cannot be true of one name |
| a non-scalar type | managed types need per-thread init/final at thread start and exit, which no hook exists for; a record/set is reached through its symbol |
| an array | same reason, plus bounds and dyn handles |
| not x86-64 | the same refusal `__pxxTlsBase` gives, for the same reason |
| `--emit-obj` / `--shared` | no ELF entry point installs a block, and `gs:` with no base faults — or worse, returns glibc's TCB |

### The corpus rows, re-measured as the ticket asked

All four now refuse **by name** instead of through a parse gap:

| row | before | after |
| --- | --- | --- |
| tclass17 `%FAIL` | `expected ':' before 'Test'` | `threadvar is not allowed in a class or record body` |
| terecs21 `%FAIL` | same | same |
| tclass16 | `class here must be followed by const, var, ...` | same |
| terecs20 | `expected ':' before 'Test'` | same |

The two `%FAIL` rows were passing on **any** refusal, and the one they were
getting had nothing to do with their subject — the `threadvar` was being read as
a FIELD NAME. The class body and the record body have SEPARATE member loops, and
fixing only the class arm left terecs20 still failing the old way: one arm of a
double case, caught by grepping for the sibling before closing.

`class threadvar` (tclass16, terecs20) remains unsupported and is the rung
above; those two also still need the RTLEvent family
(`feature-b-the-rtlevent-family-is-absent-from-the-threading-rtl`).

### Verification

- `test_a_threadvar_is_a_variable.pas` — the LANGUAGE surface, single-threaded,
  **byte-identical to `fpc -Mobjfpc`** (FPC 3.2.2). Scope, `@`, a var parameter,
  arithmetic, `Inc`/`Dec`, a second name in the group, `Double`, `Pointer`, and
  a `var` section the threadvar section did not eat.
- `test_a_threadvar_is_per_thread.pas` — 4 threads, 200000 iterations, with a
  **plain global as the positive control**: `control-raced` asserts the harness
  can see cross-talk, so the two rows can only both pass if the storage really is
  per-thread. Replacing `threadvar` with `var` in that exact file gives
  `kept=1/4 zeroed=0/4 no-crosstalk=1/4 main-copy=103`.
- Seven refusal rows, one file per diagnostic, each with a branched-on `!`.
- `gate.sh quick` GREEN with `compiler/**` uncommitted (FPC seed canary ran);
  self-host fixedpoint `converged after 1 round(s)`, `7052ba37afa1`.

### The C sibling

[[bug-c-__thread-is-accepted-and-silently-ignored-so-thread-local-storage-is-shared]]
is now the only half of this missing. The mechanism it needs is built and is
frontend-agnostic — `SymTlsOffset`, the user area, and an `AN_TLSBASE`-rooted
deref — so what remains there is the C frontend's own rewrite site, not a new
mechanism. Left for its own lane; not wired as an edge, because neither gates
the other.

## Log
- 2026-09-09 — resolved; the implementation and the resolve rode one commit — commit 7a166c995. The rewrite site is `ThreadVarRewriteRange` in `compiler/ir_codegen.inc`, called from `CompileAST`; storage is `TLS_USER_BYTES` in `compiler/defs.inc`; the section parser is `ParseThreadVarSection` in `compiler/pasparser_decl.inc`.
