---
sha: afafdddf8225f76e7ac9912a2b7436787b846893
parent_tested: 302a666b2e33f2222feb4726e339e10e2df36c10
date: 2026-08-21T06:44:08Z
host: plexus
tier: native
wall: 462.5
scale: 1.0
verdict: RED
compiler_sha256: d275f6e04592e28fe87244af8ac4025ecc6eb973c30a0eb8f424dc49c9e3bd27
---

## STILL-RED
- test-core#src:test/test_delphi_bare_alldefaulted_arg.pas — test/test_delphi_bare_alldefaulted_arg.pas
  - `ok: $TMP  [code=59792B  data=1888B  bss=42492B  procs=122] | Segmentation fault (core dumped)`
- test-core#src:test/test_mode_delphi.pas — test/test_mode_delphi.pas
  - `pascal26:25: warning: bare own name 'Gate' reads the result of parameterless function Gate; write Gate() for a recursive call, or Result to read the result | pa`
- test-core#src:test/test_mode_delphi_callarg.pas — test/test_mode_delphi_callarg.pas
  - `pascal26:51: error: undefined variable (Dbl) | near:  ApplyFn=  ApplyFn  Dbl >>>`
- test-core#src:test/test_mode_delphi_methptr.pas — test/test_mode_delphi_methptr.pas
  - `pascal26:39: error: "TCounter.Add" is a procedure and has no result to use in an expression | near:  e  c  Add >>>  e`
- test-core#src:test/test_procvar_value_context.pas — test/test_procvar_value_context.pas
  - `ok: $TMP  [code=59609B  data=1608B  bss=42516B  procs=126]`
- test-core#src:test/test_record_helper_for_string_b331.pas — test/test_record_helper_for_string_b331.pas
  - `pascal26:71: error: undefined variable (BITS) | near:  Writeln  bits:     BITS >>>   end`

## first failure: test-core#src:test/test_record_helper_for_string_b331.pas — test/test_record_helper_for_string_b331.pas (fail)
repro: `tools/testmgr.py --tier native --job 'test-core#src:test/test_record_helper_for_string_b331.pas'` at afafdddf8225f76e7ac9912a2b7436787b846893
```
(diagnostics)
pascal26:71: error: undefined variable (BITS)
(tail)
pascal26:71: error: undefined variable (BITS)
  near:  Writeln  bits:     BITS >>>   end 

```
