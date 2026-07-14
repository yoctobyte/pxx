---
prio: 30  # ESP parked (user 2026-07-12): Pascal has prio
---

# --emit-obj: @proc fixups require an iram/interrupt routine — plain callbacks can't be registered

- **Type:** bug / gap (relocatable-object writer) — **Track A** (`elfwriter.inc`
  / emit-obj path)
- **Status:** working
- **Opened:** 2026-07-11, hit by [[feature-esp-peripheral-callback-api]]
  slice 1 (esp_timer event surface).

## Symptom

Taking a plain (non-`iram;`, non-`interrupt;`) procedure's address in a
program compiled to a relocatable object fails:

```pascal
procedure Tick(arg: Pointer);   { plain proc — esp_timer callback, task context }
begin ... end;
...
p := Pointer(@Tick);            { or a proc-type value handed to the SDK }
```

```
pascal26:2: error: --emit-obj: @proc fixups need an iram/interrupt routine present (non-iram .o path not wired)
```

Marking the routine `iram;` compiles fine (the existing
`writeELF32RelIram` path emits the R_RISCV_32 reloc against the proc symbol).

## Why it matters

esp_timer / GPIO / ADC callbacks on ESP-IDF are *task-context* callbacks —
they specifically do NOT want IRAM placement (the whole point of
feature-esp-peripheral-callback-api slice 1). Today every SDK callback must be
mislabeled `iram;` just to get its address into the .o, wasting IRAM and
contradicting the "no iram; in app code" acceptance of the callback-API
ticket. The interim example `examples/esp32/timer-c3` carries exactly that
workaround + a pointer to this ticket.

## Acceptance

- `@proc` / proc-type values for ANY routine emit the proper absolute
  relocation in `--emit-obj` output (riscv32 first; same path for other
  emit-obj targets if/when they exist).
- The `iram;` marker goes back to meaning ONLY ".iram1.text placement".
- examples/esp32/timer-c3's callback drops its `iram;` and still builds/runs
  under qemu IDF; self-host + cross gate green.

## 2026-07-14 — RESOLVED (b360)

A program with @proc fixups but no iram routine now routes through the
extended two-text-section writer (which already relocates ProcAddrFix against
the proc's LOCAL symbol); with no iram procs its .iram1.text is simply empty.
Verified on qemu esp32c3 IDF: a PLAIN routine's address assigned to a
proc-type variable and called indirectly runs (`tick via ptr 1/2, hits=2`).
timer-c3's callback dropped its `iram;` and still builds and boots.

**Honest residual:** timer-c3 still reports `ticks=0 status=2` — the
esp_timer callback never fires under qemu. Identical with and without iram;,
and the @proc reloc is proven good by the indirect-call probe, so it is the
esptimer library ↔ qemu emulation interaction, not the .o writer. Belongs to
feature-esp-peripheral-callback-api's validation, not this ticket.
