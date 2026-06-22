/* Tiny C library for the {$LAZYCASING} test. The Pascal side declares this with
   the exact spelling `add_two` and then calls it with mismatched case under
   {$LAZYCASING ON}; the compiler must resolve to this exact linker symbol. */
int add_two(int a, int b) { return a + b; }
