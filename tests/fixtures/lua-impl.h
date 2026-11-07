/* A header whose functions a Nucleus file defines (nuc-lua ISSUE-013): the
   defining file is imported, not the entry, and one function is variadic. */
int li_add(int a, int b);
int li_sum(int n, ...);
