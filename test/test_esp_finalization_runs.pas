{ SPDX-License-Identifier: Zlib }
program test_esp_finalization_runs;
{ Unit finalization runs on the ESP profile, so anything built on it does too --
  NilPy's atexit, and every `finalization` in lib/rtl. The unit under test is
  test/esp_finalization_unit.pas and the reasoning is in its header.

  The LAST line is the one that matters: 'FIN-PROBE finalization ran' is printed
  after the main body has ended, so a harness that stops capturing at the end of
  the top level will lose it and report a false gap. That is exactly what
  happened to a NilPy atexit sweep on 2026-09-28. Read to the end of the output.

  The oracle is a fixed file rather than the x86-64 output, so the row cannot
  pass by comparing two identically-broken runs.

  MEASURED 2026-09-28 (frankz-e5), esp32c3 AND esp32s3 under QEMU, at tree
  3109649ec4, compiler binary 8d5d0f2653f0 -- the fixedpoint this tree
  reproduces, and NOT v450's own pin c19cc2d531e4. Re-confirmed on both chips at
  e4c44532a2, binary f545c8410b32, after a rebase over 21 commits -- the run was
  on that commit's local-only pre-rebase twin, which touches no compiler source,
  so the binary and therefore the measurement are the same. Both
  chips printed all four lines and matched this file exactly:

    FIN-PROBE init
    touch
    FIN-PROBE main done
    FIN-PROBE finalization ran

  Desktop x86-64 is identical, which is the comparison that makes it meaningful:
  the ESP profile is not a reduced exit path here. }
uses esp_finalization_unit;
begin
  Touch;
  WriteLn('FIN-PROBE main done');
end.
