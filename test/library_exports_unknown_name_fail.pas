{ MUST NOT COMPILE. `exports` naming something that is not a routine here.
  Silently dropping it writes a library missing a symbol its own source claimed
  to provide, and the failure lands at someone else's link step. }
library library_exports_unknown_name_fail;
exports PxxLibNotDeclaredAnywhere;
begin
end.
