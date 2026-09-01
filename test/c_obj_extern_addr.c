/* Taking the ADDRESS of an external routine, which xtensa refused outright.
   bug-a-the-address-of-an-external-routine-is-refused-on-i386-and-xtensa

   The refusal's suggested workaround -- "wrap it in a local routine" -- is not
   available to a C program that receives the pointer from a table it does not
   own, and sqlite's unix VFS builds exactly such a table.

   Both shapes are here because ONE of them is the control. `call_it` takes the
   address only; `just_call` calls without taking it. Every target must emit one
   more relocation naming the external for the first than for the second -- a
   row asserting only that the file compiles would pass on a backend that
   emitted no reference at all. */
extern int gcc_thing(int);

typedef int (*fn_t)(int);

int call_it(void) { fn_t f = gcc_thing; return f(1); }

int just_call(void) { return gcc_thing(2); }

void app_main(void) { }
