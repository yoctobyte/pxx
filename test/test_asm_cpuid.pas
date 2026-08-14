program TestAsmCpuid;
{ feature-inline-asm-xmm-operands, phase 2: CPU feature discovery from a Pascal
  inline `asm ... end` block — `cpuid`, `xgetbv`, `rdtsc`.

  These land before any vector opcode on purpose. They are what makes RUNTIME
  ISA dispatch possible at all: a program can only choose between a GP kernel, an
  SSE kernel and an AVX kernel if it can ask the machine what it has. Without
  them the later phases produce instructions nobody can safely reach.

  Everything asserted here is machine-INDEPENDENT. The obvious test — compare the
  vendor string to "GenuineIntel" — passes on the box that wrote it and fails on
  every AMD one, which is a worse outcome than not testing. So this pins
  invariants that hold on any x86-64 CPU capable of running the binary at all.

  Encodings were checked against gas separately: cpuid = 0F A2,
  xgetbv = 0F 01 D0, rdtsc = 0F 31. }

var failures: Integer;

procedure Fail(const what: AnsiString);
begin
  WriteLn('FAIL ', what);
  failures := failures + 1;
end;

var
  maxLeaf, b, c, d, feat: Integer;
  lo1, lo2: Integer;
  vendor: AnsiString;
  i, ch: Integer;
  sse2ok: Boolean;

begin
  failures := 0;

  { Leaf 0: eax = highest leaf supported, ebx:edx:ecx = the 12-byte vendor
    string. Note the order — ebx, then EDX, then ecx — which is a classic
    off-by-one-register trap and worth spelling out. }
  maxLeaf := 0; b := 0; c := 0; d := 0;
  asm
    mov eax, 0
    cpuid
    mov maxLeaf, eax
    mov b, ebx
    mov d, edx
    mov c, ecx
  end;

  { Any CPU running this supports at least leaf 1, which is where the feature
    bits live. A zero here means cpuid did not execute or the result never
    reached the variable. }
  if maxLeaf < 1 then Fail('cpuid leaf 0 reports maxLeaf < 1');

  vendor := '';
  for i := 0 to 3 do vendor := vendor + Chr((b shr (i * 8)) and $FF);
  for i := 0 to 3 do vendor := vendor + Chr((d shr (i * 8)) and $FF);
  for i := 0 to 3 do vendor := vendor + Chr((c shr (i * 8)) and $FF);

  { 12 bytes, all printable ASCII. True for GenuineIntel, AuthenticAMD and every
    hypervisor spelling, and false for the register-never-loaded case, which is
    the failure this actually guards. }
  if Length(vendor) <> 12 then Fail('vendor string is not 12 bytes');
  for i := 1 to Length(vendor) do
  begin
    ch := Ord(vendor[i]);
    if (ch < 32) or (ch > 126) then Fail('vendor string has a non-printable byte');
  end;

  { Leaf 1: edx bit 26 = SSE2. x86-64 REQUIRES SSE2, so on any machine that can
    run this 64-bit binary the bit must be set — a genuinely universal assertion
    rather than a property of this box. }
  feat := 0;
  asm
    mov eax, 1
    cpuid
    mov feat, edx
  end;
  sse2ok := ((feat shr 26) and 1) = 1;
  if not sse2ok then Fail('leaf 1 edx bit 26 (SSE2) clear on an x86-64 CPU');

  { rdtsc: edx:eax = the timestamp counter. It is monotonic, so a second read
    must not be below the first. Comparing only the LOW half would be wrong at a
    32-bit wrap, so tolerate lo2 < lo1 and treat it as a wrap rather than a
    failure — the point is that the instruction executed and produced something
    that moves, not a precise timing claim. }
  lo1 := 0; lo2 := 0;
  asm
    rdtsc
    mov lo1, eax
  end;
  for i := 1 to 1000 do maxLeaf := maxLeaf + i;   { burn a little time }
  asm
    rdtsc
    mov lo2, eax
  end;
  if lo1 = lo2 then Fail('rdtsc returned the same value twice');

  { xgetbv is deliberately NOT executed here. It faults with #UD unless
    CR4.OSXSAVE is set, which is itself discovered through leaf 1 ecx bit 27, so
    running it unconditionally would crash the test on older or restricted
    machines. Its ENCODING is verified against gas in the ticket; a program that
    wants it must gate on OSXSAVE first, and that is the correct usage this test
    should not undermine by demonstrating the wrong one. }

  if failures = 0 then WriteLn('asm cpuid ok')
  else WriteLn('asm cpuid FAILED ', failures);
end.
