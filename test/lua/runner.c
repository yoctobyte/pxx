/* pxx lua test-suite runner (used by `make test-lua`, NOT the base gate).
 * Amalgamates crtl + the lua core/lib from library_candidates/lua/src (gitignored
 * 3rd-party scratch) and runs the lua program whose path is argv[1] (the Makefile
 * passes each test/lua/*.lua case directly), falling back to the legacy fixed
 * PXX_LUA_SCRIPT when run with no arg. Passing the path avoids a shared /tmp input
 * file that races under parallel test execution. The suite
 * stays distinct from `make test` so the base gate carries no 3rd-party
 * dependency; test-lua skips gracefully when the lua tree is absent.
 * Diagnostic markers some lua sources emit go to stderr (fd 2); the suite checks
 * stdout only, so they do not affect results. */
#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "math.c"
#include "locale.c"
#include "lapi.c"
#include "lcode.c"
#include "lctype.c"
#include "ldebug.c"
#include "ldo.c"
#include "ldump.c"
#include "lfunc.c"
#include "lgc.c"
#include "llex.c"
#include "lmem.c"
#include "lobject.c"
#include "lopcodes.c"
#include "lparser.c"
#include "lstate.c"
#include "lstring.c"
#include "ltable.c"
#include "ltm.c"
#include "lundump.c"
#include "lvm.c"
#include "lzio.c"
#include "lauxlib.c"
#include "lbaselib.c"
#include "lcorolib.c"
#include "ldblib.c"
#include "liolib.c"
#include "lmathlib.c"
#include "loadlib.c"
#include "loslib.c"
#include "lstrlib.c"
#include "ltablib.c"
#include "lutf8lib.c"
#include "linit.c"

#define PXX_LUA_SCRIPT "/tmp/pxx_lua_input.lua"

extern long __pxx_write(int, const void *, unsigned long);
static unsigned long slen(const char *s){ unsigned long n=0; while(s[n]) n++; return n; }
static void emit(const char *s){ __pxx_write(2, s, slen(s)); }

int main(int argc, char **argv) {
  const char *inpath = (argc > 1) ? argv[1] : PXX_LUA_SCRIPT;
  lua_State *L;
  L = luaL_newstate();
  luaL_openlibs(L);
  if (luaL_loadfile(L, inpath) != 0) {
    emit("LOAD-ERR "); { const char *e=lua_tostring(L,-1); if(e) emit(e); } emit("\n"); return 4;
  }
  if (lua_pcall(L, 0, 0, 0) != 0) {
    emit("RUN-ERR "); { const char *e=lua_tostring(L,-1); if(e) emit(e); } emit("\n"); return 5;
  }
  lua_close(L);
  return 0;
}
