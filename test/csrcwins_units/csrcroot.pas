unit csrcroot;
{ THE CONTROL, and it is why this fixture is two names and not one. It lives
  ONLY in the search root, with no .c beside the program, so it can be answered
  only by the -Fu stage. Without it, `pick 111` is equally consistent with "the
  search root was never searched at all" -- a different defect with the same
  output. This row says the root IS on the chain, which is what makes the other
  row an ORDERING result. }
interface
function RootOnly: Integer;
implementation
function RootOnly: Integer; begin RootOnly := 333; end;
end.
