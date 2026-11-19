/* __attribute__((visibility("..."))) reaches the object's symbol table as
   gcc writes it: HIDDEN and PROTECTED on definitions, a hidden prototype
   holds for the definition after it, and data takes it too (rump repro
   s09: it was DEFAULT). The row compares readelf with gcc's output and
   links the object with c_visibility_attribute_main.c.
   bug-c-visibility-attribute-was-ignored */
__attribute__((visibility("hidden"))) int hid(void) { return 1; }
int proto_hid(void) __attribute__((visibility("hidden")));
int proto_hid(void) { return 2; }
__attribute__((visibility("protected"))) int prot(void) { return 3; }
int plain(void) { return hid() + proto_hid() + prot(); }
__attribute__((visibility("hidden"))) int hvar = 5;
int pvar = 6;
