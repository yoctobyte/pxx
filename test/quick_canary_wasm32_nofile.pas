{ THE NEGATIVE CONTROL for the wasm32 quick-tier canary in `make test-quick`.

  Its whole job is to touch NO file, so that the emitted wasm32 module must not
  carry a `path_open` import. The positive arm greps a binary for that string;
  a grep that cannot come back false is not a check, and this is what makes it
  able to.

  So: do not add file, directory or command-line I/O to this program, and do not
  "enrich" it. A WriteLn is safe (fd_write, not path_open) and is here only so
  the program has a body the backend must actually lower. If this ever starts
  importing path_open, the canary beside it has silently stopped testing
  anything while still printing nothing. }
program quick_canary_wasm32_nofile;
begin
  WriteLn('qc_wasm32 nofile');
end.
