{ Depth 2. Its own include is written WITHOUT a directory, so it can only
  resolve if the inner expansion searches THIS file's directory rather than the
  including program's — the incDir computation in ExpandIncludes. }
{$I n_level3.inc}
const NEST_L2 = 'l2';
{$ifdef NEVER_DEFINED}
{$I no_such_file_anywhere.inc}   { in a dead branch: must not even be opened }
{$endif}
