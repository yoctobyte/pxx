/* pxx cJSON test-suite runner (used by `make test-cjson`, NOT the base gate).
 * Amalgamates crtl + cJSON from library_candidates/cjson/src (gitignored 3rd-party
 * scratch) and round-trips a JSON document: read the file at PXX_CJSON_INPUT,
 * cJSON_Parse it, then cJSON_PrintUnformatted the result back to stdout. The
 * Makefile copies each test/cjson/*.json case to that fixed path (C argv is not
 * wired yet) and diffs stdout against the committed *.expected oracle.
 *
 * The round-trip is the free oracle: parse + canonical re-serialize exercises the
 * parser, object/array structs, heap (malloc/realloc/free), string handling, and
 * the number print path. Float number output additionally needs sscanf in crtl
 * (cJSON re-parses its own %g output to check round-trip precision); the first
 * fixtures stay integer/string/bool/null to isolate the frontend from that gap.
 *
 * Distinct from `make test`: the base gate carries no 3rd-party dependency, and
 * test-cjson skips gracefully when the cJSON tree is absent. */
#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "math.c"
#include "locale.c"
#include "cJSON.c"

#define PXX_CJSON_INPUT "/tmp/pxx_cjson_input.json"
#define PXX_CJSON_MAX   (256 * 1024)

extern long __pxx_write(int, const void *, unsigned long);
static unsigned long slen(const char *s){ unsigned long n=0; while(s[n]) n++; return n; }
static void out(const char *s){ __pxx_write(1, s, slen(s)); }
static void err(const char *s){ __pxx_write(2, s, slen(s)); }

static char input[PXX_CJSON_MAX];

int main(void) {
  FILE *f = fopen(PXX_CJSON_INPUT, "rb");
  size_t n;
  cJSON *root;
  char *printed;

  if (f == NULL) { err("OPEN-ERR\n"); return 2; }
  n = fread(input, 1, PXX_CJSON_MAX - 1, f);
  fclose(f);
  input[n] = '\0';

  root = cJSON_Parse(input);
  if (root == NULL) {
    err("PARSE-ERR\n");
    return 3;
  }

  printed = cJSON_PrintUnformatted(root);
  if (printed == NULL) {
    err("PRINT-ERR\n");
    cJSON_Delete(root);
    return 4;
  }

  out(printed);
  out("\n");

  cJSON_free(printed);
  cJSON_Delete(root);
  return 0;
}
