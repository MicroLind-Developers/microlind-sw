#include "syscalls.h"
/* S05 supplies the general program runtime. This linked diagnostic has only a
   fixed entry stub, BSS initialized by CMOC, and an explicit bounded stack. */
int main(void)
{
    unsigned char params[6];
    unsigned char info[4];
    unsigned char result[4];
    const unsigned char source[4] = {'C','M','O','C'};
    unsigned int handle;
    if (mlos_call(SYS_PROBE, 0) != ABI_VERSION) return 1;
    if (mlos_call(255, 0) != SYS_ENOSYS) return 2;
    if (mlos_call(256, 0) != SYS_EINVAL) return 8;
    if (mlos_call(SYS_ENTRY_TEST, 0) != 0x6309) return 9;
    mlos_put_u16(params, (unsigned int)info);
    if (mlos_call(SYS_MEMORY_INFO, params) != 0 || info[0] != 32 || info[1] != 3 || info[2] != 28 || info[3] != 1) return 3;
    handle = (unsigned int)mlos_call(SYS_BANK_ALLOC, 0);
    mlos_put_u16(params, handle);
    params[2] = 1;
    if (mlos_call(SYS_BANK_MAP, params) != 0) return 4;
    params[0] = 1;
    if (mlos_call(SYS_BANK_UNMAP, params) != 0) return 10;
    mlos_put_u16(params, handle);
    params[2] = 1;
    if (mlos_call(SYS_BANK_MAP, params) != 0) return 11;
    mlos_put_u16(params, (unsigned int)source);
    mlos_put_u16(params + 2, (unsigned int)result);
    mlos_put_u16(params + 4, 4);
    if (mlos_call(SYS_COPY, params) != 4 || result[0] != 'C' || result[3] != 'C') return 5;
    mlos_put_u16(params, handle);
    if (mlos_call(SYS_BANK_FREE, params) != 0) return 6;
    if (mlos_call(SYS_BANK_FREE, params) != SYS_ESTALE) return 7;
    mlos_put_u16(params, 0xFFFF);
    mlos_put_u16(params + 2, 0);
    if (mlos_call(SYS_WRITE, params) != 0) return 12;
    return 0;
}
