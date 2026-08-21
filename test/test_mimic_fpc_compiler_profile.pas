program test_mimic_fpc_compiler_profile;
{ --mimic-fpc-compiler: the build-config define profile FPC's own makefile
  injects when it compiles FPC's COMPILER
  (feature-mimic-fpc-compiler-define-profile).

  FPC's compiler is not standalone source. Every unit begins
  `{$i fpcdefs.inc}`, and that include is a pure derivation from ONE build-time
  define — the CPU. Without it every branch is dead and the include resolves to
  a configuration with no CPU class at all, which is why plain `--mimic-fpc`
  could not get through the FPC compiler tree.

  Three properties, and the third is the one worth having a test for:

  1. The FPC identity defines are still there. The profile IMPLIES --mimic-fpc;
     an early version guarded that call and produced something strictly WORSE
     than plain --mimic-fpc — `unix` went missing, so fpcdefs.inc's
     cpawaremessages gate died while the CPU gates came alive. Half a profile
     is worse than none, so `fpc` and `unix` are asserted here.

  2. The CPU define follows --target, not the host. `x86_64` / `i386` /
     `aarch64` / `arm` are FPC's own spellings, deliberately not the CPUxxx
     family (a different, RTL-facing set that FPC's compiler build does not
     use).

  3. NOTHING ELSE is defined. `cpu64bitalu` is the canary: it is one of ~40
     names fpcdefs.inc DERIVES, and the flag must not hand it over directly.
     Hand-listing the derived set would be a second copy of FPC's own
     derivation — wrong the day upstream changes it, and wrong silently. The
     `derived-leak=` line must never appear.

  Verified against the oracle when this landed: pxx under this flag and a real
  `fpc -dx86_64` agree on all seven probed derivations of FPC 3.2.2's
  fpcdefs.inc (cpu64bitalu, cpu64bitaddr, x86, cpuextended, USEINLINE,
  cpawaremessages, cputargethasfixedstack). That check needs the FPC compiler
  tree, so it is not reproducible here; this test guards the interface it rests
  on. }

begin
{$ifdef FPC}
  WriteLn('fpc=yes');
{$else}
  WriteLn('fpc=NO');
{$endif}
{$ifdef UNIX}
  WriteLn('unix=yes');
{$else}
  WriteLn('unix=NO');
{$endif}
{$ifdef x86_64}
  WriteLn('cpu=x86_64');
{$endif}
{$ifdef i386}
  WriteLn('cpu=i386');
{$endif}
{$ifdef aarch64}
  WriteLn('cpu=aarch64');
{$endif}
{$ifdef arm}
  WriteLn('cpu=arm');
{$endif}
{$ifdef cpu64bitalu}
  WriteLn('derived-leak=cpu64bitalu');
{$endif}
  WriteLn('end');
end.
