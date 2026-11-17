/* The privileged forms a kernel's arch headers spell (Nilix, ESP32-S3):
   compiled --target=esp32s3 --freestanding --emit-obj and checked by
   disassembly (tools/check_casm_xtensa.sh), since user-mode qemu cannot run
   them. One function per line so each is found by name. */
unsigned rd_ps(void) { unsigned v; __asm__ volatile("rsr.ps %0" : "=a"(v)); return v; }
void wr_ie(unsigned v) { __asm__ volatile("wsr.intenable %0; rsync" :: "a"(v) : "memory"); }
unsigned rd_cc(void) { unsigned v; __asm__ volatile("rsr %0, ccount" : "=a"(v)); return v; }
void wr_cmp(unsigned v) { __asm__ volatile("wsr %0, ccompare0" :: "a"(v)); }
unsigned xs_vb(unsigned v) { __asm__ volatile("xsr.vecbase %0" : "+a"(v)); return v; }
unsigned irq_off(void) { unsigned v; __asm__ volatile("rsil %0, 15" : "=a"(v) :: "memory"); return v; }
void irq_on(unsigned v) { __asm__ volatile("wsr %0, ps; rsync" :: "a"(v) : "memory"); }
void idle(void) { __asm__ volatile("waiti 0" ::: "memory"); }
unsigned tp(void) { unsigned v; __asm__ volatile("rur.threadptr %0" : "=a"(v)); return v; }
void set_tp(unsigned v) { __asm__ volatile("wur.threadptr %0" :: "a"(v)); }
void bars(void) { __asm__ volatile("memw\n\tisync\n\tesync\n\tdsync" ::: "memory"); }
unsigned excsave(void) { unsigned v; __asm__ volatile("rsr.excsave1 %0" : "=a"(v)); return v; }
