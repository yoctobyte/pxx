---
prio: 40
---

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# advisory: demos#00 red at 98ed38202254 (auto-filed by twatch)

- **Type:** advisory (NOT a gate — nothing day-to-day depends on this path; a notice for the owning track) (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-22T00:45:59Z
- **Test source:** unknown (see repro commands)

## Repro
`tools/testmgr.py --tier full --job 'demos#00'` at 98ed382022547bbe6624c779ee024a3ad1dea518

## Range
bad `98ed38202254`, last good `23becd24b8e5`, 423 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ear: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError 
  FAIL  examples/net/httpdemo.pas  --   near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError 
  OK    examples/parallel/collatz.pas
  OK    examples/parallel/membw.pas
  FAIL  examples/parallel/pow.pas  --   near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError 
  OK    examples/parallel/primecount.pas
  FAIL  examples/player/player.pas  --   near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError 
  FAIL  examples/primes/sieve.pas  --   near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError 
  FAIL  examples/raytracer/raytracer_gui.pas  --   near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError 
  FAIL  examples/raytracer/raytracer.pas  --   near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError 
  FAIL  examples/sat/satdemo.pas  --   near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError 
  FAIL  examples/solitaire/console_solitaire.pas  --   near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError 
  FAIL  examples/solitaire_gui/solitaire_gui.pas  --   near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError 
  OK    examples/sudoku/sudoku_game.pas
  OK    examples/sudoku/sudoku.pas
  OK    examples/tk/uses_tkinter_and_configparser.pas
  FAIL  examples/tui/menudemo.pas  --   near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError 
  FAIL  examples/vm/vmdemo.pas  --   near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError 
=== demos: 7/35 built into build/demos/ (esp32 skipped — cross-only) ===
(demos is a dashboard, not a gate; FAILs -> file a ticket)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
