---
prio: 70
track: C
---

> **Track guessed as C** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:tools/crtl_reachability.py red at 98ed38202254 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-22T00:45:59Z
- **Test source:** tools/crtl_reachability.py tools/gen_crtl_map.py +2

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:tools/crtl_reachability.py'` at 98ed382022547bbe6624c779ee024a3ad1dea518

## Range
bad `98ed38202254`, last good `23becd24b8e5`, 423 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:4790: error: undefined variable (PXXVariantErrorHook)
(tail)
rror: undefined variable (PXXVariantErrorHook)
      in: stable_linux_amd64/default/../../lib/rtl/sysutils.pas
      near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError
lib-units: FAIL tempfile
    pascal26:4790: error: undefined variable (PXXVariantErrorHook)
      in: stable_linux_amd64/default/../../lib/rtl/sysutils.pas
      near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError
lib-units: FAIL testutils
    pascal26:4790: error: undefined variable (PXXVariantErrorHook)
      in: stable_linux_amd64/default/../../lib/rtl/sysutils.pas
      near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError
lib-units: FAIL tls13_native
    pascal26:4790: error: undefined variable (PXXVariantErrorHook)
      in: stable_linux_amd64/default/../../lib/rtl/sysutils.pas
      near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError
lib-units: FAIL truststore
    pascal26:4790: error: undefined variable (PXXVariantErrorHook)
      in: stable_linux_amd64/default/../../lib/rtl/sysutils.pas
      near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError
lib-units: FAIL variants
    pascal26:4790: error: undefined variable (PXXVariantErrorHook)
      in: stable_linux_amd64/default/../../lib/rtl/sysutils.pas
      near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError
lib-units: FAIL vm
    pascal26:4790: error: undefined variable (PXXVariantErrorHook)
      in: stable_linux_amd64/default/../../lib/rtl/sysutils.pas
      near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError
lib-units: FAIL x509
    pascal26:4790: error: undefined variable (PXXVariantErrorHook)
      in: stable_linux_amd64/default/../../lib/rtl/sysutils.pas
      near: PXXNilRefHook   SysRaiseAccessViolation  PXXVariantErrorHook >>>   SysRaiseVariantError

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
