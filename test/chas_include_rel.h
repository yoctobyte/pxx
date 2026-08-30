/* Sole purpose: exist, so `__has_include("chas_include_rel.h")` in
   test/chas_include.c can prove the quoted form resolves relative to the
   including file rather than only from -I roots. */
#define CHAS_INCLUDE_REL_SEEN 1
