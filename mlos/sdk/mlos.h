#ifndef MLOS_SDK_H
#define MLOS_SDK_H
#include "syscalls.h"
#ifndef MLOS_SDK_IMPLEMENTATION
#define main mlos_program_main
#endif
typedef unsigned char u8;
typedef unsigned int u16;
typedef unsigned long u32;
void *malloc(u16 size);
void free(void *pointer);
void *calloc(u16 count, u16 size);
void *realloc(void *pointer, u16 size);
int mlos_argc(void);
char **mlos_argv(void);
u16 get16(const u8 *p);
void put32(u8 *p, u32 v);
u32 get32(const u8 *p);
extern u8 std_infile, std_outfile;
extern u16 std_infd, std_outfd;
int kstdio_start(int argc, char **argv);
void kstdio_close(void);
int kerror(int result);
int kword(u16 call, u16 value);
void kyield(void);
void ksleep(u32 ticks);
void kexit(int status);
int kread(u8 descriptor, void *data, u16 count);
int klog(const void *data, u16 count);
int kwrite(const void *data, u16 count);
int kspawn(const char *name, u8 priority, u8 argc, const char **argv);
int kwait(u16 pid);
int ksend(u16 handle, const void *data, u16 count);
int kreceive(u16 handle, void *data, u16 capacity);
int klisten(const char *name);
int kconnect(const char *name, u16 *tx, u16 *rx);
int kaccept(u16 listener, u16 *tx, u16 *rx);
int kclose(u16 handle);
int kwait_one(u16 handle);
#endif
