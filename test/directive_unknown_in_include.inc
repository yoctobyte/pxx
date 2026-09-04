{ Include half of test_pascal_directive_unknown_in_include.pas. The unknown
  directive below is on line 4 of THIS file, and 4 is what the diagnostic must
  name -- the include's OWN line, not the line it was pasted onto. }
{$bogusinsideinclude}
const FromInclude = 7;
