/* CF-loaded filesystem acceptance diagnostic. Owns only /fsdiag on partition 1.
 * Refuses an existing namespace; failures leave it available for inspection. */
#include "filesystem.h"

extern void diag_putc(unsigned char value);
static unsigned char buffer[600];

static void text(const char *message)
{
    while (*message) diag_putc(*message++);
}

static void hex(uint16_t value)
{
    unsigned char i;
    for (i = 0; i < 4; ++i) {
        unsigned char digit = (unsigned char)((value >> 12) & 15);
        diag_putc(digit < 10 ? '0' + digit : 'A' + digit - 10);
        value <<= 4;
    }
}

static unsigned char pattern(uint16_t index)
{
    return (unsigned char)(index * 19 + 3);
}

#define CHECK(call, name) do { status = (call); stage = (name); if (status) goto failed; } while (0)

int main(void)
{
    FsRequest request;
    FsStats before, after;
    int16_t status;
    uint16_t i;
    const char *stage = "mount";
    text("FS diagnostic: partition 1, /fsdiag\r\n");
    CHECK(fs_mount(1), "mount");
    CHECK(fs_stats(&before), "initial stats");
    request.path = "/fsdiag";
    request.buffer = buffer;
    request.count = sizeof(buffer);
    request.offset = 0;
    CHECK(fs_mkdir(&request), "create namespace (must be absent)");
    request.path = "/fsdiag/a";
    CHECK(fs_create(&request), "create file");
    request.path = "/fsdiag/blocker";
    CHECK(fs_create(&request), "create growth blocker");
    request.path = "/fsdiag/a";
    for (i = 0; i < sizeof(buffer); ++i) buffer[i] = pattern(i);
    request.offset = 511;
    CHECK(fs_write(&request), "write/growth");
    stage = "write count";
    status = FS_ECORRUPT;
    if (request.transferred != sizeof(buffer)) goto failed;
    CHECK(fs_stat(&request), "stat");
    stage = "file size";
    status = FS_ECORRUPT;
    if (buffer[2] || buffer[3] || buffer[4] != 4 || buffer[5] != 0x57) goto failed;
    request.offset = 0;
    request.count = 512;
    CHECK(fs_read(&request), "read gap");
    stage = "zero gap";
    status = FS_ECORRUPT;
    if (request.transferred != 512) goto failed;
    for (i = 0; i < 511; ++i) if (buffer[i]) goto failed;
    if (buffer[511] != pattern(0)) goto failed;
    request.offset = 511;
    request.count = sizeof(buffer);
    CHECK(fs_read(&request), "read contents");
    stage = "compare contents";
    status = FS_ECORRUPT;
    if (request.transferred != sizeof(buffer)) goto failed;
    for (i = 0; i < sizeof(buffer); ++i) if (buffer[i] != pattern(i)) goto failed;
    request.buffer = (void *)"/fsdiag/renamed";
    CHECK(fs_rename(&request), "rename");
    request.path = "/fsdiag/sub";
    request.offset = 0;
    CHECK(fs_mkdir(&request), "mkdir");
    request.path = "/fsdiag/renamed";
    request.buffer = (void *)"/fsdiag/sub/save";
    CHECK(fs_rename(&request), "move");
    request.path = "/fsdiag/sub";
    stage = "nonempty directory";
    status = fs_rmdir(&request);
    if (status != FS_ENOTEMPTY) goto failed;
    request.path = "/fsdiag/sub/save";
    CHECK(fs_unlink(&request), "unlink");
    request.path = "/fsdiag/sub";
    CHECK(fs_rmdir(&request), "rmdir");
    request.path = "/fsdiag/blocker";
    CHECK(fs_unlink(&request), "remove blocker");
    request.path = "/fsdiag";
    CHECK(fs_rmdir(&request), "remove namespace");
    CHECK(fs_stats(&after), "final stats");
    stage = "allocation balance";
    status = FS_ECORRUPT;
    if (before.used_blocks != after.used_blocks || before.free_blocks != after.free_blocks) goto failed;
    CHECK(fs_mount(0), "restore partition 0");
    text("FS diagnostic PASS (allocation balanced)\r\n");
    return 0;
failed:
    text("FS diagnostic FAIL: ");
    text(stage);
    text(" status=");
    hex((uint16_t)status);
    text("\r\n");
    fs_mount(0);
    return 1;
}
