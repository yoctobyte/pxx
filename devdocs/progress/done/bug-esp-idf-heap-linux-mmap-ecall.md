---
prio: 35  # ESP parked (user 2026-07-12): Pascal has prio; still the top ESP ticket when resumed
---

# ESP-IDF (.o) profile: builtin heap still uses Linux mmap — any string literal crashes

- **Type:** bug (runtime / builtin heap) — **Track A** (`compiler/builtin/builtinheap.pas`)
- **Status:** done
- **Opened:** 2026-07-11, hit by [[feature-esp-peripheral-callback-api]] slice 1
  (examples/esp32/timer-c3) under qemu esp32c3.

## Symptom

A riscv32 relocatable-object build for ESP-IDF (`--target=riscv32
--platform=esp`, `.o` output linked by idf.py) crashes the moment anything
allocates:

```
Guru Meditation Error: Core 0 panic'ed (Environment call from M-mode).
MEPC: ... (HeapMmap)  RA: ... (PXXAlloc)   A7 = 0xde (= 222, linux mmap)
```

`builtinheap.pas` selects the ESP static-arena path only for
`CPU_XTENSA` or `CPU_RISCV32 + PXX_ESP_BARE`:

```pascal
{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$ifdef PXX_ESP_BARE}{$define PXX_ESP}{$endif}{$endif}
```

The IDF profile is riscv32 + `--platform=esp` WITHOUT bare boot, so the heap
falls into the hosted-linux branch and executes `ecall` 222 (mmap) inside
FreeRTOS → panic. First trigger in practice is `PXXStrFromLit`: **passing any
string literal to a `string` parameter** (e.g.
`esp_rom_printf('...', v)`) allocates. This means the committed
`examples/esp32/hello-c3` also crashes if rebuilt with the current compiler —
its README's qemu validation predates the current heap/alloc behavior.

## Fix direction

- Key the arena (or a better heap) on the *platform*, not bare-boot:
  `CPU_RISCV32 + PXX_PLATFORM_ESP` → not linux-mmap. Hosted riscv32
  (qemu-user linux, posix platform) must keep real mmap (64 KiB arena OOMs
  sqlite — see the header comment).
- For the IDF profile specifically, the right heap is IDF's own: back
  PXXAlloc with `malloc`/`free` externals (resolved at IDF link time) instead
  of a fixed arena — the IDF heap is the SoC's real memory map. Bare keeps the
  static arena. May need a define to distinguish idf-vs-bare (PXX_ESP_BARE
  already exists; a PXX_ESP_IDF or just PLATFORM_ESP-and-not-BARE works).
- Define-application order is fine (PXX_ESP_BARE is applied the same way and
  builtinheap sees it).

## Acceptance

- examples/esp32/timer-c3 boots under qemu esp32c3 and prints its tick
  sequence (that example is the live repro; its README documents the crash).
- hello-c3 rebuilt with the current compiler still runs.
- Hosted riscv32 (qemu-user) keeps mmap; ESP bare keeps the static arena;
  self-host + cross gates green.

## 2026-07-14 — RESOLVED (b358)

- `PXX_ESP_IDF` define: `--platform=esp` without bare boot (any ISA).
- builtinheap: under PXX_ESP_IDF, PXXAlloc/PXXFree/PXXRealloc are backed by the
  IDF heap (`calloc`/`free` externals, resolved at IDF link time) with the same
  8-byte size header as the native allocator; calloc keeps the zero-init
  contract. Hosted riscv32 keeps mmap; bare keeps the static arena.
- `tools/esp_run.sh` now passes `--platform=esp` (it compiled the c3 leg as
  POSIX, which is how the linux-mmap heap got into IDF images at all).

Verified: string literal -> `string` param, AnsiString concat and Length all
run on BOTH IDF legs (esp32c3 and esp32s3) under qemu; test-esp-bare fully
green; quick + selfcheck green.

**Honest residual on the acceptance list:** timer-c3 now BOOTS and prints
`PXX timer: started` / `PXX timer: done ...` (the panic is gone), but its
callback never fires (`ticks=0 status=2`) — that is the pre-existing
[[bug-esp-emit-obj-proc-fixup-non-iram]] territory (the example's header wart
documents the same area), not the heap.

## Log
- 2026-07-14 — resolved, commit 98c1d40b.
