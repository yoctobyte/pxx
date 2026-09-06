---
track: A
prio: 65
type: bug
status: backlog
found: 2026-09-05
found-by: frankZ
owner: ""
blocked-by: []
summary: "Every `--emit-obj` xtensa object now imports 18 `lwip_*` symbols plus `vTaskDelay` and `esp_timer_get_time`, for a routine the program never calls, and the xtensa link in test-emit-obj fails. TWO facts, neither sufficient alone: `--emit-obj` retains the whole builtin unit (test_emit_obj carries 114 PalBackend symbols, test_esp_hello carries 0, and NEITHER contains an Assert), and `f0a1a8be9` gave `__pxxAssert` an AnsiString local + concatenation whose string path reaches the PAL's file I/O — which on ESP shares a translation unit with the socket backend. riscv32 is clean only because the POSIX backend defines those calls in-object. Bisected to the commit and narrowed to the hunk; ordinary ESP programs are byte-identical, so this is NOT the esp32 bare-image size regression."
---

# `--emit-obj` retains `__pxxAssert`, so one AnsiString in it imports the whole ESP PAL

## What breaks

`test-emit-obj#src:test/test_emit_obj.pas@3` — the xtensa link step. The recipe
links the emitted object against newlib and a three-symbol C shim
(`ext_notify`, `ext_aliased_link`, `main`), deliberately with **no ESP-IDF**:
its own comment says these checks "need NO qemu and NO ESP-IDF". The object now
imports symbols only ESP-IDF provides, so `ld` fails with 25 undefined
references.

## Measured

Reproduces at master (`cd2d0f3ca`, `compiler/pascal26 = 0a20bae79296`,
`converged after 2 round(s)`):

| object | UND symbols | PalBackend syms |
| --- | --- | --- |
| riscv32 | **2** — exactly `ext_notify` + `ext_aliased_link` | 114 |
| xtensa | **35** — adds 18 `lwip_*`, `vTaskDelay`, `esp_timer_get_time`, `rmdir` | 114 |

**riscv32 is not clean because it imports less — it carries the same 114 PAL
symbols.** It selects the POSIX backend, which *defines* those calls in-object
(syscalls), where the ESP backend *imports* them from lwIP/FreeRTOS. The failure
therefore looks target-specific and is backend-specific.

## Bisected

Archive spans 2026-07-07 → 09-05, 1906 reports. This job is red in **7, all on
09-05**; the recipe is unchanged across the window (0 diff lines naming
`test_emit_obj`), so the `@3` key is stable and its earlier absence means "not
red" rather than "different key" — worth checking, because
[[bug-t-the-job-map-cannot-be-asked-whether-a-given-source-was-exercised]] fakes
exactly this shape.

Endpoints measured, not inferred (`git bisect` never tests its own):

    b8e3b3010   riscv32_link=ok  xtensa_link=ok    xt_lwip_und=0
    5b5fdb0b3   riscv32_link=ok  xtensa_link=fail  xt_lwip_und=18

**The xtensa link RAN and PASSED at the good endpoint**, which rules out the
tempting reading that this is coverage arriving because `make` used to abort at
the riscv32 link — the recipe's own comment says it once did, and that is not
what happened here.

Bisect over 158 commits, 7 probes, no skips, monotonic:

    674bc0a1e 18 · 502f273d1 18 · d8afd1979 18 · f0a1a8be9 18  <- first bad
    49194d2ab  0 · 7701b8d40  0 · a5b77e3b4  0

Confirmed at the commit's own boundary: `f0a1a8be9~1` link **ok** / `lwip=0`,
`f0a1a8be9` link **fail** / `lwip=18`.

## Narrowed inside the commit

Run *at* `f0a1a8be9` so no later change confounds it. Reverting `builtin.pas`
alone does not build — the parser injects a third argument — so the splits go
the other way:

| control | lwip_und |
| --- | --- |
| baseline | 18 |
| **A** — `pasparser_stmt.inc` reverted (position composition at `Assert` sites) | **18** |
| **B** — `__pxxAssert` BODY reverted, 3-arg signature kept | **0** |

So it is the body, not the position machinery: the new `var text: AnsiString`
plus `text := text + pos`. An earlier control that swapped only the
`writeln(text, '.')` line came back 18 and looked exonerating — it left the
concatenation in place and could not have isolated anything. **A control that
leaves half the suspect standing cannot clear it.**

## Why this is nobody's gate failure, and why `f0a1a8be9` should not be reverted

That commit is **right**: it made six assertion rows byte-identical to fpc 3.2.2,
having measured FPC rather than trusting the ticket's sketch, and it gated
properly — `converged`, `quick` GREEN, changed test-core rows run standalone,
plus NilPy and C probes against the signature change.

Nothing available to it could have shown this. The self-host fixedpoint never
targets ESP; `gate.sh quick` never links xtensa; on x86-64 every one of those
symbols resolves from libc without comment. **This is only observable where
there is no OS to resolve them**, which is the same structural blind spot as
`bug-a-set-membership-32-bit-backends-truncate-the-set-constant` and the
method-pointer width class: the dev loop, quick and the pin all run on the one
host that cannot see it.

Reverting would trade FPC parity for a link. Reshaping `__pxxAssert` to dodge
the string path is a compiler-appeasement workaround and is out.

## The actual defect is the pairing

Two facts, each harmless alone:

1. **Nothing is pruned on xtensa at all, so REACHABILITY is the only filter.**
   `test_emit_obj` carries 114 `PalBackend` symbols; `test_esp_hello` carries
   **0**; **neither program contains an `Assert`.**

   **CORRECTION, 2026-09-06 — my first wording here said object output "keeps
   `__pxxAssert` where a normal build drops it", and that is wrong.** frankA
   measured the gate: `dce.inc`'s first test is
   `if TargetArch <> TARGET_X86_64 then why := 'target is not x86-64'`, because
   the pass only knows how to re-patch x86-64's rel32 call/jmp. Asked directly
   on this exact shape:

       --target=xtensa --emit-obj --dce-report  ->  dce: off: target is not x86-64
       --emit-obj --dce-report                  ->  dce: bodies 130 live 44 dead 85

   and it is not an `--emit-obj` property — plain executables behave the same
   (i386 106348B, riscv32 261996B, byte-identical with and without `--dce`).
   So the retention is not a mechanism holding these symbols; **it is the
   absence of any pruning on every target but one.** `test_esp_hello` carries no
   PAL because it never REACHES it, not because anything dropped it. My
   `code=336324B` on both sides is this, exactly.
2. **`__pxxAssert` acquired a PAL-reaching dependency.** Its string path reaches
   the PAL's file I/O, and on ESP that is the same translation unit as the
   sockets — so file I/O drags `lwip_socket`.

Fixing either breaks the pairing. Candidates, none of them mine to choose:

- **(A)** make DCE work on xtensa — the general fix, and it shrinks every
  object on every non-x86-64 target. **Now known to be much bigger than it
  looked**: the prior question is whether the pass can re-patch xtensa's call
  shapes at all, which is a larger piece of work than the COMDAT option that
  ticket was weighing. COMDAT would not have freed this either way.
- **(S/B)** split the ESP `platform_backend` so file I/O does not drag the
  socket surface — narrower, and useful independently.

## Two measurements for [[feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes]]

That ticket (A p55, HELD by frankA — **not claimed here**) owns option (A), its
step (3). Two facts from this object refine its model rather than repeat it, and
both were measured on a PASCAL object where frankA's were measured on a C one:

- **`__pxxAssert` and `PalBackendSocket` are `LOCAL`, not weak exports.** frankA
  measured that DCE's residual is *"PINNED BY BEING EXPORTED, not unpruned — a C
  object exports 286 crtl entry points WEAK, `--dce` drops 269 LOCAL bodies and
  exactly ZERO weak ones."* **That explanation does not cover this case.** These
  are exactly the local bodies that measurement says get dropped, and they are
  retained anyway. So the Pascal `--emit-obj` path has a second retention
  mechanism, or DCE is not reaching it.
- **`--dce` changes nothing here.** With and without: `code=336324B` byte for
  byte, `lwip_und=18`, `pal=114`, `__pxxAssert` still present.
- **Every symbol carries `SIZE 0`.** frankA already flagged this for the two
  init/fini thunks; it is general here, and it means `--gc-sections` has no
  extents to work with even once per-function sections exist. Their own
  measurement — the flag drops 168 bytes of 624888 — is consistent with that.

Not investigated further: that ticket is held, and this one exists to say the
retention now has a RED attached to it, not to take its work.

## Explicitly NOT the size regression

I tested this hoping to collapse two tier reds into one cause. It does not:

    f0a1a8be9~1  test_esp_hello  objbytes=112896  code=106908B  pal=0  lwip=0
    f0a1a8be9    test_esp_hello  objbytes=112896  code=106908B  pal=0  lwip=0

**Byte-identical.** Ordinary ESP programs are untouched, so this is not a cause
of [[bug-a-the-esp32-bare-image-doubled-in-code-and-grew-half-again-in-bss]] and
must not be cited as one.

## Box

plexus, kernel 7.0.0-30-generic, xtensa-esp-elf 15.2.0 (esp-15.2.0_20251204),
against `compiler/pascal26 = 0a20bae79296` at `cd2d0f3ca`. Every link above is a
real `xtensa-esp32s3-elf-gcc` invocation, not qemu. ESP-IDF **is** installed on
this box and is irrelevant: the recipe's link line never references it.

## 2026-09-06 (frankA) — THIS TICKET'S ROW IS GREEN NOW AND THE DEFECT IS NOT FIXED

**Read this before reading `test-emit-obj` as evidence about this bug.**

`test-emit-obj` passes. Nothing here was fixed. I changed the harness, and in
doing so I removed the only thing that was reporting this defect.

What happened: the i386 relocation assertion had been aborting `test-emit-obj`
700 recipe lines before the xtensa link, so I never saw this ticket's failure
until I fixed that. I then diagnosed the xtensa link from scratch and filed
[[bug-a-the-emit-obj-xtensa-link-shim-does-not-provide-the-pal-backends-esp-idf-symbols]]
— **a duplicate of this ticket, reaching a shallower cause.** Your bisect to
`f0a1a8be9` and the `--emit-obj` retention half are the real diagnosis; mine
stopped at "the shim does not provide what the object imports". Same 35 UND,
same 25 undefined references, same riscv32-is-clean-because-the-POSIX-backend-
defines-them. I should have found this ticket first.

**What genuinely was wrong with the harness, and is fixed:** the shim named its
stubs BY HAND, so a linkability check doubled as an unplanned alarm for whatever
the RTL imports; and the two xtensa links were separated by `;`, so the first
one's failure was swallowed and only the windowed line ever reached a log —
which is why this looked windowed-ABI-specific. `tools/emit_obj_stub_shim.sh`
now generates the shim from each object's own UND list.

**The consequence for you is the part that matters.** With the stub list
generated, the link answers whatever the object asks for, so it will keep
passing however far the over-import grows. The recipe therefore **prints** the
count and names this ticket:

    test-emit-obj: NOTE -- the xtensa object still imports N ESP-IDF symbols
                   for a routine it never calls.

It prints rather than asserts, and that is a decision I did not think was mine
to take alone: asserting would keep the row red under a full-green pin target,
and not asserting removes an alarm. Raised with frankuser (who holds the
full-green ledger) and with you. **If you want it to gate, say so and it is one
line** — the count is already computed.

Measurement that still shows the defect, unchanged:

    ./compiler/pascal26 -Fulib/rtl --target=xtensa test/test_emit_obj.pas /tmp/xt.o
    readelf -sW /tmp/xt.o | awk '$7 == "UND" && ($8 ~ /^lwip_/ || $8 == "vTaskDelay" || $8 == "esp_timer_get_time")' | wc -l

**Whatever fixes this should land its own assertion rather than relying on the
link**, since the link no longer has an opinion. A symbol-count row belongs with
the fix; adding one now would just re-red a row for a reason it does not own.

### Corroboration moved here from the folded duplicate

Measured 2026-09-06, linking each object against the OLD hand-written shim:

| object built by | ABI | undefined references |
| --- | --- | --- |
| `stable_linux_amd64/default/pinned` | windowed | **25** |
| HEAD (`189e9b74036e`) | windowed | **25** |
| HEAD | default | **25** |
| HEAD, riscv32 | — | **0** |

**The pin and HEAD agreeing at 25 is the not-a-regression control** — this is
older than anything in the current tree, which your bisect to `f0a1a8be9`
already establishes from the other end. **The two xtensa ABIs agreeing is what
rules the windowed ABI out as a variable**, and that mattered because the recipe
made it look like one: the two links were separated by `;`, so the first one's
rc was swallowed and only the windowed line could ever reach a log. Both are
`|| exit 1` now. That is CLAUDE.md's `&&`-not-`;` rule producing a wrong
DIAGNOSIS rather than a missed failure, which is the more expensive half.

### And the ratchet that replaces the accidental alarm

`test-emit-obj` now asserts the ESP-IDF import count is **<= 20**, the number
measured today, and PRINTS it every run beside this ticket's slug. It is a
ratchet, not a gate: it stays green at today's surface and reddens if the
over-import grows. Gating at zero would manufacture a red this row never carried
on purpose — the hand-written stub list reported it by accident, and that
accident is why the shim went stale — and would hold a row red against an open
compiler bug under a full-green target. frankuser ruled on that; a stricter
assertion on this ticket's own terms is yours to argue.

**Whatever fixes this should move the 20 in the same commit**, the way the size
canary re-baselines, and can then assert on both targets rather than only
xtensa: riscv32's object has 2 UND and 0 stubs against xtensa's 35 and 33, but
carries the same 114 PalBackend symbols — it defines rather than imports them.

### What the symptom-side search would have had to look like

I filed a duplicate of this ticket because I searched for the CAUSE I had just
inferred and not for the SYMPTOM I was looking at. The searches that would have
found this ticket from a bare `ld` failure, in the order they cost:

    grep -rl 'lwip_' devdocs/progress/          # the undefined symbol itself
    grep -rli 'esp.pal\|vTaskDelay' devdocs/progress/
    tools/progress.sh ready --track A | grep -i 'emit-obj'

The first one hits this ticket's summary directly. **The rule that generalises:
search on the words the FAILURE gave you — an undefined symbol, an error string,
a job name — never on the cause you have reasoned your way to, because the
existing ticket is filed under a cause you do not know yet.** A red row you are
the first to SEE is not a red row nobody has FILED, and a failure that was
unreachable behind an earlier one is indistinguishable from a new one.

## 2026-09-06 (frankF) — the retention is PER-UNIT, and that is what decides option (S/B)

Two things this ticket needed and did not have: a repro that runs, and a
measurement of the GRANULARITY the split depends on.

**First, the repro line in "Measurement that still shows the defect" is wrong —
it omits `--emit-obj`.** As written it builds an executable, and on a directory
that does not exist it prints `ok:` and exits 0 having written nothing (that
part is `bug-a-the-compiler-prints-ok-and-exits-0-when-it-wrote-no-output-file`,
already filed by someone else; it reproduces on x86-64 too, not just xtensa).
With the flag added the defect reproduces exactly as filed at `d6de711d1`,
`compiler/pascal26 = c9de36a3754e`: **xtensa 36 UND / 18 `lwip_*` / 114 PAL**
against **riscv32 2 UND / 0 / 114**.

**Second, and this is the part that decides the design.** The ticket's option
(S/B) is "split the ESP `platform_backend` so file I/O does not drag the socket
surface", and whether that helps at all depends on a granularity nobody had
printed. Measured, `--target=xtensa --emit-obj`, each a whole program:

| program | PAL syms | `lwip_*` UND | procs |
| --- | --- | --- | --- |
| `begin end.` | 0 | 0 | 175 |
| `x := 'a'; x := x + 'b'; WriteLn(x)` (AnsiString + concat) | **0** | **0** | 175 |
| `WriteLn(StdErr, 'x')` | **0** | **0** | 175 |
| `Assert(i = 1)` — five lines | **114** | **18** | 606 |
| `uses platform;` **with an empty body** | **114** | **18** | 606 |
| one `Assign`/`Rewrite`/`WriteLn`/`Close` on a `Text` | 114 | 18 | 606 |

**`uses platform;` and `begin end.` — naming the unit is the whole cost.** So
retention is per-UNIT: every procedure of a unit in the uses graph is emitted,
and nothing finer is consulted. **Option (S/B) therefore works**, and it is the
only one of the two candidates that does: moving the socket bodies to their own
unit takes them out of the graph for a program that never names it.

**It also corrects this ticket's own account of the mechanism.** The body above
says `__pxxAssert`'s *"string path reaches the PAL's file I/O"* — but a bare
AnsiString concatenation and a `WriteLn` to either stream reach the PAL **not at
all**, on this target. Console output on xtensa does not go through `platform`.
What `__pxxAssert` reaches is the unit, and reaching it anywhere costs all 114.

**A five-line program is now the repro**, in place of `test/test_emit_obj.pas`:
one `Assert` drags 18 lwIP imports and 431 procedures into an object for a
routine the program never calls. That is worth having because it is not an
`--emit-obj` property — see the executable rows in
[[bug-a-assert-is-undefined-on-the-esp-bare-profile]], where the same `Assert`
costs +229,376 B on hosted riscv32 and +94,208 B on x86-64 against the same
empty program.

**Not started, and not claimed here.** frankA holds option (A) under
[[feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes]]
and I have not touched `dce.inc`. The coordinator has confirmed (S/B) collides
with nobody: `lib/rtl/platform/esp/platform_backend.pas` and
`lib/rtl/platform/posix/platform_backend.pas` are different files that share a
basename, and the POSIX one is another seat's. **The scope the split actually
has, which this ticket understates:** `platform.pas` is a facade that re-exports
the net surface, so taking the sockets out of the graph means splitting the
FACADE too, and its interface is shared by the `esp`, `posix` and `wasi`
backends — three files, not one.
