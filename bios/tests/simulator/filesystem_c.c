/* Exercise the real CMOC ABI, including automatic request/buffer storage. */
#include "filesystem.h"
typedef char request_size_check[sizeof(FsRequest) == 12 ? 1 : -1];
typedef char stats_size_check[sizeof(FsStats) == 8 ? 1 : -1];

int main(void)
{
    FsRequest request;
    FsStats stats;
    int16_t status;
    unsigned char buffer[128];
    unsigned char *result = (unsigned char *)0x0320;
    *result = 1;
    if (fs_mount(256) != FS_EINVAL || fs_mount(0)) return 1;
    *result = 2;
    request.path = "/docs/sub/data.bin";
    request.buffer = buffer;
    request.count = 32;
    request.offset = 0x10005UL;
    request.transferred = 0;
    if (fs_read(&request) || request.transferred != 32) return 2;
    *result = 3;
    if (buffer[0] != 152 || buffer[31] != 27) return 3;
    *result = 4;
    if (fs_stats(&stats) || !stats.used_blocks || !stats.free_blocks) return 4;
    *result = 5;
    request.count = sizeof(buffer);
    if (fs_stat(&request) || request.transferred != 128 || buffer[1] != 2) return 5;
    request.path = "/docs";
    request.offset = 0;
    status = fs_list(&request);
    *(int16_t *)(result + 2) = status;
    *(uint16_t *)(result + 4) = request.transferred;
    *(uint32_t *)(result + 6) = request.offset;
    result[10] = buffer[1];
    result[11] = buffer[16];
    if (status) return 6;
    if (request.transferred != 1) return 7;
    if (buffer[1] != 1) return 8;
    if (request.offset != 1) return 9;
    if (buffer[16] != 's') return 10;
    *result = 0xA5;
    return 0;
}
