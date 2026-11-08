#include "lua-macros.h"
const char lm_ident[] = "ident";
int lm_table[3] = {4, 5, 6};
int lm_call (lm_handler h) { return h == LM_DFL ? 1 : 0; }
