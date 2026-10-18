/* Disposable S00 MLFS fixture, using the production host filesystem encoder. */
#define _POSIX_C_SOURCE 200809L
#include "mlfs.h"
#include <stdio.h>
#include <time.h>
#include <unistd.h>
/* Fixed sources replace host wall/CPU clocks only in this fixture executable. */
time_t fixture_time(time_t *out) { const time_t value=1792195200; if(out)*out=value;return value; }
clock_t fixture_clock(void) { return 0; }
int fixture_rand(void) { static unsigned long state=1;state=(state*1103515245+12345)&0x7FFFFFFF;return (int)(state>>16); }
static int rd(void *ctx,uint64_t lba,uint32_t count,void *buf) {
    return fseeko(ctx,(off_t)(lba*512),SEEK_SET) || fread(buf,512,count,ctx)!=count ? -1:0;
}
static int wr(void *ctx,uint64_t lba,uint32_t count,const void *buf) {
    return fseeko(ctx,(off_t)(lba*512),SEEK_SET) || fwrite(buf,512,count,ctx)!=count ? -1:0;
}
int main(int argc,char **argv) {
    if(argc!=2)return 1;
    FILE *disk=fopen(argv[1],"w+b");if(!disk)return 1;
    if(ftruncate(fileno(disk),128*512))return 1;
    mlfs_io_t io={disk,rd,wr,512};mlfs_t fs;
    const char text[]="MLOS S00 disposable MLFS fixture\r\n";
    if(mlfs_make_single_partition(&io,1,127,9) || mlfs_mkfs(&io,0,&fs) ||
       mlfs_create_empty_file(&fs,"fixture.txt",1) ||
       mlfs_pwrite_file(&fs,"fixture.txt",text,sizeof(text)-1,0)!=(ssize_t)(sizeof(text)-1))return 1;
    return fclose(disk)!=0;
}
