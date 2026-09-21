---
slug: bug-s-an-interrupt-directive-proc-reached-through-a-normal-call-returns-via-mret-with-no-diagnostic
track: S
type: bug
prio: 60
status: done
owner: ""
created: 2026-09-21
found-by: frankb-8e
blocked-by: []
summary: "FIXED d305e1afa (the @proc arm; the direct-call arm is split out and still open). `interrupt;` and `iram;` are two spellings of one concept -- an ESP interrupt handler -- and WHICH ONE IS CORRECT IS DECIDED BY THE DISPATCHER THAT CALLS YOU, not by anything visible at the declaration. A raw vector entry must be `interrupt;` (epilogue returns via `mret`/`rfe`); an esp_intr_alloc handler must be `iram;`, because the IDF dispatcher calls it as an ordinary `void(*)(void*)`. PICKING WRONG PRODUCES NO ERROR AT ANY STAGE: an `interrupt;` proc whose address is handed to esp_intr_alloc compiles, links and executes a trap-return instruction to leave a normal call, restoring a caller-saved set the caller never saved and returning through mepc/EPC rather than to the return address. The condition that springs it is any `@proc` of an `interrupt;` routine reaching a normal call site or an external -- so it is armed the moment a third ISR call site is written, and the only reason it has never fired is that the tree's two existing ISR tests (test_esp_isr_register.pas using `iram;`, test_esp_interrupt.pas using `interrupt;`) each happen to have picked the right one while NOTHING IN THE TREE STATES THE RULE. Wants a compile-time refusal, not a note: this is normalise-dont-special-case's sibling case, where the two spellings mean the same thing to whoever wrote the source and neither the construct name nor the test corpus distinguishes them. Diagnosing it on silicon costs a board session; refusing it costs a predicate at the @proc site."
---

# An `interrupt;` proc reached through a normal call returns via `mret`, silently

## The mechanism

Measured 2026-09-21 at pin v414 by disassembling `test/test_esp_interrupt.pas`
compiled `--emit-obj` on both ESP ISAs. An `interrupt;` body is a correct raw
trap routine:

| | riscv32 | xtensa Call0 |
| --- | --- | --- |
| prologue saves | `t0`-`t6`, `a0`-`a7` (64 B) + `ra`/`s0` | `a2`-`a13` (48 B) + `a0`/`a15` |
| returns via | `mret` (`30200073`) | `rfe` (`003000`) |

That is exactly right for a hardware vector entry and exactly wrong for
anything reached by `jalr`/`callx`. `mret`/`rfe` pop privilege state and jump
through the machine exception PC — in a normal call there is no trap frame to
return through, and the return address the caller left is never consulted.

## Why nothing catches it

- **The compiler does not care** how a proc's address is used. `IR_PROCADDR`
  materialises the body address for any routine; nothing consults
  `ProcIsInterrupt` at the `@proc` site.
- **The linker cannot care.** Both directives produce a `FUNC` symbol in
  `.iram1.text`; the reloc is identical.
- **The IDF cannot care.** `esp_intr_alloc(source, flags, handler, arg, ret)`
  takes a `void(*)(void*)` — any code address satisfies it.

So the failure surfaces only as a fault on the device, at a point unrelated to
the declaration, which is the most expensive place this fleet can be wrong.

## Why this is a bug rather than documentation

The two existing call sites are both correct, and that is the whole hazard: the
rule is enforced by coincidence. CLAUDE.md's `normalise-dont-special-case`
sibling clause is exactly this shape — *"both spellings mean the same thing to
the person who wrote the source, so neither the construct name nor the test
corpus distinguishes them"* — and its prescription is to reach for the other
spelling's handler rather than the feature. Here the cheaper discharge is a
refusal at the one site that can see both facts.

## Suggested shape (not prescribed)

Refuse, or at minimum warn, when `@<proc>` of a routine with `ProcIsInterrupt`
set is used as anything other than the operand of a raw vector install. Today
that is trivially decidable because **there is no raw vector install at all**
— see the CSR ticket below — so *every* `@interrupt_proc` is currently a
mistake. That makes the positive control easy and it makes the refusal cheap
now and refinable later.

**Positive control, and it must be drawn from the right population:**
`test_esp_isr_register.pas` with its `iram;` changed to `interrupt;` must be
REFUSED, and the file as it stands must still compile. Assert both arms — a
refusal that also rejects the correct spelling is not a guard, it is a break.

## Related

- `devdocs/dev/esp32-hardening-map.md` §1.2 — the measurement and the buckets.
- `feature-s-a-csr-write-is-not-expressible-from-pascal-so-no-raw-isr-can-be-installed`
  — why the raw arm is currently unreachable, which is what makes the refusal
  cheap today.

## Log
- 2026-09-21 — resolved, commit d305e1afa. Refused at the AN_PROCADDR convergence
  point in ir.inc, so every spelling of `@f` is covered rather than the one the ticket
  happened to name. BOTH CONTROL ARMS ASSERTED: test_esp_isr_register.pas as it stands
  (`iram;`) still compiles and produces an object; the same file with `iram;` changed to
  `interrupt;` is REFUSED at line 30 — exactly the `h := @MyIsr;` line — and produces none.
  The refusal is unconditional today because no raw vector install exists in the language;
  the code comment says in terms that it must be NARROWED to permit the install operand
  when that lands, not deleted. `gate.sh quick` GREEN, read from the job's own verdict line
  rather than the wrapper's exit status; fixedpoint a7ce4183f209.
  RESIDUAL, SPLIT OUT RATHER THAN CLOSED SILENTLY: a DIRECT CALL to an `interrupt;` routine
  is the same fault by a different spelling and is deliberately NOT refused, because
  test_esp_interrupt.pas depends on one to force body emission. Filed as
  `bug-s-a-direct-call-to-an-interrupt-routine-is-the-same-trap-return-fault-by-another-spelling`.
