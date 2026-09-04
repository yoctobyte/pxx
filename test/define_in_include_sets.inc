{ Sets a define for its INCLUDER to branch on -- the classic config-include
  pattern. The define is part of the includer's textual state, not a scope of
  its own: fpc has no per-include rollback and neither may we. }
{$DEFINE PXX_DEFINE_FROM_INCLUDE}
