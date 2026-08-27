---
slug: feature-a-complete-the-builtin-unit-on-the-esp-class-targets
track: A+S
prio: 60
type: feature
blocked-by: []
status: backlog
summary: "Not \"builtin is unavailable on ESP\" but \"xtensa is hardcoded as bare-metal on both axes, whatever the profile\". Measured under --platform=esp (the IDF-linked route): esp32c3 compiles Variant + UpCase + Str with the FULL builtin unit; esp32s3 is refused. riscv32-under-IDF already proves the unit works on an ESP target — xtensa, the user's own S2/S3 hardware, is the one locked out, and it is locked out of the profile where FreeRTOS, VFS and sockets actually live."
---

# Complete the `builtin` unit on the ESP-class targets

> **Re-scoped 2026-08-27 after the user's second correction:** *"the IDF-linked
> route is more interesting than the bare metal route, bare tests the compiler
> but misses out on a lot of functionality."* That reframes this ticket, and
> measuring against the IDF profile makes the defect much sharper than the
> version below found.
>
> Under **`--platform=esp`** (relocatable `.o` linked by `idf.py` into a
> FreeRTOS app — what `tools/esp_run.sh` builds and what actually ships):
>
> | | `Variant` + `UpCase` + `Str` |
> | --- | --- |
> | `--target=riscv32 --platform=esp` (esp32c3) | **compiles** — the full `builtin` unit, 341416B |
> | `--target=xtensa --xtensa-abi=windowed --platform=esp` (esp32s3) | **`UpCase: builtin helper unavailable ... not on ESP`** |
>
> So it is **not** "the ESP targets cannot have `builtin`" — riscv32 under IDF
> already has all of it, on an ESP target, today. It is that **xtensa is
> hardcoded as bare-metal on both axes, regardless of profile**:
>
> ```pascal
> { util.inc — the COMPILER side }
> Result := (TargetArch = TARGET_XTENSA) or
>           ((TargetArch = TARGET_RISCV32) and EspBareBoot);
>
> { builtinheap.pas — the UNIT side }
> {$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
> {$ifdef CPU_RISCV32}{$ifdef PXX_ESP_BARE}{$define PXX_ESP}{$endif}{$endif}
> ```
>
> Both read "xtensa **means** bare metal". That was true before the IDF profile
> existed and is now wrong, and it is wrong in the worst place: xtensa is the
> **S2/S3**, the user's own hardware, and it is locked out of precisely the
> profile where FreeRTOS tasks, IDF drivers, VFS file I/O and sockets live.
>
> **This also retires a judgement call from the version below.** It said
> `{$ifndef PXX_ESP}` around **file I/O** was "a genuine platform statement".
> It is not — under IDF, basic VFS file I/O works (CLAUDE.md's own ESP note:
> *"sockets and basic VFS file I/O are what work"*). The exclusions are keyed on
> the **ISA** where they should be keyed on the **profile**, and that single
> mis-keying is the bug. `--esp-profile=bare` is the axis that legitimately
> withholds an OS; `TARGET_XTENSA` is not.
>
> **The repo already knew.** `test-esp-idf`'s own comment, on the timer demo:
> *"passing a 64-bit argument to a C function was broken on BOTH backends for a
> month with no symptom other than a callback that never fired. **Nothing in
> the bare-metal suite calls into C, so nothing there could have caught it.**"*
> That target builds and runs on esp32c3 AND esp32s3 under the Espressif qemu —
> and it is skipping too, for want of IDF
> ([[task-s-install-esp-idf-to-turn-on-the-skipped-esp-execution-rows]]).
>
> **Revised plan — do this first, it is smaller than what follows:**
> 1. make `TargetIsEspClass` and the units' `PXX_ESP` **profile-aware**, so
>    xtensa-under-IDF behaves like riscv32-under-IDF (which is proven working);
> 2. [[bug-a-xtensa-cannot-lower-an-int64-to-float-conversion]] — measured to be
>    the next wall behind the guards, and already filed;
> 3. [[bug-a-xtensa-codegen-has-no-variant-support]] — already filed;
> 4. only then consider what, if anything, genuinely belongs behind
>    `PXX_ESP_BARE` for the bare profile.
>
> Everything below stands as the bare-profile measurement and is still the
> reference for the three guard layers; read it after the above.


Filed after the user pushed back on
[[feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle]]: *"builtins not
being complete for ESP is a minor issue, isn't it."* Measured rather than
argued, and the answer is yes — this is the cheap path to the same place.

## The wall, and why it looked structural

Every blocked xtensa ticket's gate names a test that needs the `builtin` unit,
and on an ESP-class target you get:

```
error: UpCase: builtin helper unavailable (needs the builtin unit; not on ESP)
error: Str: builtin unit not loaded
```

Read quickly, that says "the ESP targets cannot run this code". It does not.
There are **three independent layers**, each added at a different time, each
with a comment asserting the same thing, and none of them a hardware or ISA
fact:

| layer | where | shape |
| --- | --- | --- |
| 1. the units exclude their own bodies | `compiler/builtin/builtinheap.pas`, `builtin.pas` | 14 `{$ifndef PXX_ESP}` blocks — *"Not yet on ESP: file I/O, ... variant, float formatting"* |
| 2. the unit is never PULLED | `pasparser_prog.inc` | **21** `(not TargetIsEspClass)` guards on the `needsBuiltin` token triggers — *"ESP can't compile builtin"* |
| 3. the forwards are never REGISTERED | `pasparser_prog.inc:882` | *"File load, variant and float-format helpers are not on ESP yet"* — and note it is the **arch-only** spelling `(TargetArch <> TARGET_XTENSA) and (TargetArch <> TARGET_RISCV32)`, the one `util.inc`'s `TargetIsEspClass` header warns must not be confused with the profile-aware test |

Layer 2 is why the diagnostic is misleading: `FindProc('__pxxUpCase')` fails not
because the helper cannot exist but because nothing asked for the unit.

## Measured — what is actually left when the layers come off

Probe (scratch copies under `PXX_HOME`, plus a throwaway compiler build widening
the ESP softfloat pull; **both reverted**, fixedpoint back to `07fbc8c97b3c`):

- **`builtinheap` alone already works on bare, untouched.** AnsiString +
  concat builds for riscv32-bare (51652B) and xtensa-bare (44468B) today. The
  heap and managed-string runtime are not the problem.
- With layer 1 off, a Variant program compiles the variant bodies on both ESP
  targets and stops at **`__pxx_l2d not linked`** — i.e. the ordering point
  below, not an ESP wall.
- With layer 1 off **and** softfloat pulled alongside, riscv32 reaches
  `UpCase` (layer 2) and xtensa reaches
  **`target xtensa: Int64-to-float conversion not yet supported`** —
  [[bug-a-xtensa-cannot-lower-an-int64-to-float-conversion]], already filed.

So the residue is small and already known:

1. **softfloat must be pulled alongside `builtin` on ESP-class.** The on-demand
   scan added by [[bug-a-esp32c3-bare-profile-cannot-find-the-softfloat-repack-helper]]
   reads the **user program's** tokens, and `builtin`'s own variant/float
   bodies bring float code the program never mentions. That is unreachable
   **today** — verified: `Str(i, s)` on bare answers `Str: builtin unit not
   loaded`, so `builtin` cannot be pulled on ESP at all and the hole cannot
   open — but it opens the moment layer 2 comes off. Widen the ESP arm to
   `needsSoftFloat or needsBuiltin` as part of this work, not before.
2. [[bug-a-xtensa-cannot-lower-an-int64-to-float-conversion]] (filed).
3. [[bug-a-xtensa-codegen-has-no-variant-support]] (filed) — for the variant
   rows specifically.

## Why this rather than a hosted xtensa profile

[[feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle]] was filed to make
the blocked gates reachable, and its argument was that only a hosted profile
gets the RTL. That is true of the *hosted* RTL and **irrelevant if `builtin`
works on ESP** — the tests need `builtin`, not a POSIX platform. This route:

- touches guards and ifdefs rather than adding a target profile (that ticket's
  own estimate: 68 `TARGET_XTENSA` sites to audit, plus `IR_SYSCALL`);
- runs on the **real ESP image under the Espressif qemu fork**, which is what
  actually ships, instead of a Linux-ELF flavour of xtensa that no product uses;
- pairs with [[task-s-install-esp-idf-to-turn-on-the-skipped-esp-execution-rows]],
  which is a download.

The hosted profile keeps a separate, weaker justification (running the whole
`test_cross_*` corpus on xtensa the way riscv32 does) and should be re-ranked
accordingly, not treated as the unblock.

## Do it in layers, and keep the size discipline

The ESP exclusions are not all wrong: an ESP image pays for what it links, and
`{$ifndef PXX_ESP}` around **file I/O** is a genuine platform statement, while
the same directive around **variant and float formatting** is not. Take them
one group at a time — variant, then string/char helpers (UpCase/Pos/Move), then
float formatting — measuring image size at each step, and leave the ones that
are real platform facts alone. `test_esp_bare.pas` staying its current size is
the canary: the pull is on demand, so a program that uses none of this must pay
none of it.

## Gate

`test_div_by_zero_raises_on_every_target.pas` and
`test_cross_variant_payload_widths.pas` building for `--target=xtensa
--esp-profile=bare` and `--target=esp32c3 --esp-profile=bare`, and — with IDF
installed — running under the Espressif fork with UART output matching the
x86-64 oracle. Plus a float-free bare image unchanged in size, plus Track A's
usual gate.
