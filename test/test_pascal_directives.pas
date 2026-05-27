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

begin
  writeln(NativeCompiler);
  writeln(FreePascalIdentity);
  writeln(LocalDefine);
  writeln(LocalUndefine);
  writeln(NestedConditional);
  writeln(CommandLineDefine);
end.
