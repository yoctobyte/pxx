/* An ESP object that exports MORE than app_main.
   bug-a-the-esp-object-writer-exports-only-app-main-so-no-cdecl-routine-or-global-is-linkable

   The xtensa/riscv32 object writer emitted exactly one global symbol --
   app_main -- with every proc LOCAL FUNC and no data symbol planned at all.
   That is the ESP-IDF component shape and the LOCAL choice is a deliberate
   guard against name collisions inside an IDF build, so what is exported now
   is exactly what the programmer MARKED: nothing else moves.

   app_main is DEFINED here on purpose. The writer emits its own GLOBAL
   `app_main` at the program entry, so a source that also defines one used to
   put two GLOBAL definitions of the same name in one object at different
   values -- measured, before ObjEspProcIsExported excluded it. */
int esp_helper(int a) { return a + 1; }

int EspVal = 7;

void app_main(void) { }
