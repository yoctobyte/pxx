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
/* Callbacks into the program (test/test_nt_dll_callbacks.pas): called with the
   Microsoft convention, floats positional in xmm0-3, arguments 5+ on the stack.
   Every float comes in from the caller: a constant here would be an .rdata
   relocation. */
typedef double (*FD)(double, int, double);
__declspec(dllexport) double cb_mixed(FD f, double a, double b) { double r = f(a, 3, b); return r + r; }
typedef long long (*F6)(long long, long long, long long, long long, long long, long long);
__declspec(dllexport) long long cb_six(F6 f) { return f(1, 2, 3, 4, 5, 6); }
typedef double (*F6M)(int, double, int, double, int, double);
__declspec(dllexport) double cb_six_mixed(F6M f, double b, double d, double g) { return f(1, b, 2, d, 3, g); }
typedef float (*FS)(float, float);
__declspec(dllexport) double cb_single(FS f, float a, float b) { return f(a, b); }
