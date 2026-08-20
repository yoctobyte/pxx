/* Sentinel bodies for the own-language-first tests. Every value is one no real
   implementation would return, so a passing row can never be a coincidence.

   `exp` and `sqrt` are Pascal INTRINSIC spellings case-insensitively; `cube`
   has no Pascal twin and is the reachability control.
   feature-a-own-language-first-symbol-resolution */

double exp(double x)  { return 42.0; }
double sqrt(double x) { return 43.0; }
int    cube(int x)    { return 999; }
