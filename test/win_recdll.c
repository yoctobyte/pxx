/* The callee for test/test_nt_dll_records.pas: records by value in and out of a
   DLL, built by test-windows with clang for x86_64-pc-windows-msvc and
   tools/vm/mkdll.py. Every function is self-contained (no relocations). */
typedef struct { int x, y; } P8;
typedef struct { short a; } P2;
typedef struct { int a, b, c; } P12;
typedef struct { double d; } PD;
typedef struct { float a, b; } PF;
__declspec(dllexport) long long take8(int k, P8 p) { return k * 1000 + p.x * 10 + p.y; }
__declspec(dllexport) int take2(P2 p, int k) { return p.a + k; }
__declspec(dllexport) long long take12(P12 p, int k, P12 q) { p.a = 99; return p.a + p.b * 10 + p.c * 100 + k * 1000 + q.c * 10000; }
__declspec(dllexport) double takeD(PD p, double s) { return p.d * s; }
__declspec(dllexport) double takeF(PF p) { return p.a + p.b; }
__declspec(dllexport) long long take6(int a, int b, int c, int d, P8 e, P12 f) { return a + b + c + d + e.x + e.y * 10 + f.c * 100; }
__declspec(dllexport) P8 ret8(int a, int b) { P8 r = {a, b}; return r; }
__declspec(dllexport) P12 ret12(int a, double s, int b) { P12 r = {a, (int)(s * 2), b}; return r; }
__declspec(dllexport) P2 ret2(short a) { P2 r = {(short)(a * 3)}; return r; }
