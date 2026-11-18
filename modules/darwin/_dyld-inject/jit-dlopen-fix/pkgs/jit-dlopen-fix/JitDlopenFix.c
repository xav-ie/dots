#include <pthread.h>
#include <dlfcn.h>
static __thread int tracked, last;
static void my_wp(int e){ tracked=1; last=e; pthread_jit_write_protect_np(e); }
static void restore(void){ if(tracked) pthread_jit_write_protect_np(last); }
static void*my_dlopen(const char*p,int m){ void*r=dlopen(p,m); restore(); return r; }
static int my_dlclose(void*h){ int r=dlclose(h); restore(); return r; }
static bool my_preflight(const char*p){ bool r=dlopen_preflight(p); restore(); return r; }
__attribute__((used,section("__DATA,__interpose"))) static struct{const void*n,*o;} ip[]={
 {(const void*)my_wp,(const void*)pthread_jit_write_protect_np},
 {(const void*)my_dlopen,(const void*)dlopen},
 {(const void*)my_dlclose,(const void*)dlclose},
 {(const void*)my_preflight,(const void*)dlopen_preflight}};
