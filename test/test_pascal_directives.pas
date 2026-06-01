program TestPascalDirectives;

{$mode objfpc}

{$ifdef PXX}
const NativeCompiler = 1;
{$else}
const NativeCompiler = 0;
{$endif}

{$ifdef FPC}
const FreePascalIdentity = 1;
{$else}
const FreePascalIdentity = 0;
{$endif}

{$define LOCAL_FLAG}
{$ifdef local_flag}
const LocalDefine = 1;
{$else}
const LocalDefine = 0;
{$endif}
{$undef LOCAL_FLAG}
{$ifndef local_flag}
const LocalUndefine = 1;
{$else}
const LocalUndefine = 0;
{$endif}

{$ifdef MISSING_OUTER}
const NestedConditional = 0;
{$ifdef PXX}
const ExcludedNested = 0;
{$endif}
{$else}
{$ifdef PXX}
const NestedConditional = 1;
{$else}
const NestedConditional = 0;
{$endif}
{$endif}

{$ifdef CLI_FLAG}
const CommandLineDefine = 1;
{$else}
const CommandLineDefine = 0;
{$endif}

{$ifdef CPU64}
const Cpu64Target = 1;
{$else}
const Cpu64Target = 0;
{$endif}

{$ifdef CPUX86_64}
const CpuX8664Target = 1;
{$else}
const CpuX8664Target = 0;
{$endif}

{$ifdef LINUX}
const LinuxTarget = 1;
{$else}
const LinuxTarget = 0;
{$endif}

{$if defined(PXX) and not defined(MISSING_EXPR)}
const ExpressionConditional = 1;
{$elseif defined(FPC)}
const ExpressionConditional = 0;
{$else}
const ExpressionConditional = 0;
{$endif}

{$if defined(MISSING_EXPR)}
{$error inactive error must not fire}
const ElseIfConditional = 0;
{$elseif 1}
const ElseIfConditional = 1;
{$else}
const ElseIfConditional = 0;
{$endif}

{$if (defined(MISSING_EXPR) or defined(PXX)) and 1}
const ParenthesizedOrConditional = 1;
{$else}
const ParenthesizedOrConditional = 0;
{$endif}

begin
  writeln(NativeCompiler);
  writeln(FreePascalIdentity);
  writeln(LocalDefine);
  writeln(LocalUndefine);
  writeln(NestedConditional);
  writeln(CommandLineDefine);
  writeln(Cpu64Target);
  writeln(CpuX8664Target);
  writeln(LinuxTarget);
  writeln(ExpressionConditional);
  writeln(ElseIfConditional);
  writeln(ParenthesizedOrConditional);
end.
