{ The POSITIVE CONTROL for test_pascal_nested_comment_directive.pas: this file
  is really included, so the test proves the include pre-pass was LIVE. Without
  it, "no error about a missing include" is also what a pass that never ran
  prints. }
const NC_LIVE = 'live';
