# RETRIAGE — proposal, not applied

**Status: PROPOSAL. No `prio:` field in any ticket has been changed.** This file is
the whole deliverable; the owner reviews it, then someone applies (or overrules) it.

- **Date:** 2026-08-25 · **Scope:** all 292 tickets `tools/progress.sh ready` returns.
- **Excluded by charter:** `float/` (Track F) and `experimental/` (Tracks R, Z) —
  deliberately parked and unranked. Untouched.
- **Track U `decide-*` tickets are listed but their prio is owned by the Track U
  agent working that folder concurrently.** Treat those rows as context, not as a
  competing proposal.

## Why

> *"The tickets seem to seek edge cases, not real world targets. we're not seeking
> utopia, we're seeking a pragmatic tool. triaging tickets is actually the issue.
> i see low-prio tickets that i would rank highest. and vice versa."* — owner

The ranking basis proposed here is **"which real-world target does this unblock"**,
not a hand-assigned integer. Product spec: *can it compile and correctly run real
programs.*

### Ranking bands used

| band | class | meaning |
| --- | --- | --- |
| 70-90 | **A** | Blocks a named real-world target. Ticket says which. |
| 40-69 | **B** | Real defect — wrong answer, crash, hard refusal — that no listed target currently hits. |
| 3-29 | **C** | Edge case / conformance polish: diagnostics wording, spec corners, layout parity, refusals nobody's program depends on. |
| — | **D** | Infrastructure / tooling / docs. Ranked by whether it unblocks an A, not by its own subject. |

Within a band, a **silent wrong value outranks a loud refusal**, and a **crash
outranks both** — the repo's own debugging note says the expensive bugs here do not
crash, they produce a plausible wrong value far from the cause.

## Result: the ranking now discriminates

`prio:` currently has almost no dynamic range — ~200 of 292 sit in the 25-45 band,
and since `progress.sh` propagates prio down dependency edges, a flat input gives a
flat output.

```
            CURRENT                          PROPOSED
 0- 9:   3  ###                    0- 9:  11  ###########
10-19:  17  #################     10-19:  25  #########################
20-29:  48  ################...   20-29:  46  ##############################################
30-39: 102  ################...   30-39:  43  ###########################################
40-49:  85  ################...   40-49:  56  ##################################################
50-59:  25  #########             50-59:  50  ##################################################
60-69:   8  ########              60-69:  32  ################################
70-79:   4  ####                  70-79:  22  ######################
80-89:   0                        80-89:   7  #######
```

Class split: **A 86 · B 78 · C 67 · D 61**.

---
## 1. THE DISAGREEMENTS — read this section, skip the rest if you like

### 1a. Currently LOW, should be HIGH

| Δ | now→proposed | track | slug | why it is a real-world blocker |
| --- | --- | --- | --- | --- |
| **+60** | 15→**75** | P | `feature-pascal-corpus-expansion` | **The single most inverted item on the board.** C got a driven real-world ladder (c-testsuite → zlib → cJSON → lua → sqlite → tcc, all green and wired). Pascal never got one, and it sits at prio 15. Given the stated goal this should be near the top of Track P. |
| **+42** | 30→**72** | N | `feature-nilpy-stdlib-coverage-gaps-measured` | `os` is undefined **entirely** — no `os.path.basename`, no `os.path.exists` — and `time.time()` does not resolve. Nearly every real Python script touches `os.path` in its first page. |
| **+40** | 25→**65** | N | `bug-n-a-unicode-identifier-is-rejected-by-the-lexer` | Two tinycss2 files name colour-space constants with Greek letters, so the corpus ladder stops on a **lexer** row. Small, self-contained, directly unblocks corpus files. |
| **+40** | 25→**65** | A | `feature-typeinfo-ttypedata-payloads` | Self-declared "not urgent, no consumer" — but `gap-b-typinfo-ptypedata…` (65) and `feature-typinfo-facade-unit` (50) **are that consumer now**, and Generics.Defaults reads `OrdType`. It is the blocker of a 78. |
| **+38** | 30→**68** | N | `feature-nilpy-user-defined-decorators` | The decorator list is a **name whitelist**, so nothing a program declares itself can appear in it. An ordinary `@wrap` over a `def` is refused at parse time. |
| **+35** | 45→**80** | N | `bug-n-a-class-base-that-is-an-expression-does-not-compile` | Named in the ticket as **the single remaining wall on html5lib's `html5parser.py`** (`six.with_metaclass`). The most directly target-blocking N ticket that exists. |
| **+35** | 40→**75** | N | `bug-nilpy-empty-str-and-none-are-the-same-value` | `"" is None` answers **True**. `if x is None` is in every Python program ever written. Silent wrong branch, and it contradicts pylib's own stated contract. |
| **+35** | 35→**70** | P | `feature-pascal-typed-and-untyped-files` | `file of T` and untyped `file` are refused **outright**; only `TextFile` works. That is the classic Pascal record-file idiom and a whole category of real programs. |
| **+35** | 35→**70** | N | `feature-nilpy-staticmethod-and-classmethod` | `@staticmethod` / `@classmethod` **rejected**. They appear in essentially every real Python class of any size, html5lib included. |
| **+35** | 35→**70** | N | `bug-nilpy-redefining-a-def-rebinds-calls-that-came-before-it` | Calls written *before* a redefinition run the *later* body. Silent wrong value on a valid CPython program, no diagnostic — it already made unrelated test rows print binary garbage once. |
| **+35** | 25→**60** | C | `idea-c-realworld-test-targets` | Filed as an "idea" at 25. Real C programs are the best bug-finders we have — lua and sqlite each surfaced a dozen genuine codegen/ABI/crtl bugs no synthetic test caught. This IS the C real-world driver. |
| **+35** | 20→**55** | N | `bug-nilpy-except-tuple-binder-is-typed-by-the-first-arm-only` | `except (A, B) as e` reads B's object at A's field offsets. Harmless inside Python's own hierarchy; a **silent wrong value** the moment a tuple crosses hierarchies — which every mimic module declaring Pascal exceptions does. |
| **+35** | 10→**45** | B | `feature-crtl-implement-libc-assumptions` | The standing collector for the libc assumptions real C leans on, driven by what real corpora actually touch. C-side companion to the ladder; at prio 10 it is invisible. |
| **+33** | 45→**78** | N | `bug-n-class-x-inherits-mod-x-is-refused-in-the-main-program` | How **all ~100** of CPython's `encodings/*.py` and three html5lib filters are written. Refused only on the program path — a name-collision bug, not a design position. |
| **+33** | 25→**58** | P | `compat-pascal-class-helpers` | `class helper for T` is a parse error while `record helper` and `type helper` work. Standard modern FPC/Delphi. (Duplicate of `feature-p-class-helper-for-a-class-type` @35 — merge.) |
| **+32** | 40→**72** | P | `feature-p-fpc-global-operator-overload-declarations` | First wall on the `cutils`/`cstreams` path behind the FPC-compiler define profile. **"FPC itself" is a named compat target** in CLAUDE.md. |
| **+32** | 40→**72** | P | `feature-p-fpc-assigned-enum-ordinals-with-colon-equals` | Sibling wall on the `cclasses`/`globtype` path. Same named target. These two are the whole remaining distance to a real milestone and they idle at 40. |
| **+32** | 30→**62** | N | `feature-nilpy-list-sort-inplace-key-reverse` | `xs.sort(key=…, reverse=…)` is a **compile error**; only the free `sorted()` takes them. In-place sort with a key is everywhere. |
| **+30** | 45→**75** | B | `feature-b-rtl-gap-inventory-22-sysutils-strutils-symbols` | 22 measured symbols FPC has and pxx rejects — "a directory-walking or PChar-using program simply does not compile". Pure coverage; everything already implemented is byte-identical to FPC. |
| **+30** | 35→**65** | B | `feature-b-text-file-surface-seekeof-rename-settextbuf` | `SeekEof`/`SeekEoln` are the whitespace-tolerant loop conditions ordinary token-reading code uses. All four are compile-time `undefined variable`. |
| **+30** | 35→**65** | N | `feature-nilpy-iter-and-next-over-a-container` | `iter(xs)` is undefined. The explicit iterator protocol is fundamental Python. |
| **+30** | 25→**55** | T | `bug-t-run-pascal-conformance-silently-fails-every-test-on-a-relative-compiler-path` | A relative `$CC` makes **51 of 107** tests report `compile error` — i.e. as *compiler* bugs — all at once. The absolute path passes 61/0. This poisons the entire Pascal conformance signal. |
| **+30** | 25→**55** | N | `bug-n-super-as-an-expression-fails-with-a-misleading-diagnostic` | `return super().hi()` is ubiquitous in real class hierarchies, and the diagnostic names neither the construct nor the right line. Two costs in one ticket. |
| **+28** | 60→**88** | N | `bug-n-inferred-return-type-of-true-division-is-int` | Unannotated `return x / 2` prints the float's **raw bit pattern as an int**. Silent wrong value, hits every corpus program that divides. |
| **+23** | 65→**88** | B | `bug-b-read-of-a-number-from-a-text-file-reads-the-whole-line` | `readln(t, n, m)` on `'42 3'` silently yields `0 0`. Reading numbers from a text file is table stakes; no error, no exception, no diagnostic. |

### 1b. Currently HIGH, should be LOW

| Δ | now→proposed | track | slug | why it does not deserve the rank |
| --- | --- | --- | --- | --- |
| **n/a** | 40→**0** | A | `chore-makefile-ws-skeleton-loop-hides-tmp-paths` | **The ticket file does not exist** in any status folder, yet `ready` ranks it. Dangling board entry — delete or restore it. |
| **−35** | 55→**20** | T | `feature-t-freebsd-image-and-runner` | Install qemu so a **FreeBSD port** can start. FreeBSD is not a named product target; nothing in the C/Pascal/Python real-world set needs it. The clearest upward misrank in the queue. |
| **−35** | 70→**35** | N | `regression-test-nilpy-test-nilpy-callable-to-str-param-fails` | An auto-filed watcher stub over a **refusal test** (`*_fail`), 132-commit bisect range. A feature landing turns its own refusal test red — verify it is not simply obsolete before ranking it at 70. |
| **−25** | 70→**45** | N | `regression-lib-test-lib-mimic-xml-etree-elementtree-2` | 137-commit range, and the ticket itself says the job builds only with `PXX_STABLE` so **the named sha cannot be the cause**. Re-verify at HEAD; do not carry 70 on an unsound bisect. |
| **−25** | 65→**40** | C | `feature-c-csmith-differential-fuzzing` | A synthetic-program campaign at prio 65 while eight *wired real* C corpora exist. It finds real bugs — but it is literally the edge-case generator, and it outranks the real-world C driver (`idea-c-realworld-test-targets`, currently 25) by 40 points. That inversion is the owner's complaint in one line. |
| **−25** | 45→**20** | A | `feature-cross-frontend-interop-contract` | Self-declared "scoping only, no code yet, **unranked**". Not dispatchable work. |
| **−25** | 45→**20** | A | `meta-constant-normalisation` | Standing governance index, never "done". Rate the linked tickets. Ranking a never-completable item is exactly how `meta-dialect-extensions` once topped `next --track A`. |
| **−25** | 45→**20** | A | `feature-nilpy-idf-import` | North-star ESP integration milestone. Aspirational by its own text. |
| **−25** | 40→**15** | D | `task-d-document-own-language-first-in-the-language-reference` | Explicitly **blocked until the symbol rule is built**. Documenting behaviour the compiler does not have is worse than documenting nothing. |
| **−23** | 58→**35** | O | `feature-opt-o3-register-pressure` | -O3 umbrella. Landed slices are pinned; the rest is soak plus a promotion gate that needs the full matrix. No target waits on it, and `-O2` remains the proven default. |
| **−23** | 53→**30** | S | `feature-esp-peripheral-callback-api` | ESP peripherals. The whole ESP axis is off the critical path for "a pragmatic C + Pascal + Python compiler". |
| **−23** | 35→**12** | N | `bug-n-abs-of-a-complex-raises-typeerror` | `abs()` of a **complex number**. `type`, `.real`, `.imag` and `round()` already match CPython exactly. This is the definition of an edge case. |
| **−20** | 45→**25** | S | `feature-esp-hardware-flash-validation` | Requires a board on USB; **un-automatable in-harness**. It cannot be dispatched to an agent at all, so it should not sit above work that can. |
| **−20** | 45→**25** | W | `feature-web-track-w-bootstrap` | Website lane bootstrap; wants a dedicated creative session, not queue time. |
| **−20** | 50→**30** | A | `feature-nilpy-collections-and-string-methods` | Filed 2026-07-10 describing a NilPy that no longer exists — most of the listed surface has landed. **Likely stale; re-scope or close.** |
| **−20** | 40→**20** | A | `bug-a-nilpy-leading-double-star-in-a-call-is-not-detected` | Its own sibling ticket records this as **fixed in `a057789bc`**. Verify and close rather than rank. |
| **−20** | 55→**35** | E | `feature-demo-portable-userland` | Umbrella/demo arc with no dated target. |
| **−20** | 25→**5** | P | `compat-pascal-directive-in-comment-ignores-nested-comments-off` | We are **laxer** than FPC; the one-line fix **breaks the self-build** and is already tried-and-reverted. Nothing real depends on rejecting this. |
| **−18** | 40→**22** | A | `refactor-a-seven-frontends-borrow-rust-parser-helpers` | Costs nothing today; it makes R and Z individually unomittable. A build-configuration nicety. |
| **−17** | 35→**18** | S | `feature-c-esp-conformance-coverage` | C conformance on bare ESP, needing its own UART-capture harness. The desktop cross matrix already landed and is where real C runs. |

Plus a tail of conformance-polish items proposed **below 15** that currently sit at
20-30 and therefore compete with real work: `compat-pascal-strict-fpc-should-reject-a-duplicate-identifier-in-one-scope`
(20→5 — pxx compiles it and resolves **both** names correctly), `compat-pascal-method-impl-without-declaration`
(20→8 — we accept what FPC rejects), `compat-pascal-strict-fpc-abs-and-sqr-widths` (20→8),
`compat-pascal-binop-operand-eval-order` (15→3 — self-declared "documented, deliberately
unfixed, rainy-day"), `compat-pascal-not-of-a-cast-constant-keeps-its-width` (10→3 — we
match Delphi), and `feature-nilpy-nested-def-as-value` (15→5 — its own header says
**SUPERSEDED**; it belongs in `rejected/`, not in the ready queue).

---

## 2. Structural findings the numbers cannot express

### 2.1 `ready`/`next` do NOT scan `unfinished/` — CLAUDE.md says they do

`tools/progress.py:628` — `ready_tickets()` iterates **`backlog`, `backlog_new`,
`urgent`** only. `unfinished/` and `blocked/` are never ranked. CLAUDE.md states in
two places that the ranker scans `urgent`/`working`/`unfinished`/`backlog`.

The consequence is that **30 tickets are invisible to the queue, including the
highest-`prio:` open item in the entire repo**:

| prio | folder | slug |
| --- | --- | --- |
| **88** | unfinished | `bug-n-calling-through-a-function-alias-with-a-default-omitted-segfaults` — a SEGFAULT |
| **85** | blocked | `bug-n-an-import-alias-binds-to-a-same-named-member-of-the-source-module` |
| 70 | blocked | `regression-cascade-4e27dc2be114` |
| 65 | unfinished | `feature-nilpy-thirdparty-libraries-as-targets` — **the html5lib/tinycss2 ladder itself** |
| 65 | unfinished | `feature-pascal-corpus-fpc-testsuite`, `feature-pascal-corpus-generics`, `feature-nilpy-cpyext-c-api-from-source` |
| 65 | unfinished | `bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython` |
| 62 | unfinished | `bug-n-an-attribute-on-an-unresolved-import-degrades-to-a-bare-name`, `feature-b-the-module-shim-batch-blocking-the-python-corpus` |
| 60 | blocked | `bug-nilpy-songformatter-no-longer-compiles-set-callback-and-get-arity` |

**This is a bigger triage defect than any individual prio.** The four highest-value
Python real-world-target tickets in the repo are parked where nothing dispatches
them, and the board tells agents otherwise. Fix one of: the code, or the doc — and
say which is intended. (Filed as an observation, not edited: `tools/progress.py` is
not mine to touch and `devdocs/dev/**` belongs to another lane.)

### 2.2 Duplicate pairs found — merge before applying any prio

| # | pair | note |
| --- | --- | --- |
| 1 | `bug-b-inttostr-of-a-qword-above-2-63-renders-negative` (45) ⟷ `bug-b-inttostr-of-a-qword-prints-it-signed` (40) | Same defect, same file, filed a day apart. |
| 2 | `feature-t-gate-quick-should-smoke-the-pinned-compiler` (60) ⟷ `bug-t-gate-quick-cannot-see-a-broken-pinned-rtl` (45) | Both are the same ~1s pinned-compiler canary, both from the same 2026-08-21 incident. |
| 3 | `compat-pascal-class-helpers` (25) ⟷ `feature-p-class-helper-for-a-class-type` (35) | Same syntax, same refusal. |
| 4 | `decide-tobject-classinfo-blob-or-refusal` (42) ⟷ `decide-classinfo-returns-our-blob-or-nothing` (35) | Same three options, same recommendation. Track U's to merge. |

### 2.3 Stale / dead entries in the ready queue

- `chore-makefile-ws-skeleton-loop-hides-tmp-paths` — **ranked but has no file.**
- `bug-a-nilpy-leading-double-star-in-a-call-is-not-detected` — recorded as fixed by its sibling.
- `feature-nilpy-nested-def-as-value` — header says SUPERSEDED.
- `feature-nilpy-collections-and-string-methods` — describes a July NilPy; most has landed.
- Two of the three prio-70 `regression-*` stubs carry 132/137-commit bisect ranges and
  self-documented reasons why the named sha cannot be the cause.

### 2.4 The real-world target set, corrected

The draft target set I was given is directionally right but wrong in three places.
Verified against `Makefile`, `tools/testmgr.py` tiers, `tools/nilpy_ladder.py`,
`tools/install_lib_candidates.sh` and the `done/` corpus tickets:

| lang | **WIRED** (built + asserted today) | in progress | aspirational / rejected |
| --- | --- | --- | --- |
| Pascal | self-host fixedpoint (the universal gate) · **Synapse** (in `lib-test`, incl. OpenSSL 3) · fcl-**fpcunit** · fcl-**fpjson** · **fpc-testsuite** conformance battery | rtl-generics (blocked on `gap-b-typinfo…`) | **fgl — NOT wired** (a dated probe only) · fcl-passrc (stalled, "endgame") · fcl-xml (unfiled) · DWScript / Pascal-Script / mORMot ("not now") · **LCL/Lazarus and gpc: out of scope / rejected** |
| C | **zlib** (output byte-identical to a gcc-built zlib) · **sqlite3** (5 targets) · **lua 5.4** · **tcc** self-compile · **QuickJS** · **Duktape** · **chess perft** · **cJSON**, stb · **c-testsuite** (220 programs + cross) | GTK3 header wiring | busybox, DOOM, micropython, p2c, GCC-itself |
| Python | **uforth** — a real 4,357-line Forth interpreter, byte-identical to CPython on the *entire* ANS Forth-2012 suite; testmgr calls it "the densest NilPy regression corpus" · **sqlite CRUD** · the `mimic_*` set (xml.etree, xml.dom, xml.sax, collections.abc, six, bisect, urllib, codecs…) diffed against CPython in `lib-test` | **html5lib / tinycss2 / webencodings** — the "ladder", measured by an **unwired** script against gitignored trees; the Makefile targets it was meant to deliver were never built | reportlab (parked) · `lib/pyrecipes/` (design proposal, no files) |
| all | a **curated subset** of `examples/**` hard-asserted inside `lib-test`/`test-core` | — | `make demos` is a **dashboard, not a gate** — it exits 0 on failure by design |

Three corrections that change how tickets rank:

1. **`uforth` is the biggest Python real-world target and the draft omitted it.** Any
   ticket touching uforth's corpus signal (e.g. `bug-n-a-uforth-corpus-timeout-is-reported-as-a-cpython-divergence`)
   is protecting our densest oracle, not doing harness chores.
2. **`fgl` is aspirational, not wired.** Do not rank tickets as "unblocks fgl" the way
   you would rank "unblocks Synapse".
3. **`html5lib` is not wired either** — but it is the *live campaign*, and the N bugs
   naming it (`class base is an expression`, `class X(mod.X)`, the collections.abc
   mixin family, the Greek-letter lexer row) are the highest-value A items on the board.

### 2.5 One pattern worth naming

Of the 67 tickets classed **C**, the largest single family is **FPC layout/size
parity**: `set of TE8` is 32 bytes not 4; a subrange is 4 bytes not 1; `string[20]`
is a handle not a shortstring; a record holding one is 24 bytes not 11. Every one of
these tickets says, in its own words, *"values are all correct"*. They cost memory
and break binary interop, and they do not stop a single real program from compiling
and running correctly. They currently occupy 20-40; they belong at ~22.

The mirror image is the family classed **A** that currently sits at 25-35: hard
refusals of syntax that real code actually writes — `file of T`, `class helper for T`,
`@staticmethod`, `{$packrecords c}`, `const S: PChar = '…'`, `uses X in 'X.pas'`,
`s.Length`. **Rank the refusal, not the divergence.**

---

## 3. Full table

Sorted by proposed priority, descending. `Δ` is proposed − current.

| prio | Δ | track | slug | cls | reason |
| ---: | ---: | :---: | --- | :---: | --- |
| **88** | +23 | B | `bug-b-read-of-a-number-from-a-text-file-reads-the-whole-line` | A | readln(t,n,m) silently yields 0 0. Reading numbers from a text file is table stakes for any real Pascal program; silent wrong value, no diagnostic. |
| **88** | +28 | N | `bug-n-inferred-return-type-of-true-division-is-int` | A | Unannotated `return x / 2` prints the float's raw bit pattern as an int. Silent wrong value on ordinary Python; hits every corpus program that divides. |
| **85** | +15 | T | `bug-t-the-native-tier-times-out-and-publishes-a-contentless-red` | D | Track T publishes RED with nothing attributed; every lane's regression signal is blind until this is fixed. Highest-leverage item on the board. |
| **82** | +27 | N | `bug-n-sorted-by-a-key-returning-a-string-bearing-tuple-segfaults` | A | SEGFAULT on sorted(key=f) for an ordinary key shape. Crash beats every polish item in the queue. |
| **80** | +35 | N | `bug-n-a-class-base-that-is-an-expression-does-not-compile` | A | Named as THE single remaining wall on html5lib's html5parser.py (six.with_metaclass). The most directly target-blocking N ticket on the board. |
| **80** | +22 | N | `bug-n-from-collections-import-counter-binds-something-that-always-answers-zero` | A | Counter silently answers 0 for every key. Silent wrong value in one of the most-used stdlib names; breaks the consume-and-ignore contract. |
| **80** | +25 | N | `bug-n-hasattr-through-an-untyped-parameter-is-always-false` | A | hasattr is always False through an untyped param — how CPython code dispatches on duck type. Silent, never an error, hits every real library. |
| **78** | +13 | B | `gap-b-typinfo-ptypedata-has-no-ordtype-and-is-just-ptypeinfo` | A | Blocks Generics.Defaults/Collections (corpus rung 3, already blocked-by this) and every TypInfo-driven real library. |
| **78** | +23 | N | `bug-n-a-mixin-cannot-iterate-self-and-an-abstract-iter-breaks-its-overrides` | A | The whole ABC mixin pattern; collections.abc Mapping is a named html5lib-ladder shim. Base __iter__ poisons every subclass override. |
| **78** | +23 | N | `bug-n-a-subscript-inside-a-base-class-skips-the-subclass-override` | A | Same mixin family; self[k] in a base method binds to the base's __getitem__. Sibling arm of an already-fixed bug — normalise-dont-special-case applies. |
| **78** | +33 | N | `bug-n-class-x-inherits-mod-x-is-refused-in-the-main-program` | A | How all ~100 of CPython's encodings/*.py and three html5lib filters are written. Refused only on the program path — a name-collision bug, not a design position. |
| **75** | +30 | B | `feature-b-rtl-gap-inventory-22-sysutils-strutils-symbols` | A | 22 measured sysutils/strutils/dateutils symbols FPC has and pxx rejects — a directory-walking or PChar-using program simply does not compile. Pure coverage, everything implemented is already byte-identical. |
| **75** | +35 | N | `bug-nilpy-empty-str-and-none-are-the-same-value` | A | `"" is None` answers TRUE. `if x is None` is in every Python program ever written; contradicts pylib's own stated contract. Silent wrong branch. |
| **75** | +60 | P | `feature-pascal-corpus-expansion` | A | The Pascal real-world ladder Track P NEVER GOT, while C got a driven one (c-testsuite to zlib to cjson to lua to sqlite to tcc, all green). At prio 15 this is the single most inverted item on the board given the stated goal. |
| **75** | +10 | P | `feature-pascal-corpus-oop` | A | Umbrella for the Pascal real-library ladder (fpcunit/fpjson done, generics blocked, passrc stalled). This IS the real-world-target lane for P. |
| **72** | +22 | B | `feature-typinfo-facade-unit` | A | Real code reaches RTTI through the typinfo UNIT, not the bytes. Blocks corpus-generics, the RTTI/streaming line, fpjsonrtti, DWScript. |
| **72** | +17 | N | `bug-n-the-old-style-iteration-protocol-reaches-only-the-for-loop` | A | list(b) returns [] SILENTLY for a __getitem__/__len__ class. Explicitly the sibling arms of a fix that only did the for-loop. |
| **72** | +42 | N | `feature-nilpy-stdlib-coverage-gaps-measured` | A | `os` is undefined ENTIRELY — no os.path.basename, no os.path.exists — and time.time() does not resolve. Nearly every real script touches os.path in its first page. |
| **72** | +32 | P | `feature-p-fpc-assigned-enum-ordinals-with-colon-equals` | A | `(ms_on := 1)` — objfpc's assigned-enum spelling. The wall on the cclasses/globtype path behind the FPC-compiler define profile; FPC-itself is a named compat target. |
| **72** | +32 | P | `feature-p-fpc-global-operator-overload-declarations` | A | Unit-scope `operator :=` — the FIRST wall on the cutils/cstreams path behind the FPC-compiler profile. Same named target as above. |
| **70** | +25 | A | `feature-a-error-does-not-halt-so-a-parse-can-be-speculative` | A | Error() calls Halt, so the compiler stops at the FIRST error and nothing can trial-parse. Stopping at error one is a real usability wall on any real program, and it unblocks NilPy inference. |
| **70** | +25 | N | `bug-n-a-guard-reports-its-own-failure-and-lets-the-call-through` | A | sys.version_info missing AND the compile-time guard for it does not fire. Every real library does a version check in its first ten lines. |
| **70** | +25 | N | `bug-n-an-augmented-subscript-on-a-dunder-class-is-refused` | A | counts[k] += 1 on any __getitem__/__setitem__ class is a hard refusal. The counting idiom is what a dict-like class is written FOR. |
| **70** | +15 | N | `bug-nilpy-a-lambda-returned-directly-is-not-callable` | A | `return lambda x: ...` yields a non-callable. Returning a lambda is core functional Python; the workaround (bind to a local first) is not discoverable. |
| **70** | +35 | N | `bug-nilpy-redefining-a-def-rebinds-calls-that-came-before-it` | A | Calls written BEFORE a redefinition run the LATER body. Silent wrong value on a valid CPython program, with no diagnostic — and it already made unrelated rows print binary garbage once. |
| **70** | +35 | N | `feature-nilpy-staticmethod-and-classmethod` | A | @staticmethod and @classmethod are REJECTED at parse time. They appear in essentially every real Python class of any size, html5lib included. |
| **70** | +35 | P | `feature-pascal-typed-and-untyped-files` | A | `file of T` and untyped `file` are refused OUTRIGHT; only TextFile works. That is the classic Pascal record-file idiom (Assign/Rewrite/Seek/BlockRead) and a whole category of real programs. |
| **70** | +25 | P | `feature-p-delphi-string-helpers` | A | s.Length / s.ToUpper / s.Trim / s.Substring — the DEFAULT style in anything written against Delphi 2009+. Every such source is refused today. |
| **70** | +0 | P | `regression-test-core-test-indexing-length-for-new-inc-positive` | A | Fresh (2026-08-25), 15-commit range, core Pascal indexing/Length. A live red on the self-host lane's own suite. |
| **68** | +18 | E | `feature-demo-songformatter-pxx-target` | A | The owner's OWN real Python app compiled with NilPy. This is precisely the pragmatic real-world target the re-triage is for, and it drives tkinter/subprocess work. |
| **68** | +18 | N | `bug-n-importing-both-f-and-F-from-one-module-loses-the-class` | A | Flat namespace folds case, so importing f and F from one module loses the class. Python is case-sensitive; every real module has both spellings. |
| **68** | +38 | N | `feature-nilpy-user-defined-decorators` | A | The decorator list is a NAME WHITELIST, so nothing a program declares itself can appear in it. An ordinary @wrap over a def is refused at parse time. |
| **65** | +40 | A | `feature-typeinfo-ttypedata-payloads` | A | Self-declared "not urgent, no consumer" — but gap-b-typinfo and the typinfo facade ARE that consumer now, and Generics.Defaults reads OrdType. The blocker of a 78. |
| **65** | +10 | B | `feature-b-a-fourth-corpus-to-test-whether-the-ladder-walls-generalise` | D | The three ladder corpora are ONE family (tinycss2 imports webencodings). Two days of NilPy ranking rest on that sample — this measures whether OUR RANKING is right. |
| **65** | +30 | B | `feature-b-text-file-surface-seekeof-rename-settextbuf` | A | SeekEof/SeekEoln are the whitespace-tolerant loop conditions ordinary token-reading code uses; Rename already has its PAL entry point. All four are compile-time undefined. |
| **65** | +15 | N | `bug-n-a-function-stored-in-a-variable-is-not-equal-to-the-function` | A | g = f makes g == f and g is f False and id() differ. The sentinel-value idiom; filed by the mimic_xml_etree author whose whole risk is this. |
| **65** | +25 | N | `bug-n-a-module-member-named-like-its-module-hides-the-modules-other-members` | A | CPython's own Lib/bisect.py ends with `bisect = bisect_right`, so `import bisect; bisect.bisect_left(...)` fails. Ordinary stdlib-shaped code. |
| **65** | +40 | N | `bug-n-a-unicode-identifier-is-rejected-by-the-lexer` | A | Two tinycss2 files use Greek letters as names, so the ladder stops on a LEXER row. Small, self-contained, and directly unblocks corpus files. |
| **65** | +20 | N | `bug-n-isinstance-does-not-accept-a-qualified-class-name` | A | isinstance(x, mod.Class) is a compile error. Any code importing a module and testing against its classes must rebind first; collections.abc hits it. |
| **65** | +30 | N | `feature-nilpy-iter-and-next-over-a-container` | A | iter(xs) is undefined. The explicit iterator protocol is fundamental Python, and the resumable-position half is what real streaming code needs. |
| **65** | +20 | O | `feature-opt-bulk-copy-is-byte-at-a-time` | B | Copy() moves ONE BYTE per iteration — 23x slower than FPC. A ~10-line word-at-a-time loop was prototyped and measured at 3.3x back. Cheapest real win on the board. |
| **65** | +20 | T | `bug-t-gate-quick-cannot-see-a-broken-pinned-rtl` | D | DUPLICATE of feature-t-gate-quick-should-smoke-the-pinned-compiler. Merge them; one ~1s canary closes a hole that killed three lanes for a day. |
| **65** | +5 | T | `feature-t-gate-quick-should-smoke-the-pinned-compiler` | D | DUPLICATE of bug-t-gate-quick-cannot-see-a-broken-pinned-rtl. A one-line canary; its absence killed Tracks B/D/E on master for a full day. |
| **65** | +25 | U | `decide-rtti-kind-numbering` | A | Track U. typinfo.pas declares FPC's TTypeKind order but the emitted blob carries the compiler's — `RetKind = Ord(tkInt64)` is SILENTLY false. Gates the whole typinfo/generics chain. (Prio owned by the Track U agent.) |
| **62** | +22 | A | `feature-a-typeref-migrate-consumers` | B | The payoff of TTypeRef: ~90 parallel-array sites collapse to one field. Root cause of the "one of six parallel arrays not written" class — four such bugs landed in ONE session. |
| **62** | +22 | A | `feature-unicodestring-model` | A | Blocks fcl-json's jsonparser/jsonscanner \uXXXX path. fpjson is a LANDED corpus rung; this is the piece of it that is not done. |
| **62** | +17 | N | `bug-n-a-module-level-rebinding-still-loses-to-a-def-of-the-same-name` | A | Module-level `f = o.f` after `def f` still calls the def. Silent wrong dispatch; the local/param arm is already fixed and gated. |
| **62** | +17 | N | `bug-n-self-class-cannot-be-called-as-a-constructor` | A | self.__class__(args) does not compile — what CPython's own xml.sax AttributesImpl.copy does. Already carries a registered Track B workaround. |
| **62** | +22 | N | `feature-nilpy-enum-class` | A | `from enum import Enum` unsupported. Enum is in the first import block of most modern Python libraries. |
| **62** | +32 | N | `feature-nilpy-list-sort-inplace-key-reverse` | A | xs.sort(key=..., reverse=...) is a COMPILE ERROR; only the free sorted() takes them. In-place sort with a key is everywhere in real Python. |
| **62** | +27 | P | `bug-p-a-parameterless-function-is-undefined-as-a-method-call-argument` | A | A parameterless function as an argument to a METHOD call is undefined; to a free function it compiles. Blocked a real mimic module being written. |
| **60** | +25 | B | `bug-b-sysutils-string-gaps-found-by-differential` | A | Concat is not variadic, AnsiQuotedStr and SameStr do not exist, TryStr* leaves its value untouched on failure. Eighteen of twenty-two rows were byte-identical, so this is the measured remainder. |
| **60** | +20 | C | `bug-c-driver-misses-the-shared-runtime-finalisation-step` | A | ONE LINE. Every C program ships with no signal runtime and --no-signals is a no-op; every other frontend was moved over already. |
| **60** | +35 | C | `idea-c-realworld-test-targets` | B | The brainstorm list of real C programs — and real C programs are the best bug-finders we have (lua and sqlite each surfaced a dozen genuine bugs no synthetic test caught). Re-rank as the C real-world driver, not as an idea. |
| **60** | +15 | N | `bug-nilpy-a-keyword-call-through-a-statically-unknown-callee-does-not-compile` | A | a = mk(1); a(x=5) fails to COMPILE. The runtime dispatcher handles it; only the parse-time gate refuses. Ordinary callback-passing code. |
| **60** | +5 | N | `feature-a-declaration-phase` | B | All declarations before any body is typed. Root-cause fix for the NilPy ordering hazard that a field pre-pass currently patches around; several bugs collapse into it. |
| **60** | +15 | N | `feature-nilpy-process-exec-binding` | A | os.system / subprocess.Popen — needed by songformatter's Preview action. Runtime already spawns libc-free; this is only the binding. |
| **60** | +15 | N | `feature-nilpy-tkinter-surface-vs-a-real-application` | A | The tkinter facade has never been proven against a real app; songformatter's GUI is the forcing target and the harness now exists to measure it. |
| **60** | +25 | P | `bug-p-a-pointer-to-a-multidim-array-indexes-and-measures-the-flat-extent` | A | qg^[i,j] prints wrong numbers and Length(qg^) answers the flat extent. SILENT wrong values on ordinary pointer-to-array code; the metadata it needs is already present. |
| **60** | +25 | P | `compat-pascal-calling-convention-directives-uneven` | A | stdcall/safecall/pascal are a parse ERROR on a plain routine and fine on a method. Every FPC source that spells a convention on a routine is refused; this is the Windows/API-binding path. |
| **60** | +25 | P | `compat-pascal-inline-generic-specialization` | A | FPC's inline `specialize Max<Integer>(a,b)` is rejected; only the declaration form works. Generics-using real code writes the inline form. |
| **58** | +23 | A | `bug-a-nilpy-double-star-in-a-mixed-argument-list` | A | f(3, **d), f(**d, b=7), f(**d, **e) all fail. The mixed forms are the ones real code writes; the bare form was just fixed. |
| **58** | +18 | A | `feature-cdecl-bodied-sysv-prologue` | A | A BODIED cdecl proc still gets the internal convention, so a Pascal callback handed to C (GTK, sqlite, qsort) is unsound for float or >6 params. The overlap is now a loud error, which caps the damage but not the gap. |
| **58** | +28 | N | `feature-nilpy-small-syntax-gaps-found-by-the-2026-08-06-sweep` | A | Ten remaining rows including dict(x=1), .update(b=2), nested unpacking, bare tuple and a two-for comprehension. All loud, all ordinary Python that real code writes. |
| **58** | +33 | P | `compat-pascal-class-helpers` | A | DUPLICATE of feature-p-class-helper-for-a-class-type. Merge. `class helper for T` is standard modern FPC/Delphi and is a parse error here. |
| **58** | +23 | P | `feature-p-class-helper-for-a-class-type` | A | DUPLICATE of compat-pascal-class-helpers. `class helper for TC` refused while record and type helpers work — the third spelling of one concept, and the one modern FPC/Delphi code uses. |
| **58** | +28 | P | `feature-p-packrecords-c-directive` | A | {$packrecords c} is refused. It is what EVERY FPC header binding to a C library uses, and it blocks the arm profile of --mimic-fpc-compiler. |
| **58** | +23 | U | `decide-typeref-gains-a-pointer-depth-field` | B | Track U. Blocks the TypeRef migration mid-flight; four bugs in two days came from a table recording the pointee without the depth. (Prio owned by the Track U agent.) |
| **55** | +20 | A | `chore-a-the-range-checked-fpc-seed-cannot-be-built` | D | The ONE build that would name an array and index on an out-of-bounds write cannot be built, so the repo debugs out-of-bounds writes by guessing. Five constants. |
| **55** | +10 | A | `feature-dynamic-include-paths-config` | B | -I flags, config files, SDK scanner. Compiling a real third-party project means pointing at its real include tree; config-file slice already landed. |
| **55** | +20 | A | `refactor-a-two-predicates-answer-what-a-caret-yields` | B | Two functions type a dereference, neither contains the other, and swapping a call site trades one kind of knowledge for the other SILENTLY — which shipped a regression on 2026-08-25. |
| **55** | +10 | B | `bug-b-format-percent-u-prints-a-signed-value` | A | Format('%u',[q]) prints -1. Silent wrong value in ordinary formatting; sysutils is on every real Pascal program's path. |
| **55** | +10 | B | `bug-b-inttostr-of-a-qword-above-2-63-renders-negative` | A | DUPLICATE of bug-b-inttostr-of-a-qword-prints-it-signed. Same value prints two ways in one program; silent wrong. |
| **55** | +15 | B | `bug-b-inttostr-of-a-qword-prints-it-signed` | A | DUPLICATE of bug-b-inttostr-of-a-qword-above-2-63-renders-negative. IntToStr(High(QWord)) answers -1; WriteLn is right, so one value prints two ways. |
| **55** | +25 | B | `bug-b-the-fpc-vartype-constants-are-missing` | A | `VarType(v) = varInteger` does not compile — none of the varXxx constants are declared anywhere. Any FPC Variant code is refused at its first type test. |
| **55** | +25 | B | `compat-pascal-ioresult-returns-a-negative-errno` | A | IOResult returns -2 where FPC returns 2, so `if IOResult = 2` silently takes the wrong branch. Classic Pascal error handling, silently wrong. |
| **55** | +10 | C | `feature-c-gtk3-header-final-wiring` | B | Stock GTK3 headers through the C import path for the PCL GTK3 widgetset. Real target, but the GTK2 path already proved the mechanism. |
| **55** | +0 | N | `bug-n-a-uforth-corpus-timeout-is-reported-as-a-cpython-divergence` | D | A loaded box MANUFACTURES a NilPy frontend finding against uforth, our densest real Python corpus. Poisons the very signal this re-triage ranks on. |
| **55** | +35 | N | `bug-nilpy-except-tuple-binder-is-typed-by-the-first-arm-only` | A | `except (A, B) as e` reads B's object at A's field offsets. Harmless inside Python's own hierarchy and a SILENT WRONG VALUE the moment a tuple crosses hierarchies — which mimic modules declaring Pascal exceptions do. |
| **55** | +15 | N | `bug-n-inline-cast-deref-loses-a-pointer-fields-pointee` | A | Byte-identical copy of a just-fixed Pascal bug living in pyparser: the deref happens, the tag is wrong, the value is plausible and silently wrong. |
| **55** | +30 | N | `bug-n-super-as-an-expression-fails-with-a-misleading-diagnostic` | A | `return super().hi()` is refused with a diagnostic naming neither the construct nor the right line. super() in expression position is ubiquitous in real class hierarchies; the diagnostic is a second, separate cost. |
| **55** | +10 | N | `feature-nilpy-lambda-compiled-closure` | B | Lambdas are interpreted by pyeval; this is the wall songformatter's settings.py stops at, plus a real perf tier. |
| **55** | +10 | N | `feature-nilpy-no-type-inference-switch` | B | User-decided escape hatch: compile fully dynamically and pay the cost knowingly. Turns "does not compile" into "compiles slowly" for the whole ladder. |
| **55** | +30 | N | `feature-nilpy-str-format-named-keyword-fields` | A | "{name} is {age}".format(name=...) is `undefined variable`. Positional .format works; the named form is at least as common in real code. |
| **55** | +20 | P | `bug-p-a-typed-constant-of-pchar-type-is-a-parse-error` | A | `const KC: PChar = 'konst';` does not parse. The ordinary way to name a C string constant, and every C-interop Pascal header does it. |
| **55** | +20 | P | `bug-p-a-typed-string-constant-cannot-be-assigned` | A | Typed consts are writable for Integer, Char and ARRAY but not string — FPC's default in non-Delphi modes. Real ported code assigns them. |
| **55** | +20 | P | `bug-p-sizeof-rejects-a-pointer-deref-in-its-operand` | A | SizeOf(p^.A) is a parse error because the operand walk has no `^` case. Any record-over-pointer code (i.e. all C-interop Pascal) hits it. |
| **55** | +15 | P | `feature-p-assertions-directive-and-position` | A | {$ASSERTIONS OFF} is ACCEPTED AND IGNORED, so an Assert with a side effect runs here and not in FPC — two dialects take different paths with no diagnostic. |
| **55** | +20 | P | `feature-p-legacy-value-object-types` | A | Turbo/Object Pascal value `object` has never been supported; five fpc-testsuite generics tests fail on this alone. Gated by decide-old-style-object-types. |
| **55** | +20 | P | `feature-p-tmethod-record-for-method-pointers` | A | TMethod is undefined. It is the standard system record naming the two halves of a `procedure of object` — the documented way real event/callback code takes a method pointer apart. |
| **55** | +25 | P | `feature-p-uses-a-unit-in-an-explicit-file` | A | `uses mymod in 'mymod.pas'` is what every real .dpr/project source writes, so a corpus program is refused at its uses clause. Owner explicitly ranked it below the NilPy import work — hence 55, not 70. |
| **55** | +10 | P | `refactor-p-carve-out-paslexer-so-p-owns-its-lexer-too` | D | Deletes the A/P no-concurrent-edit slot entirely — the single coordination constraint that serialises two of the busiest lanes. 2,566 lines, and the parser half is already done. |
| **55** | +20 | P | `refactor-p-one-lvalue-path-for-statements-and-expressions` | B | The assignment TARGET is parsed by a second smaller copy of the lvalue walk; three bugs so far are exactly the omissions. The expression spelling works and the assignment spelling does not. |
| **55** | +20 | P | `refactor-p-three-hand-rolled-postfix-loops` | B | The ^ / .field / [i] chain is parsed by THREE hand-rolled loops plus a fourth in pyparser. They have already produced silent wrong values four separate times. |
| **55** | -10 | T | `bug-t-agents-kill-each-others-processes-with-pattern-pkill` | D | Pattern-pkill destroys sibling agents' runs; already solved once in gui_shot.sh and never generalised. Costs whole fuzz batches. |
| **55** | +30 | T | `bug-t-run-pascal-conformance-silently-fails-every-test-on-a-relative-compiler-path` | D | A relative $CC makes 51 of 107 tests report `compile error`, i.e. as COMPILER bugs, all at once. Poisons the entire Pascal conformance signal; the absolute path passes 61/0. |
| **55** | -5 | T | `bug-t-the-push-rate-starves-breadth-coverage-entirely` | D | Breadth coverage queued behind an unfinishable pin verify; re-measured and root-caused. Fixing it is what makes T's reports arrive at all. |
| **55** | +15 | T | `bug-t-twatch-status-says-down-while-the-daemon-is-alive-and-testing` | D | A false DOWN costs EVERY dev agent a ten-minute full gate per fix, by CLAUDE.md's own rule. The single largest throughput tax in the tooling list. |
| **55** | +0 | T | `chore-t-test-runs-inherit-the-desktop-session` | D | Every test job inherits DISPLAY/DBUS from the workstation session; already hung one job for three days. Class fix, not symptom fix. |
| **55** | +25 | U | `decide-old-style-object-types` | A | Track U. Gates feature-p-legacy-value-object-types; five fpc-testsuite generics tests fail on the answer. Answer it or the P corpus stalls behind it. (Prio owned by the Track U agent.) |
| **55** | +25 | U | `decide-vartype-returns-pxx-tags-not-fpc-codes` | A | Track U. Gates bug-b-the-fpc-vartype-constants-are-missing: the FPC idiom `VarType(v) = varInteger` does not compile until this is answered. (Prio owned by the Track U agent.) |
| **50** | +15 | A | `feature-nested-routine-fixed-array-capture` | A | A nested routine cannot capture a fixed-size array local — a hard compile error found while writing ordinary RTL code (DnsParseIpv6). |
| **50** | +5 | C | `refactor-c-string-literal-decay-belongs-at-the-producer` | B | The +8 literal decay is duplicated at three consumers keyed on a node kind; any wrapper node defeats all three at once, which is exactly how one silent-wrong-pointer bug happened. |
| **50** | +20 | N | `bug-n-kwargs-collector-alongside-named-params-needs-the-remainder` | A | def f(a=1, **kw) must give kw the UNCONSUMED keys. Needs a pylib helper, which needs a pin — coordinator-scheduled, not worker-startable. |
| **50** | +10 | N | `bug-n-str-of-a-pascal-declared-exception-ignores-str-when-caught-as-a-base` | A | str(e) dispatches by the STATIC except-clause type; the same object gives two different strings. Hits every mimic module that declares exceptions in Pascal. |
| **50** | +20 | P | `bug-p-length-of-a-pointer-to-a-dynamic-array-answers-one` | A | Length(pdy^) answers 1 and High(pdy^) answers 0 where FPC says 5 and 4, while pdy^[1] reads correctly. Silent wrong loop bounds. |
| **50** | +5 | T | `bug-t-a-one-ulp-move-turns-the-fleet-red-and-outranks-its-own-prio` | D | THE ranking inversion in mechanical form: float accuracy is low-prio by owner decree, yet a one-ulp move re-enters at the top through the red door. Directly on-theme. |
| **50** | +5 | T | `bug-t-regressions-are-blamed-on-commits-that-touch-no-code` | D | Nine open regressions blame docs-only commits. Either the blame step is landing on a no-op or the failures are flaky; either way A is pointed at the wrong place. |
| **50** | +25 | T | `feature-t-fpc-probe-needs-a-trunk-oracle` | D | Every FPC-parity finding is measured against 2021 FPC 3.2.2, and that has TWICE produced a false "pxx diverges". Our entire compat ranking rests on this oracle being right. |
| **50** | -5 | T | `feature-t-tier-job-self-compile-differential-across-o-levels` | D | A -O0-only self-compile failure passed the entire gate once. Optimizer differential coverage as Track O ramps; user-decided. |
| **50** | +25 | U | `decide-assertion-default-vs-fpc` | B | Track U. Gates feature-p-assertions-directive-and-position, where {$ASSERTIONS OFF} is currently accepted and ignored. (Prio owned by the Track U agent.) |
| **48** | -7 | O | `feature-opt-heap-per-thread-cache` | B | Parallel alloc is 3x SLOWER than serial. Real for any threaded app, measured by a real demo; no named corpus blocked. |
| **48** | +18 | P | `bug-a-low-high-of-a-char-indexed-array-answer-the-ordinal` | A | `for c := Low(a) to High(a)` over a char-indexed array does not compile against a Char loop variable. Classic Pascal, and the missing fact (the index type) is simply not recorded. |
| **48** | +18 | P | `feature-p-const-evaluator-carries-unsigned-64-bit` | A | High(QWord), Low(UInt64), High(NativeUInt), High(PtrUInt) all rejected — the const evaluator carries Int64. Idiomatic FPC code that names a machine-word bound does not compile. |
| **48** | +8 | P | `feature-p-nested-record-field-in-a-typed-record-constant` | B | A record-typed FIELD in a typed record constant is "not a constant"; array-valued fields already work. Loud, and ordinary declaration code. |
| **45** | +15 | A | `feature-a-a-variant-has-no-null-tag` | A | One no-value tag, so VarIsNull and VarIsEmpty are the same question and disagree with FPC. variants.pas states the approximation and asks for this ticket. |
| **45** | +15 | A | `feature-a-dynamic-array-of-frozen-strings` | B | `array of string` is refused from SetLength up in the frozen-string model — which is the SELF-HOST build, so it constrains the compiler's own source. |
| **45** | +10 | A | `feature-a-getinterface-refcounting` | B | Every Supports/GetInterface hit is one release the object never got a retain for. Nothing observed to crash yet, but the asymmetry is real. |
| **45** | +5 | A | `refactor-a-one-program-driver-prologue-for-every-frontend` | B | Five drivers open-code one prologue and drift toward whatever Pascal gained last; the BASIC driver has been caught missing four steps one at a time. |
| **45** | +5 | A+O | `feature-a-reentrant-heap-lock-and-per-thread-arenas` | B | The allocator does not scale because the lock is global; TLS landed 2026-08-20 so it is now possible. Judged as allocator work, no target blocked. |
| **45** | +5 | B | `bug-b-varisstr-is-false-for-a-one-character-string` | A | VarIsStr('x') is False. Two mechanisms for one concept in the same unit, disagreeing — the sibling three lines below is already correct. |
| **45** | +35 | B | `feature-crtl-implement-libc-assumptions` | B | The standing collector for the libc assumptions real C leans on, driven by what real corpora actually touch. It is the C-side companion to the corpus ladder, not a completeness chase. |
| **45** | +0 | D | `docs-d-name-resolution-pages-state-the-import-rule-with-no-cpyext-carve-out` | D | Two public pages are now wrong in the direction that makes a WORKING program look unsupported. Cheap, and public-facing. |
| **45** | +15 | N | `bug-n-typeinfo-reads-the-wrong-token-and-switches-on-kind` | B | Reads one token PAST the type name and resolves by token KIND, so TypeInfo(byte) answers Integer. Silent wrong; the Pascal-side twin is already fixed. |
| **45** | +0 | N | `feature-n-from-accepts-a-quoted-foreign-file` | B | Implements a user-answered decision; parser-only, semantics already exist. Cheap, and it is the cross-language import story. |
| **45** | +5 | N | `feature-nilpy-hasattr-per-instance-assigned-tracking` | B | hasattr True for a field the instance never assigned. Implements a resolved decision; the loud half is done. |
| **45** | +10 | N | `feature-nilpy-methods-on-int-and-float` | B | x.bit_length(), y.is_integer(), (1.5).hex() — no methods on numeric values at all. One gap, several idioms. |
| **45** | +10 | N | `feature-nilpy-multi-arg-callback-bridges` | B | Only two call bridges exist, so a callable cannot receive more than one own argument. The tkinter/callback path needs it. |
| **45** | +15 | N | `feature-nilpy-threadsafe-containers` | B | TPyList/TPyDict corrupt under concurrent mutation: append is a read-modify-write over a buffer that can realloc. Use-after-free, and free-threaded CPython guarantees it cannot happen. |
| **45** | +15 | N | `refactor-n-two-import-handlers-are-twins` | B | Two handlers for one concept, which is WHY a relative import fails with two different errors depending on which it reaches. Imports are the ladder's wall, so this has real reach. |
| **45** | -25 | N | `regression-lib-test-lib-mimic-xml-etree-elementtree-2` | B | Auto-filed stub, 137-commit bisect range, job builds only with PXX_STABLE so the named sha cannot be the cause. Re-verify at HEAD before ranking it as a red. |
| **45** | +10 | O | `feature-opt-inline-float-and-record-returning-leaves` | B | The inliner rejects any function returning a float or record; hand-inlining a sin kernel was BIT-IDENTICAL and 3.8x faster. ~74% call overhead on that path. |
| **45** | +15 | P | `compat-pascal-supports-three-arg-out-form` | B | Supports(obj, IFoo, out Ref) — the form that tests AND retrieves in one step — is a parse error. Common in real interface code. |
| **45** | +20 | P | `compat-pascal-uses-sysutils-withdraws-the-variadic-concat` | A | `uses sysutils` silently withdraws the variadic Concat, because ANY user Concat disables the intrinsic outright. Loud, but the combination is extremely common. |
| **45** | +0 | P | `feature-embed-pascal-script` | C | Same survey, same "Not now". Better first candidate than DWScript (pure Object Pascal, FPC-supported upstream) but still behind the OOP ladder. |
| **45** | +5 | P | `feature-p-defineglobal-a-define-that-crosses-unit-boundaries` | B | {$CLAIM}, the user-decided spelling. Unblocked, designed, and the shape that dissolves the pylib/sysutils Exception collision. |
| **45** | +10 | P | `feature-p-record-const-with-an-array-of-record-field` | B | A record constant whose field is an array of records is "not a constant". Loud; ordinary table-declaration code. |
| **45** | +15 | P | `refactor-p-the-field-declaration-parser-exists-twice` | B | Every field-level feature must be written twice, and the second copy is the one that stays broken — the enum-identity work needed the same six edits in both. |
| **45** | -5 | T | `bug-t-track-ts-own-pushes-destroy-track-ts-own-breadth-coverage` | D | T's own tooling pushes abort in-flight breadth runs and discard 100%. Structural, and it is why full-tier verdicts are rare. |
| **45** | +0 | T | `bug-t-two-devtests-measure-the-box-and-flake-the-fleet-job` | D | A timing guard flakes under load and, because the job stops at the first failure, hides 50 other guards behind it. |
| **45** | -10 | T | `chore-t-split-lib-test-into-jobs-that-name-what-failed` | D | One lib-test job bundles several sources so a tk timeout reads as a C-math regression. Report quality; real but not blocking. |
| **45** | +0 | T | `feature-t-fail-when-a-test-file-is-wired-into-no-build-rule` | D | Two confirmed tests that existed, passed, and were gated by nothing — one for two weeks. Converts "someone notices" into "CI notices". |
| **45** | +25 | T | `feature-t-nilpy-cpython-differential-fuzzer` | D | NilPy is the ONLY mainline frontend with no fuzz oracle, and it is the lane where the live real-world corpus work is. pasmith and csmith both drew real silent bugs. |
| **45** | +15 | U | `decide-pointer-difference-unit` | B | Track U. FPC answers BYTES for an untyped operand and pxx always answers elements — a silent difference in ported code. (Prio owned by the Track U agent.) |
| **40** | +5 | A | `bug-a-a-dynarray-delete-temp-holds-the-new-buffer-until-scope-exit` | B | Correct refcounts, wrong destruction TIME. Visible to any destructor with a side effect, and fpc-testsuite tarray11 checks it. |
| **40** | +10 | A | `feature-a-emit-obj-record-class-abi-mode` | B | Two .o files built with different --compact-classes settings link and call the WRONG METHOD with no diagnostic. Narrow reach, exactly the failure class the debugging note is about. |
| **40** | +5 | A | `feature-a-io-lock-owner-from-tls-not-gettid` | B | One gettid SYSCALL per I/O statement under --threadsafe; 43% overhead, and caching it in TLS removed the whole penalty. The naive version is unsound, so it needs the recorded design. |
| **40** | -5 | A | `feature-writeln-as-library` | B | write/writeln special-cased in codegen and not FPC-compatible. array of const is now stable so the rewrite is possible; no named target waits. |
| **40** | +15 | A | `task-a-add-fu-to-the-compiler-usage-line` | D | ONE LINE. -FuDIR is the flag that makes a third-party Python package resolvable and it is missing from the compiler's own usage output — i.e. undiscoverable at the exact moment a user needs it. |
| **40** | +0 | B | `feature-b-fpc-signal-compat-unit` | B | FPC's Signal/fpSignal surface on top of the shipped __pxxSigNum. RTL unit only, compiler half done. |
| **40** | +5 | B | `feature-b-random-tier1-consume-the-hw-entropy-intrinsics` | B | The compiler half landed; random.pas runs one tier below its design. A few lines, no uses clause needed. |
| **40** | +20 | B | `feature-networking` | B | A target-neutral net.pas with Synapse as compat target and test suite. Synapse already compiles and is wired into lib-test, so the compiler-facing value is largely banked. |
| **40** | -25 | C | `feature-c-csmith-differential-fuzzing` | D | Standing campaign, synthetic oracle. Real yield, but it is exactly the edge-case generator; C already has 8 wired real corpora that find more. |
| **40** | +10 | C | `feature-c-diagnostics-name-the-module-they-are-in` | B | The Pascal side prints `in: <path>`; the C side has the same data and prints nothing, so an error inside a crtl module reports a bare line number. Real cost when compiling real C. |
| **40** | +15 | C | `refactor-c-the-partial-index-sentinel-should-not-be-a-type-tag` | B | A type tag used as a flag, colliding with the honest tag of a `long long` array — and that collision already cost a real silent-wrong-stride bug. |
| **40** | +0 | N | `bug-n-tk-got-files-are-invisible-to-testmgr-privatization` | D | Three .got files never privatized, so two concurrent runs share them. Found by T's own new lint in a recipe believed fixed. |
| **40** | +5 | N | `feature-nilpy-map-over-several-iterables` | B | map(f, xs, ys) is a parse error; the whole callback path below it is one-argument by construction. Real but not common. |
| **40** | +15 | N | `feature-nilpy-str-surface-gaps-2026-08-09` | B | Str/bytes methods missing, every one a LOUD compile error naming the method. The one silent finding from the same sweep was correctly split out and fixed. |
| **40** | +10 | N | `perf-nilpy-remaining-perbyte-string-builders` | B | O(n^2) per-byte concat remains in pystr_join, PyReprQuote, the strip family and f-string helpers. The dominant sites were already fixed; this is the measured remainder. |
| **40** | +5 | N | `refactor-nilpy-three-places-decide-a-locals-class-identity` | B | Three sites decide a NilPy local's class identity. Root-cause cleanup behind a fixed bug; the class of defect it prevents is silent-wrong-type. |
| **40** | -5 | O | `feature-inline-nonleaf-and-branch-locals` | B | Deferred inliner slices. Landed slices are green at -O2; measured wins exist but no target waits. |
| **40** | -5 | O | `feature-opt-dynarray-grows-in-place` | B | A growing dynarray leaves its whole geometric series as garbage; self-compile RSS +10%. Real, measured, nothing blocked. |
| **40** | +10 | P | `bug-p-a-variant-refuses-wide-chars-and-interfaces` | B | WideChar, UCS4Char and any interface cannot go into a Variant, while Char/ShortString/Single/Currency can. A hole in one enumeration, not a design position. |
| **40** | -5 | P | `feature-embed-dwscript-rtti` | C | Named in the corpus survey as explicitly "Not now" — too many simultaneous walls for a clean bisect. Real target, wrong time. |
| **40** | -5 | T | `bug-t-a-cascade-ticket-concludes-harness-event-with-no-evidence` | D | Auto-filed tickets assert a cause from the absence of one narrow signal. Report quality; misdirects triage. |
| **40** | -5 | T | `bug-t-a-pin-verifys-reds-carry-no-reasons` | D | The 11 reds a reader must triage are exactly the 11 with no reason recorded. Report quality. |
| **40** | -10 | U | `decide-release-signing-key-custody` | D | Track U. Gates release signing; releases are not the stated near-term goal. (Prio being set by the Track U agent.) |
| **35** | +0 | A | `bug-a-real-is-single-on-hosted-riscv32` | B | Real is 4 bytes on hosted riscv32 because the type keys on ARCH not on the ESP profile. Silently halves precision, but on a non-target host. |
| **35** | +0 | A | `bug-a-the-specialization-splice-does-not-adjust-the-body-pass-spans` | B | The splice calls one of the two adjusters InsertTokens calls. Either Pass2Active is always false there or the spans drift — currently nobody knows which. |
| **35** | -5 | A | `feature-c-package-namespace-decision` | B | `uses zlib` collides between a Pascal wrapper and a direct C package. Needs the owner's call; small once answered. |
| **35** | +5 | A | `refactor-a-the-const-cast-width-table-is-the-third-copy` | B | A third copy of the builtin type-name table, carrying the same longint/nativeint disagreements the other two just settled. It is the COUNT that is the problem. |
| **35** | -5 | D | `docs-d-document-exec-eval-and-the-builtins-incompatibility` | D | Public docs say eval/exec do not exist; the explicit-dict form has worked since 2026-07-31. Wrong in the direction that hides a working feature. |
| **35** | +5 | D | `docs-toolchain-cli-flags` | D | Seven shipped information flags plus PXX_HOME/PXX_LIBPATH/pxx.cfg, all verified by test rows, none documented. First thing a new user types. |
| **35** | +10 | E | `feature-demo-ide-jump-into-includes-and-units` | B | The IDE drops the new `in: <path>` line, so jump-to-error lands on the wrong file. Small, real, and it is our own dogfood app. |
| **35** | -20 | E | `feature-demo-portable-userland` | C | Umbrella/demo arc, no dated target. Aspirational showcase; nothing waits on it. |
| **35** | -5 | N | `bug-nilpy-a-generator-instance-leaks-its-locals-and-argument-cells` | B | A deliberate, recorded trade behind the stackless-generator fix. A leak, not a wrong value; documented so it is not rediscovered as a mystery. |
| **35** | +15 | N | `bug-nilpy-augmented-repeat-on-a-variant-target-still-rebinds` | B | A dict VALUE as a *= target still rebinds, so an alias keeps the old contents. Silent; the parameter half already landed and += has the same split. |
| **35** | +5 | N | `bug-nilpy-del-on-a-plain-variable-silently-does-nothing` | B | `del x` on a bare name is accepted and does nothing. Silent, but the container forms real code uses are correct. |
| **35** | +5 | N | `feature-nilpy-walrus-operator` | B | `:=` is not parsed. Modern and increasingly common, but every use has a two-line rewrite and no target corpus requires it. |
| **35** | -35 | N | `regression-test-nilpy-test-nilpy-callable-to-str-param-fails` | C | A *_fail refusal test; a feature landing turns its own refusal test red. 132-commit range. Verify it is not simply obsolete. |
| **35** | -23 | O | `feature-opt-o3-register-pressure` | B | -O3 umbrella; landed slices are pinned, the rest is soak + a promotion gate needing the full matrix. No target waits on it. |
| **35** | -5 | P | `feature-pascal-management-operators-nested-and-array` | C | Initialize/Finalize do not reach an array element or nested field. Advanced-records corner; refused loudly rather than silently. |
| **35** | -10 | T | `chore-t-test-binaries-hardcode-unsweepable-tmp-paths` | D | 60 hardcoded /tmp paths in 37 compiled test sources; two concurrent runs share them even under testmgr. Real but slow-burn. |
| **35** | -5 | T | `feature-twatch-full-tier-coverage-age` | D | No signal separates "full tier lagging" from "full tier never completes". Observability behind the starvation bug above. |
| **35** | -5 | U | `decide-pchar-node-side-storage-or-a-pchar-type-kind` | B | Track U. Its premise expired twice and the do-nothing option is now live (198/198 rows match fpc through one walk). Design tidiness, not a blocker. (Prio owned by the Track U agent.) |
| **32** | -8 | O | `feature-opt-rtti-emit-on-use` | B | RTTI emitted for every class whether used or not. Size, not correctness; matters on ESP, which is off the critical path. |
| **30** | +5 | A | `chore-a-delete-the-dead-pascal-lvalue-statement-path` | D | ~130 lines with no callers anywhere, including direct machine-code emission. Deleting it removes a place future readers can be misled by. |
| **30** | +0 | A | `chore-a-re-include-bench-timing-in-tools-devtest` | D | Delete one `case` line to re-arm a guard that has been fixed and is green under load 14. That is the whole ticket. |
| **30** | +0 | A | `feature-a-finalize-for-bare-dynarray-and-variant` | B | The Variant half landed; a bare dyn-array lvalue still gets a clear compile error and `a := nil` is the one-line workaround. Narrow. |
| **30** | -5 | A | `feature-a-unreferenced-class-rtti-keeps-every-method-alive` | B | Every VMT slot is a DCE root, so an unused class keeps every method. Size, not correctness. |
| **30** | -20 | A | `feature-nilpy-collections-and-string-methods` | C | Filed 2026-07-10; most of the listed surface has since landed. Likely stale — re-scope or close before ranking. |
| **30** | -15 | A | `feature-toolchain-cli-ux` | C | Steps 1-3 landed; step 4 (--selfcheck) waits on release packaging. Remaining scope is install/distribution UX, not compiling real programs. |
| **30** | -10 | D | `docs-d-nilchecks-directive-and-flag` | D | Two shipped directives absent from the reference. Cheap; the tri-state subtlety is worth one sentence. |
| **30** | -10 | E | `feature-demo-nilpy-ide` | C | Landmark demo, blocked on the tk surface and NilPy loop control. Showcase, not a target. |
| **30** | +0 | N | `bug-nilpy-an-extended-slice-cannot-be-assigned` | B | l[::2] = [7,8] is a parse error; the read form and the plain-slice assign both work. Both halves it needs already exist. |
| **30** | +5 | N | `feature-nilpy-a-genexpr-is-lazy-not-materialised` | B | Elements are built eagerly then walked. Consumption is now correct; what remains is infinite generators and construction-time side effects. |
| **30** | -10 | N | `feature-nilpy-cpyext-cycle-collector` | C | Cycles leak in the cpyext object model. Costs nothing observable until a cdef class allocates in a loop; no wired target reaches it. |
| **30** | +0 | N | `feature-nilpy-fstring-nested-spec-and-nested-fstring` | B | Two of twenty-four f-string forms. Dynamic width f"{n:{w}d}" and a nested f-string; the other 22 match CPython exactly. |
| **30** | +5 | N | `feature-nilpy-math-module-twelve-absent-names-measured` | B | 39 of 51 math names agree exactly. Four absent ones (isqrt, isfinite, ldexp, frexp) are exact operations and can land today; the other eight inherit the low-prio float policy. |
| **30** | -5 | P | `bug-p-high-and-low-refuse-every-non-identifier-operand` | C | High('abc'), High('ab'+s), High(('ab')). fpc gives each a different base, so it needs its own measured table. Corner of an intrinsic. |
| **30** | -15 | P | `feature-pascal-corpus-passrc` | C | Self-declared ENDGAME, do LAST: 60k LOC over a 200-class hierarchy would hit a dozen unrelated walls at once with no clean bisect signal. |
| **30** | -5 | P | `feature-pascal-management-operators-copy-and-addref` | C | Copy/AddRef parse, check arity, register — and are never dispatched, because there is no copy lifetime event. Advanced-records corner. |
| **30** | +0 | S | `bug-b-crtl-esp-close-cannot-dispatch-socket-vs-file` | B | On ESP-IDF one close() serves both files and sockets, so socket close is wrong there. Real defect, ESP-only. |
| **30** | -23 | S | `feature-esp-peripheral-callback-api` | C | ESP peripheral API. No named real-world target; the ESP campaign is a side axis to a pragmatic C+Pascal+Python compiler. |
| **30** | +0 | T | `bug-t-fpc-seed-canary-red-cited-lines-that-cannot-contain-the-identifier` | D | One unreproducible false RED that cost an agent a full investigation. Evidence points at a stale tree read; low frequency. |
| **30** | -5 | T | `feature-t-pasmith-rung-selftest` | D | A fuzz rung that has only ever been silent is indistinguishable from one that does not work. Real methodological point, low urgency. |
| **30** | -10 | T | `meta-t-dev-throughput-and-track-a-t-integration` | D | Umbrella holding the wait-limited-not-token-limited thesis. Closed when its linked tickets are; rate those. |
| **30** | -5 | U | `decide-classinfo-returns-our-blob-or-nothing` | C | Track U; DUPLICATE of decide-tobject-classinfo-blob-or-refusal. Merge them. (Prio owned by the Track U agent.) |
| **30** | +5 | U | `decide-should-a-null-variant-raise-like-fpc` | C | Track U. Requires a second tag or making both Null and Unassigned die; the uncontested half already landed. (Prio owned by the Track U agent.) |
| **30** | -12 | U | `decide-tobject-classinfo-blob-or-refusal` | C | Track U; DUPLICATE of decide-classinfo-returns-our-blob-or-nothing. Last PXX-REJECT member of TObject; no corpus reads it. (Prio owned by the Track U agent.) |
| **25** | +5 | A | `bug-a-a-riscv32-diagnostic-names-the-wrong-target` | D | The user types riscv32 and the message says esp32. One hard-coded name in a shared arm; misleading diagnostics cost real debugging time. |
| **25** | +10 | A | `bug-a-numeric-goto-labels-are-not-supported` | B | Standard Pascal spells a label as a digit sequence and FPC takes both. Old real code uses it; small. |
| **25** | -5 | A | `bug-a-riscv32-codegen-has-no-variant-support` | B | `v := 1` does not compile for riscv32. Loud, and it exposes that riscv32 Variant claims elsewhere describe an unreachable path — but riscv32 is not a product target. |
| **25** | +0 | A | `chore-progress-flag-prose-only-track-decl` | D | Two conventions for declaring a track let the Windows-vs-website W collision hide for months. Board hygiene with a proven failure behind it. |
| **25** | -10 | A | `feature-nilpy-arc-cross-parity` | C | Object-ARC leaks on aarch64/arm32/etc. Leak-only, retains and releases stay paired; x86-64 is complete and is where the corpora run. |
| **25** | -5 | A | `perf-c-parse-codegen-large-file-superlinear` | B | sqlite3.c takes 32s where a linear extrapolation predicts 20s. Informational, no test failing; a real-corpus compile-time tax though. |
| **25** | -10 | A | `refactor-a-backend-machine-code-lives-in-six-shared-files` | C | Six shared files emit per-arch machine code, including the C frontend writing raw rv32/a64 entry stubs. Real layering smell; costs nothing until a backend is omitted. |
| **25** | -5 | A+S | `bug-a-the-div-by-zero-check-is-still-missing-on-xtensa` | C | The sixth target, and a genuinely different job (8-bit displacements, windowed ABI, two divide shapes, cannot be run on this box). ESP axis. |
| **25** | -5 | D | `idea-public-status-page` | D | Wire the hand-written status page to the already-generated tstate reports so public numbers stop rotting. The data pipeline exists. |
| **25** | +0 | N | `bug-nilpy-classmethod-constructors-on-builtin-types-are-absent` | C | bytes.fromhex / float.fromhex. The dotted-table mechanism exists and these two names are simply not in it — cheap, but rare. |
| **25** | -10 | N | `feature-nilpy-ascii-flag-fast-path` | C | An O(1) isascii fast path — with a stated risk that a false positive is a SILENT wrong answer on exactly the strings the surface exists for. Measure-first, low reward. |
| **25** | -5 | N | `feature-nilpy-hoist-constant-container-literals-out-of-a-loop-condition` | B | `while x in ("a","b")` rebuilds the tuple every test. Perf, and the motivating instance of normalise-dont-special-case. |
| **25** | -5 | N | `feature-nilpy-match-statement` | C | Structural pattern matching, 3.10+. Absent from every corpus we target, all of which support older Pythons. |
| **25** | -5 | O | `feature-opt-arch-level-and-dispatch` | B | Decided: compile to x86-64-v2, dispatch above it. The gate box has no FMA, so nothing forces this now. |
| **25** | -15 | P | `compat-pascal-a-string-n-field-makes-a-record-a-different-size-than-fpc` | C | A record with a string[10] is 24 bytes where FPC says 11. Values all correct — a layout divergence that matters only for binary interop. |
| **25** | +0 | P | `compat-pascal-string-n-is-not-a-shortstring` | C | string[20] is a handle with a cap, not a shortstring: SizeOf 8 vs 21 and ss[0] is not the length byte. Matters only for binary layout and `file of record`. |
| **25** | -20 | S | `feature-esp-hardware-flash-validation` | C | Requires physical hardware on USB; un-automatable in-harness. Cannot be queued to an agent at all. |
| **25** | -5 | T | `chore-t-unit-class-est-mem-is-below-what-lib-test-00-actually-peaks-at` | D | testmgr's own advisory: the scheduler admitted a job on a promise the box could not keep. One table row. |
| **25** | -10 | T | `feature-t-uforth-bench-on-the-watcher-idle-phase` | D | Automates uforth bench rows per-sha and would give the quiet-box baseline the harness never had. Bench, not correctness. |
| **25** | -5 | U | `decide-variant-bitwise-width` | C | Track U. Three defensible readings of a negative operand's shift; they agree on every non-negative one. (Prio owned by the Track U agent.) |
| **25** | -20 | W | `feature-web-track-w-bootstrap` | D | Website lane bootstrap. Off the compiler critical path; wants a dedicated creative session, not queue time. |
| **22** | -18 | A | `refactor-a-seven-frontends-borrow-rust-parser-helpers` | C | Costs nothing today. Makes R and Z individually unomittable; a build-configuration nicety, and RWiden sharing SEMANTICS is the only real smell. |
| **22** | +7 | C | `compat-c-printf-p-of-null-prints-0x0-not-nil` | D | Neither spelling is wrong (musl prints 0x0 too) — but the gcc oracle IS glibc, so this manufactures a divergence in every C differential run that prints a null pointer. Rank it as oracle hygiene. |
| **22** | -3 | P | `compat-pascal-set-storage-size-is-always-32-bytes` | C | Every set is 32 bytes whatever its range. Values, membership, operators and case all agree exactly with FPC — only the SIZE differs. |
| **22** | -8 | P | `compat-pascal-subrange-storage-size` | C | Every subrange is 4 bytes. Values all correct; a layout divergence costing 4x memory and binary interop. |
| **20** | -20 | A | `bug-a-nilpy-leading-double-star-in-a-call-is-not-detected` | D | Its own sibling ticket records this as FIXED in a057789bc. Verify and close rather than rank. |
| **20** | +0 | A | `chore-a-sweep-the-unwired-tests-into-the-suite` | D | PAUSED with 15 files left, all in lanes the owner has DEFERRED. Nothing is half-applied; resume when a lane is un-deferred. |
| **20** | -15 | A | `feature-a-why-threadsafe-needs-45pct-more-global-fixups` | C | An open question left behind after the cap was raised. Nothing is blocked; pure curiosity with a plausible benign explanation. |
| **20** | +0 | A | `feature-cli-widgetset-flag` | D | --widgetset=<name> as sugar for a define. Pure convenience; the define already works and the library half needed no compiler change. |
| **20** | -25 | A | `feature-cross-frontend-interop-contract` | C | Explicitly scoping-only, self-declared unranked, no code. Not dispatchable work. |
| **20** | -25 | A | `feature-nilpy-idf-import` | C | North-star integration milestone (NilPy including arbitrary ESP-IDF headers). Aspirational; ESP is off the pragmatic-compiler critical path. |
| **20** | -25 | A | `meta-constant-normalisation` | D | Standing governance index, never "done". Rate the linked tickets, not the charter — ranking a never-completable item is how one topped `next` before. |
| **20** | +5 | B | `feature-b-a-real-minidom-is-an-implementation-not-a-shim` | C | ~25 DOM methods, weakref.proxy and a reach into minidom's PRIVATE members — a DOM implementation project that unblocks EXACTLY ONE corpus file. |
| **20** | -15 | D | `task-d-document-the-strict-overload-width-flag` | D | One table row each in three files for a shipped flag. Cheap, low reach. |
| **20** | -10 | D | `task-d-document-warn-ignored-directives` | D | One CLI row plus a pointer from the directive table. Cheap, low reach. |
| **20** | -5 | M | `feature-t-windows-wine-harness` | C | Wine test bed ahead of the PE writer. Windows is a whole campaign that no named real-world target needs yet. |
| **20** | -15 | N | `bug-n-exec-ignores-a-caller-supplied-builtins-mapping` | C | The restricted-exec idiom. A real upward-compat defect, but no corpus program restricts exec. |
| **20** | -15 | N | `bug-n-name-on-a-builtin-type-is-unimplemented` | C | str.__name__ raises. User classes answer correctly; clean Python-shaped error, not a crash. |
| **20** | +12 | N | `feature-n-nilpy-ast-typing-module-scope` | B | Module scope still uses the token scanner, so the inference drift the AST typing was built to kill survives at module level. A trial parse there needs the recoverable-Error work first. |
| **20** | +0 | P | `feature-p-sizeof-of-a-literal` | B | SizeOf(1), SizeOf('abc'). Left out DELIBERATELY because fpc types a literal by its VALUE; routing them through the expression path would answer a wrong size silently. |
| **20** | -20 | S | `feature-a-promoint-variant-esp-targets` | C | Promotable-int Variant interop on riscv32/xtensa. ESP axis, and the riscv32 half is a pre-existing Writeln-of-Variant gap that is not this ticket's. |
| **20** | -15 | S | `feature-dns-esp-backend` | C | DNS on ESP via lwIP. Re-scoped and correct in design; ESP axis, off the critical path. |
| **20** | -10 | S | `feature-pal-esp-posix-fd-semantics` | C | Exact POSIX fd semantics over ESP-IDF VFS. The newlib-stdio backend already gives real file contents; ESP axis. |
| **20** | -10 | T | `chore-t-lint-a-job-that-runs-a-binary-it-does-not-compile` | D | Prototyped and deliberately not shipped — 5-7 candidates each needing adjudication. Shipping it half-tuned makes the guard that gets muted. |
| **20** | -35 | T | `feature-t-freebsd-image-and-runner` | D | FreeBSD is not a named product target. Installing qemu to unblock a port nobody has asked for; the queue's clearest misrank upward. |
| **20** | -5 | T | `feature-t-record-host-cpu-features-in-tstate` | D | Record CPU model and feature level per host, once. An ISA question needed an ssh to answer; small. |
| **18** | -7 | A | `refactor-a-search-path-helpers-live-in-the-c-preprocessor` | C | Generic -Fu/-I search-path helpers live in cpreproc.inc, so the compiler's own CLI depends on the C frontend. Misplacement, costs nothing today. |
| **18** | -12 | A | `refactor-a-the-greenfield-frontends-share-each-others-parser-helpers` | C | Four esoteric frontends call Rust's parser support functions. Costs nothing today; couples two language specs, which the substrate note forbids. |
| **18** | -17 | S | `feature-c-esp-conformance-coverage` | C | C conformance on bare ESP. Needs its own UART-capture harness; the desktop cross matrix already landed and is what real C targets run on. |
| **15** | -5 | A | `chore-a-retire-the-dead-pyexec-stub-and-its-stale-comments` | D | A dead stub plus comments claiming a done, gated feature SEGFAULTs. The stale prose already made a reader doubt working code; a rider for the next builtin pin. |
| **15** | -10 | A | `feature-n-a-quoted-from-import-reaches-another-language` | C | Self-declared: "Nothing needs it today", and the refusal points at the working spelling. Filed to be visible, not urgent. |
| **15** | +5 | A | `idea-cross-namespace-ambiguity-warning` | B | The case-insensitive C/Pascal namespace once silently broke call binding; the crtl fix removed the known collisions but the failure mode stays SILENT for the next one. |
| **15** | -25 | D | `task-d-document-own-language-first-in-the-language-reference` | D | Explicitly blocked until the symbol rule is built. Documenting behaviour the compiler does not have is worse than documenting nothing. |
| **15** | -5 | P | `feature-p-tobject-api-classparent-instancesize-tostring` | C | Five of six landed; only ClassInfo remains and it is a Track U question, not an implementation choice. Effectively already done. |
| **15** | +3 | P | `task-pascal-conformance-long-tail` | C | Catch-all for the FPC-conformance audit's small clusters, after the four big ones got their own tickets. Conformance burn-down is explicitly rainy-day. |
| **15** | -10 | T | `bug-t-twatch-web-lists-a-target-that-cannot-be-built` | D | The dashboard carries a structurally empty riscv64 column that reads as "no news" rather than "impossible". Cosmetic. |
| **15** | -10 | T | `feature-t-uforth-bench-restore-the-elfhash-outlier` | D | The tracked ~100x-slow outlier SKIPs, so the harness has no visibility on its worst case. Bench only. |
| **15** | -10 | W | `feature-promo-launch-plan` | D | Outreach. The loud moment is USER-TRIGGERED ONLY and one-shot; the low prio is the guard. |
| **12** | -13 | A | `bug-a-riscv32-sa-onstack-has-no-effect-under-qemu` | C | Points at qemu-user rather than at us, and is unverifiable without hardware. The other three targets took the identical fix. |
| **12** | -3 | A | `compat-pascal-overload-prefers-signed-for-an-unsigned-argument` | C | A Cardinal argument goes to Int64 where FPC sends it to QWord. Both arms must be visible for it to matter; loud in effect. |
| **12** | -8 | A | `feature-a-audit-strict-flags-against-dialectispxx` | C | Audit six strict flags for a dialect-ownership carve-out. Housekeeping on a strict-mode family that is itself low prio by charter. |
| **12** | -8 | A | `feature-a-typeinfo-integer-name-under-strict-fpc` | C | Report LongInt instead of Integer under strict-FPC. The underlying type already matches; this is a STRING, and cosmetic RTTI parity at that. |
| **12** | -3 | B | `feature-lib-mimic-string-template` | C | string.Template is what logging uses — and `import logging` does not resolve at all today, so nothing can reach Template. Blocked behind a shim that does not exist. |
| **12** | -23 | N | `bug-n-abs-of-a-complex-raises-typeerror` | C | abs() of a complex. Complex numbers are the definition of an edge case here; type/.real/.imag/round all already match. |
| **12** | -3 | N | `bug-nilpy-delattr-globals-and-locals-are-absent` | C | delattr is a real gap; globals()/locals() want a runtime name table this dialect deliberately does not build and may be a documented divergence. |
| **12** | -8 | N | `bug-nilpy-four-remaining-absent-builtins` | C | slice, dir, vars, memoryview. Self-declared: "None has appeared in any corpus scan." |
| **12** | -23 | U | `decide-how-much-string-machinery-the-basic-frontend-gets` | C | Track U. The BASIC frontend is an esoteric probe, not a product frontend. (Prio owned by the Track U agent.) |
| **10** | -5 | A | `feature-a-shrink-managed-header-on-32-bit` | C | Self-de-ranked 25->15 on 2026-08-19 because its deadline passed and was MET. An optional ESP memory win with nothing behind it. |
| **10** | +5 | N | `feature-nilpy-parallel-for-in` | C | Blocked on a semantics decision; the runtime substrate is complete and frontend-agnostic. Nothing in any target corpus is parallel. |
| **10** | -15 | O | `feature-opt-alloc-intent-hint` | C | Self-declared "deferred / earn-it-first: no live profile is pulling this". Filed so the design is on record, explicitly not to schedule. |
| **10** | -5 | P | `compat-p-system-integer-is-smallint-in-fpc` | C | System.Integer is SmallInt in FPC's objfpc mode. A qualified-name corner; unqualified Integer already agrees. |
| **8** | -12 | A | `compat-pascal-strict-fpc-abs-and-sqr-widths` | C | A strict-mode escape hatch for two operators. The default divergence is deliberate and documented; this is parity-for-parity behind a flag. |
| **8** | -12 | P | `compat-pascal-method-impl-without-declaration` | C | We ACCEPT what FPC rejects. Laxness, the method dispatches consistently, and nobody's real program depends on the refusal. |
| **5** | -15 | A | `compat-pascal-strict-fpc-should-reject-a-duplicate-identifier-in-one-scope` | C | pxx compiles it and resolves BOTH correctly; FPC rejects. Pure laxness behind a flag, nothing resolves wrongly. |
| **5** | -10 | A | `idea-a-auto-enable-threadsafe-by-restarting-the-compile` | C | Explicitly WAIVED by the owner ("worth a ticket but i waive it for another day") and marked do-not-pick-up. Filed to preserve the idea only. |
| **5** | -5 | A | `idea-adaptive-heap-growth` | C | Self-declared "research / north-star — not scheduled... pick up only for fun or if a profile forces it." Its cheaper slices capture most of the win. |
| **5** | +0 | A | `meta-dialect-extensions-and-fpc-strict` | D | Self-declared NOT DISPATCHABLE — a charter with no green state it can reach. Its own header explains prio 5: visible at the tail, out of the dispatch slot. |
| **5** | -10 | N | `feature-nilpy-nested-def-as-value` | C | Marked SUPERSEDED in its own header by feature-nilpy-function-values, kept only for the closure-record reasoning. Should be moved to rejected/, not ranked. |
| **5** | -20 | P | `compat-pascal-directive-in-comment-ignores-nested-comments-off` | C | We are LAXER than FPC, the one-line fix BREAKS THE SELF-BUILD, and it is already tried-and-reverted. Nothing real depends on rejecting this. |
| **3** | -12 | A | `compat-pascal-binop-operand-eval-order` | C | Self-declared "DOCUMENTED, deliberately unfixed. Rainy-day only." Unspecified in ISO Pascal and in FPC's own documentation. |
| **3** | -7 | P | `compat-pascal-not-of-a-cast-constant-keeps-its-width` | C | `not Byte(0)` — pxx matches DELPHI and differs from FPC only in the constant-folded form; variables agree. The definition of a spec corner. |
| **0** | -40 | A | `chore-makefile-ws-skeleton-loop-hides-tmp-paths` | D | FILE NOT FOUND — ranked by `ready` but no ticket file exists in any status folder. Dangling board entry; delete or restore. |

---

## 4. How to apply this

1. **Resolve section 2.1 first.** Whether `ready` should scan `unfinished/` changes
   where 30 tickets — including a segfault at prio 88 and the html5lib ladder
   itself — sit in the queue. No prio edit is worth much until that is settled.
2. **Merge the four duplicate pairs (2.2) and clear the five stale entries (2.3)**
   before writing any number. That is ~9 rows of the 292 removed for free.
3. Then apply the table. Write a **bare `prio: N`** (no `# auto`) — per
   `devdocs/progress/README.md` that pins it as human-set and `autorate` will leave
   it alone.
4. Track U rows: leave to the Track U agent; the numbers here are context.
5. Track F (`float/`) and Track X (`experimental/`) were not touched and should stay
   parked.

*Produced by a re-triage pass, 2026-08-25. Every row was read; nothing was inferred
from the slug alone. Where a ticket's own text made the call (self-declared
"unranked", "not now", "superseded", "waived", "endgame"), that text is quoted in
the reason and the proposed number follows it.*
