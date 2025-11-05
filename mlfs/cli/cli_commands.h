/****************************** cli_commands.h ******************************/
// MLFS CLI command definitions and structures
#ifndef CLI_COMMANDS_H
#define CLI_COMMANDS_H

#include "mlfs.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Maximum command line length
#define MAX_CMD_LEN 1024
#define MAX_ARGS 16
#define MAX_ARG_LEN 256

// CLI state structure
typedef struct {
    FILE *image_file;
    mlfs_io_t io;
    mlfs_t fs;
    char image_path[256];
    char current_dir[256];      // Current working directory path
    uint16_t current_partition; // Currently mounted partition number
    int mounted;
} cli_state_t;

// Command function type
typedef int (*cmd_func_t)(cli_state_t *state, int argc, char **argv);

// Command structure
typedef struct {
    const char *name;
    const char *usage;
    const char *description;
    cmd_func_t func;
} command_t;

// File I/O functions for disk images
int file_io_read(void *ctx, uint64_t lba, uint32_t count, void *buf);
int file_io_write(void *ctx, uint64_t lba, uint32_t count, const void *buf);

// Command functions
int cmd_help(cli_state_t *state, int argc, char **argv);
int cmd_mount(cli_state_t *state, int argc, char **argv);
int cmd_unmount(cli_state_t *state, int argc, char **argv);
int cmd_format(cli_state_t *state, int argc, char **argv);
int cmd_ls(cli_state_t *state, int argc, char **argv);
int cmd_mkdir(cli_state_t *state, int argc, char **argv);
int cmd_rmdir(cli_state_t *state, int argc, char **argv);
int cmd_touch(cli_state_t *state, int argc, char **argv);
int cmd_rm(cli_state_t *state, int argc, char **argv);
int cmd_cat(cli_state_t *state, int argc, char **argv);
int cmd_write(cli_state_t *state, int argc, char **argv);
int cmd_info(cli_state_t *state, int argc, char **argv);
int cmd_cd(cli_state_t *state, int argc, char **argv);
int cmd_pwd(cli_state_t *state, int argc, char **argv);
int cmd_partitions(cli_state_t *state, int argc, char **argv);
int cmd_partition(cli_state_t *state, int argc, char **argv);
int cmd_mkpart(cli_state_t *state, int argc, char **argv);
int cmd_mkfs(cli_state_t *state, int argc, char **argv);
int cmd_open(cli_state_t *state, int argc, char **argv);
int cmd_close(cli_state_t *state, int argc, char **argv);
int cmd_quit(cli_state_t *state, int argc, char **argv);

// Utility functions
void print_help(void);
void print_prompt(cli_state_t *state);
int parse_command(char *line, char **args);
int execute_command(cli_state_t *state, int argc, char **argv);

// Path resolution utilities
char* resolve_path(cli_state_t *state, const char *path, char *resolved, size_t resolved_size);
void init_cli_state_cwd(cli_state_t *state);

// Global command table
extern const command_t commands[];
extern const int num_commands;

#endif // CLI_COMMANDS_H
