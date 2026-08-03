/* The other half: with NO declaration at all there is no C function to prefer,
   so the call must be REFUSED and name the collision — binding it compiles a
   call whose arguments cannot arrive.
   bug-cfront-c-name-binds-to-pascal-routine-at-wrong-arity */

int cnsf_probe_time(void) {
  long long now = 0;
  long long r = time(&now);
  return (now != 0) && (now == r);
}
