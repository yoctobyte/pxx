{ SPDX-License-Identifier: 0BSD }
program test_interrupts_pascal_no_pylib;
{ A PASCAL program using interrupts must not link the Python runtime.
  interrupts.pas compiles its Python surface (and its `uses pylib`) only under
  PXX_NILPY, which the compiler sets for NilPy compilations. The Makefile row
  builds this file twice -- plain, and with -dPXX_NILPY as the positive control
  that the Python half is what costs the bytes -- and asserts the plain build
  is under half the other. Measured 2026-09-24, x86-64: 31,800 B plain against
  410,108 B with the define. On xtensa the difference decides whether a Pascal
  ESP program links at all without --xtensa-long-calls (examples/esp32/pwm-s3). }
uses interrupts;

procedure Handler(const e: TIntEvent);
begin
  writeln('event ', e.Id);
end;

begin
  IntOnEvent(INT_SRC_TEST, @Handler);
  IntPush(INT_SRC_TEST, 7);
  IntPoll;
end.
