---
slug: bug-s-a-direct-call-to-an-interrupt-routine-is-the-same-trap-return-fault-by-another-spelling
track: S
type: bug
prio: 35
status: done
owner: frank
created: 2026-09-21
resolved: 2026-09-23
commit: PENDING-COMMIT
found-by: frankb-8e
blocked-by: []
summary: "FIXED 2026-09-23. A DIRECT CALL to a routine declared `interrupt;` is now refused at the AN_CALL convergence point (ir.inc) -- the sibling spelling of the `@proc` refusal in d305e1afa and the same fault: such a body returns via a trap-return (riscv32 `mret`, xtensa `rfe`), so any normal entry restores a caller-saved set the caller never saved and returns through mepc/EPC instead of the return address, with no diagnostic at link or run time. UNCONDITIONAL where the @proc arm is narrowed to bare riscv32/xtensa, because an address has one legitimate consumer (installing a vector) and a call has none on any target or profile. Placed AHEAD OF IRInlineExpand: at -O2 an inline-eligible body is spliced in before a call node exists, so a predicate below the inliner is bypassed on exactly the builds that ship -- there is a -O2 row as that ordering's positive control. THE BLOCKER THIS TICKET WAS PARKED ON WAS CORRECT WHEN FILED AND FALSE 15 HOURS LATER: it required an emission-forcing mechanism before the fixture could drop its always-false `if counter < 0 then MyIsr;`, and 57af7aa10 made every `interrupt;` body an unconditional DCE root (DCE_WHY_VECTOR) as a side effect of bare xtensa's vector table -- the very option this ticket named as probably right. Nobody recorded that it closed the blocker; found by running --dce-why, not by reading. The fixture's two existing rows asserted only that the compiler exited 0, so the probe that existed to prove the ISR is emitted never checked that it was; rows now assert MyIsr is FUNC at shndx=3 and that [ 3] is .iram1.text, on both ISAs, and fail against an ISR-less object. THE CONDITION THAT WOULD SPRING THIS AGAIN: the DCE_WHY_VECTOR root being removed or gated, which would delete an uncalled handler and leave a vector pointing at the hole -- fix the root, never by reintroducing a call."
---

# A direct call to an `interrupt;` routine is the same fault by another spelling

## Why it is filed separately rather than left in a comment

`d305e1afa` refused `@<interrupt proc>` at the AN_PROCADDR convergence point.
That closes the arm anyone hits by accident. It does **not** close the class,
and this repo's own `normalise-dont-special-case` rule says the sibling is
usually a *spelling* rather than a shape — which is exactly what this is. The
code comment in `ir.inc` names it, but a comment is read by whoever is already
editing that function; the point of a ticket is to be found by someone who is
not.

## The mechanism, restated so it does not depend on the sibling ticket

`interrupt;` emits a raw trap routine whose epilogue is `mret` (riscv32) or
`rfe` (xtensa). Those pop privilege state and resume through the machine
exception PC. Entered by a normal `jalr`/`callx`, there is no trap frame to
return through and the caller's return address is never consulted. Nothing
diagnoses it at any stage.

## The actual obstacle

`test/test_esp_interrupt.pas` is a structural probe: it must get `MyIsr`
EMITTED so the prologue/epilogue and `.iram1.text` placement can be inspected,
without ever executing it. Its only lever today is a call behind a
runtime-false guard:

    if counter < 0 then MyIsr;   { never true; forces emission }

Refuse direct calls and that fixture has no way to do its job — and it is the
fixture that proves the ISR codegen exists at all.

## So the ticket is the mechanism, not the refusal

Pick one, then the refusal is trivial:

- a `{$KEEP}` / `{$USED}` directive, or an existing equivalent if one exists
  (**grep before adding one** — this repo has a standing instance of proposing
  a mechanism that already existed under another name);
- exporting the routine, if that already pins a body;
- **making `interrupt;` bodies unconditionally DCE-retained**, which is
  arguably correct on its own terms: a handler's only legitimate caller is
  hardware, so DCE can never see a reference to it and *every* such body is
  reachable-in-fact and unreachable-in-graph. This is probably the right
  answer and it deletes the problem rather than working around it.

**Positive control when it lands, both arms:** a direct call to an `interrupt;`
routine must be REFUSED, and `test_esp_interrupt.pas` (rewritten onto whatever
mechanism is chosen) must still compile AND still emit `MyIsr` — assert the
symbol is present in `.iram1.text`, not merely that the file compiled, or the
new mechanism can silently do nothing and the row still passes.

## Related

- `bug-s-an-interrupt-directive-proc-reached-through-a-normal-call-returns-via-mret-with-no-diagnostic`
  — the `@proc` arm, fixed in `d305e1afa`.
- `devdocs/dev/esp32-hardening-map.md` §1.2.

---

# FIXED 2026-09-23 (frank)

## The obstacle above was real when filed and false 15 hours later

Everything from "## The actual obstacle" down was **correct when written** and
had been overtaken before anyone read it again. This is not a summary that
drifted: the ticket was created in `f47eb50c9` at **09-21 10:11**, two minutes
after the `@proc` refusal it was split out of, and `57af7aa10` landed at
**09-22 01:57** — *"bare xtensa emits its own exception vector table"* — which
made every `interrupt;` body an **unconditional DCE root**, `DCE_WHY_VECTOR`.
That is precisely the third option this ticket lists and calls *"probably the
right answer"*. It arrived as a side effect of a feature commit, nobody
recorded that it retired this blocker, and the design question the ticket
describes never needed answering.

`dce.inc` explains the history in its own comment at the root loop, which is
the part worth keeping:

> *Until the compiler emitted that table a program had to write `@MyIsr` itself
> to install one, so every such body was reachable as `DCE_WHY_PROCADDR` and
> this root was never needed — the gap existed and was masked by the very
> awkwardness the table removes.*

So the fixture's always-false call had been dead weight since the moment the
vector table landed, and it went on demonstrating the exact mistake the
compiler already refused in its other spelling.

**Found by measuring, not by reading.** The ticket states its obstacle in the
summary, which is the part everyone reads, so the cheap move was to believe it
and go design a `{$KEEP}` directive. `--dce-why` answers the question directly:

```
$ pascal26 --dce --dce-why=MyIsr --target=riscv32 --platform=esp --emit-obj <fixture, call deleted>
dce: bodies 139  live 9 (2876B)  dead 129 (165904B)  dropping 129 (165904B)
dce-why:   [match] 312B  MyIsr <- [interrupt; -- entered by hardware]
```

DCE *runs* and drops 129 bodies; `MyIsr` survives as a root in its own right.

**Independent control, because the above is this session's own compiler:** the
**pinned** compiler — which predates this commit — also emits `MyIsr` at
`shndx=3` from the fixture with the call deleted. The property is not something
this fix introduced.

## What landed

**The refusal**, at the top of the `AN_CALL` arm in `ir.inc`, unconditional.
The `@proc` refusal is narrowed to bare riscv32/xtensa because an address has
one legitimate consumer — installing a vector — and a **call has none on any
target or profile**, so there is no arm to carve out.

**Ahead of `IRInlineExpand`, deliberately.** At `-O2` an inline-eligible body is
spliced in before any call node exists, so a predicate placed lower would be
bypassed *by the optimiser*, on exactly the builds that ship. `test-emit-obj`
carries a `-O2` row as that ordering's positive control; it is not a duplicate
of the `-O0` row and must not be deduplicated into one.

**`AN_CALL` is the convergence site**, for the same reason `AN_PROCADDR` is for
the address: a procedure statement and a function call in an expression both
allocate `AN_CALL`. The other kinds cannot reach an `interrupt;` routine —
`AN_VIRTUAL_CALL`/`AN_INTF_CALL` need a method and the directive is only
accepted on a plain routine, and `AN_CALL_IND` needs an address already denied.

**`test/test_esp_interrupt.pas` lost its guarded call** and says in its header
why, including *do not reintroduce one* if a future DCE regression deletes the
handler — the root is what would have broken.

## The rows, and the gap they close

The ticket asked for exactly the control that was missing, and it was right to:

> *assert the symbol is present in `.iram1.text`, not merely that the file
> compiled, or the new mechanism can silently do nothing and the row still
> passes.*

**The two pre-existing rows for this fixture asserted only that the compiler
exited 0** — which deleting the handler would not have disturbed. So the
fixture that existed to prove the ISR codegen is emitted never checked that it
was. Added, both ISAs: `MyIsr` present as `FUNC` at `shndx=3`, and `[ 3]` is
`.iram1.text`. Negative control: both rows FAIL against an object built from a
program with no ISR, so they are not decorative.

Refusal rows on both ISAs plus `-O2`, each grepping the message so the row
fails for the right reason. **Positive control against the pin:** the pinned
compiler ACCEPTS `test_esp_interrupt_direct_call_fail.pas` (rc=0, object
contains `MyIsr`) where HEAD refuses it, so the row discriminates and is not
born red. The fixture keeps the call **behind an always-false guard on
purpose** — that is the shape the old fixture used and the shape a structural
probe reaches for, so it is the one that most needs refusing.

## Not closed by this

Nothing here touches whether an `interrupt;` handler can be *installed*. That
remains the `@proc` refusal's narrowed arm (bare riscv32/xtensa, vector-install
operand only) and the dedicated-ISR-stack condition recorded there.

## Log
- 2026-09-23 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
