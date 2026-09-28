---
slug: bug-a-the-33rd-parameter-crashes-the-compiler
track: A
prio: 55
type: bug
status: done
owner: ""
created: 2026-09-28
found-by: frankD (writing test_xtensa_call0_wide_argument_block.pas with 40 parameters)
tags: [core, limits, crash]
blocked-by: []
summary: "A routine, method or procedural type with more parameters than MAX_PROC_PARAMS (32, counting a method's Self) crashed the compiler, SIGSEGV with no diagnostic, on ordinary Pascal at the shipped cap. Each declaration parser wrote the 33rd name past a 32-slot staging array. It is now refused: `too many parameters (33, max 32, counting Self for a method)`, from one helper, CheckParamCap, asked before every append and before each implicit Self shift. The cap itself is unchanged (bug-a-max-proc-params-is-coupled-to-a-hardcoded-array-bound-by-a-comment)."
---

# The 33rd parameter crashes the compiler

`function F(a0, ..., a32: Integer)` was rc 139 on pin v448, with no message.
So were a class method with 32 declared parameters (plus Self), a procedural
type with 33, an interface method with 32 and an advanced-record method with
32.

## Fix

`CheckParamCap(have)` (symtab.inc) refuses when `have >= MAX_PROC_PARAMS`,
naming the count and the cap. It is called before each parameter-name append
and before each implicit-Self shift, in all eight places:

- pasparser_proc.inc: the routine's name loop, and the method Self shift.
- pasparser_decl.inc: procedural types (7117), interface methods (8061) and
  their Self shift, class methods (8911) and their Self shift, and record
  methods (5672). The record site had a guard whose message gave no numbers;
  it now uses the helper.

The places were found from the concept (every `CurTok.SVal; Inc(` append of
a parameter name, and every `downto 1` Self shift), not from callers of an
existing guard.

## Not crashes, left alone

- The C frontend refuses a 33-parameter function definition. Its
  function-pointer staging (cparser.inc 6420, 6969, 18557) instead DROPS
  parameters past 32 without a message. That is a silent truncation, a
  different defect, recorded in the max-proc-params ticket.
- Nil Python refuses both a def and a lambda past the cap.
- Calls with too many arguments are refused by overload resolution, and 40
  WriteLn arguments compile. A 40-argument varargs call gives an
  IR_UNSUPPORTED refusal. That message is unhelpful, but it is not a crash.

## Test

- `test/test_param_cap_{routine,method,proctype}_fail.pas`: each is refused
  with exactly one `too many parameters (33, max 32` message. The pinned v448
  binary SIGSEGVs on the routine file.
- `test/test_param_cap_at_the_limit.pas`: 32 on a routine and a procedural
  type, 31 plus Self on a method. It compiles and runs, and its output equals
  FPC 3.2.2's on x86-64 and on i386.

Found on the way: bug-p-a-procvar-named-like-a-routine-calls-nil.
