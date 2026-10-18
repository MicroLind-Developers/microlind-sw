#ifndef MLOS_FS_H
#define MLOS_FS_H
#include "mlos.h"
#define F_STAT 0
#define F_LIST 1
#define F_READ_PATH 2
#define F_WRITE_PATH 3
#define F_CREATE 4
#define F_UNLINK 5
#define F_MKDIR 6
#define F_RMDIR 7
#define F_RENAME 8
#define F_TRUNCATE 9
#define F_STATS 10
#define F_OPEN 11
#define F_CLOSE 12
#define F_READ 13
#define F_WRITE 14
#define F_SEEK 15
#define F_CHDIR 16
#define F_GETCWD 17
#define F_MOUNTS 18
#define F_RECOVER 19
#define F_UNMOUNT 20
#define F_WRITE_FLAG 1
#define F_CREATE_FLAG 2
#define F_TRUNCATE_FLAG 4
#define F_PACKET_SIZE 400
int fs_call(u8 *packet);
int fs_open(const char *path, u8 flags);
int fs_close(u16 fd);
int fs_read(u16 fd, void *data, u16 count);
int fs_write(u16 fd, const void *data, u16 count);
int fs_seek(u16 fd, u32 offset);
int fs_chdir(const char *path);
int fs_getcwd(char *path);
int fs_list(const char *path, u32 *cursor, u8 *dentry);
int fs_stat(const char *path, u8 *dentry);
int fs_mutate(u8 op, const char *path, const char *other);
#endif
