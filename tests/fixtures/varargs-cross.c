/* Each exit code names the case that failed; see run-varargs-cross-test.sh. */
#include <stdarg.h>
extern long n_sum(int, ...);
extern long n_copy(int, ...);
extern long n_list(int, va_list);
long c_list(int n, va_list ap){ long t=0; for(int i=0;i<n;i++){ t+=va_arg(ap,int); t+=(long)va_arg(ap,double);} return t; }
long fwd(int n, ...){ va_list ap; va_start(ap,n); long r=n_list(n,ap); va_end(ap); return r; }
static void bye(long c){
#if defined(__x86_64__)
 __asm__("mov %0,%%rdi; mov $60,%%rax; syscall"::"r"(c):"rdi","rax");
#elif defined(__aarch64__)
 register long x0 __asm__("x0")=c; register long x8 __asm__("x8")=93; __asm__("svc 0"::"r"(x0),"r"(x8));
#else
 register long a0 __asm__("a0")=c; register long a7 __asm__("a7")=93; __asm__("ecall"::"r"(a0),"r"(a7));
#endif
 for(;;);
}
void cstart(void){
  long r = n_sum(12, 1,1.0,2,2.0,3,3.0,4,4.0,5,5.0,6,6.0,7,7.0,8,8.0,9,9.0,10,10.0,11,11.0,12,12.0);
  long r2 = n_sum(1, 40, 2.0);
  long r3 = n_copy(12, 1,1.0,2,2.0,3,3.0,4,4.0,5,5.0,6,6.0,7,7.0,8,8.0,9,9.0,10,10.0,11,11.0,12,12.0);
  long r4 = fwd(12, 1,1.0,2,2.0,3,3.0,4,4.0,5,5.0,6,6.0,7,7.0,8,8.0,9,9.0,10,10.0,11,11.0,12,12.0);
  bye(r==156 ? (r2==42 ? (r3==312 ? (r4==156 ? 0 : 4) : 3) : 2) : 1);
}
#if defined(__x86_64__)
__asm__(".globl _start\n_start: and $-16,%rsp\n call cstart\n");
#else
void _start(void){ cstart(); }
#endif
