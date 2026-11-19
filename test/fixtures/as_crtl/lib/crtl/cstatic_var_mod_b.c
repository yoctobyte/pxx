/* Module B of the two-module static VARIABLE probe — see cstatic_var_mod_a.c.

   Same spelling, different object, initialised to 2 so a read bound to the
   wrong module is a wrong VALUE rather than an indistinguishable one. It has
   no setter on purpose: nothing in this module ever writes `v`, so if row 4
   ever reports anything but 2 the write came from module A's object through a
   shared row. */

static int v = 2;

/* Six, not three -- see cstatic_var_mod_a.c. */
static int arr[6] = { 2, 2, 2, 2, 2, 2 };

int mb_get(void)  { return v; }
int mb_size(void) { return (int)sizeof(arr); }
