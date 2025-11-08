/****************************** main.c *************************************/
// MLFS CLI - Main application entry point
#include "cli_commands.h"
#include <signal.h>

#ifdef HAVE_READLINE
#include <readline/history.h>
#include <readline/readline.h>
#endif

// Global state
static cli_state_t g_state = {0};

// Signal handler for clean exit
void signal_handler(int sig)
{
    (void)sig;
    printf("\n\nReceived interrupt signal. Exiting...\n");
    if(g_state.mounted) {
        cmd_unmount(&g_state, 0, NULL);
    }
    exit(0);
}

// Print command prompt
void print_prompt(cli_state_t *state)
{
    if(state->mounted) {
        printf("mlfs:%s[%u]:%s> ", state->image_path, state->current_partition, state->current_dir);
    } else if(state->image_file) {
        printf("mlfs:%s> ", state->image_path);
    } else {
        printf("mlfs> ");
    }
    fflush(stdout);
}

// Parse command line into arguments
int parse_command(char *line, char **args)
{
    int argc = 0;
    char *ptr = line;
    static char arg_buffer[MAX_CMD_LEN];
    int arg_pos = 0;

    while(*ptr && argc < MAX_ARGS - 1) {
        // Skip leading whitespace
        while(*ptr && (*ptr == ' ' || *ptr == '\t' || *ptr == '\n')) {
            ptr++;
        }
        
        if(!*ptr) break;

        args[argc] = &arg_buffer[arg_pos];
        
        if(*ptr == '"') {
            // Quoted string - everything between quotes becomes one argument
            ptr++; // Skip opening quote
            while(*ptr && *ptr != '"') {
                if(*ptr == '\\' && *(ptr + 1)) {
                    // Handle escaped characters
                    ptr++;
                    switch(*ptr) {
                        case 'n': arg_buffer[arg_pos++] = '\n'; break;
                        case 't': arg_buffer[arg_pos++] = '\t'; break;
                        case 'r': arg_buffer[arg_pos++] = '\r'; break;
                        case '\\': arg_buffer[arg_pos++] = '\\'; break;
                        case '"': arg_buffer[arg_pos++] = '"'; break;
                        default: arg_buffer[arg_pos++] = *ptr; break;
                    }
                } else {
                    arg_buffer[arg_pos++] = *ptr;
                }
                ptr++;
            }
            if(*ptr == '"') {
                ptr++; // Skip closing quote
            }
        } else {
            // Regular argument - until whitespace
            while(*ptr && *ptr != ' ' && *ptr != '\t' && *ptr != '\n') {
                arg_buffer[arg_pos++] = *ptr;
                ptr++;
            }
        }
        
        arg_buffer[arg_pos++] = '\0'; // Null terminate
        argc++;
    }

    args[argc] = NULL;
    return argc;
}

// Execute a command
int execute_command(cli_state_t *state, int argc, char **argv)
{
    if(argc == 0)
        return 0;

    // Find and execute command
    for(int i = 0; i < num_commands; i++) {
        if(strcmp(argv[0], commands[i].name) == 0) {
            return commands[i].func(state, argc, argv);
        }
    }

    printf("Unknown command: %s\n", argv[0]);
    printf("Type 'help' for available commands.\n");
    return -1;
}

#ifdef HAVE_READLINE
// Command completion for readline
char **command_completion(const char *text, int start, int end)
{
    (void)start;
    (void)end; // Suppress unused warnings

    char **matches = NULL;

    // Only complete commands at the beginning of the line
    if(start == 0) {
        matches = rl_completion_matches(text, rl_filename_completion_function);

        // Add our commands to the completion list
        static char *command_names[sizeof(commands) / sizeof(commands[0]) + 1];
        static int initialized = 0;

        if(!initialized) {
            for(int i = 0; i < num_commands; i++) {
                command_names[i] = (char *)commands[i].name;
            }
            command_names[num_commands] = NULL;
            initialized = 1;
        }

        // Simple command name completion
        int len = strlen(text);
        for(int i = 0; i < num_commands; i++) {
            if(strncmp(text, commands[i].name, len) == 0) {
                if(!matches) {
                    matches = malloc(sizeof(char *) * 2);
                    matches[0] = strdup(commands[i].name);
                    matches[1] = NULL;
                } else {
                    // This is a simplified version - readline has more complex completion
                    break;
                }
            }
        }
    }

    return matches;
}
#endif

// Initialize CLI
void init_cli(void)
{
    // Setup signal handlers
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

#ifdef HAVE_READLINE
    // Initialize readline
    rl_readline_name = "mlfs";
    rl_attempted_completion_function = command_completion;
#endif

    // Print welcome message
    printf("MLFS CLI - MicroLind File System Command Line Interface\n");
    printf("========================================================\n");
    printf("Version 0.3 - Type 'help' for available commands\n\n");

    printf("Quick start:\n");
    printf("  format disk.img              # Create a new 64MB disk image\n");
    printf("  mount disk.img               # Mount the disk image\n");
    printf("  help                         # Show all commands\n\n");
}

#ifdef HAVE_READLINE
// Main CLI loop
void cli_loop(void)
{
    char *line;
    char *args[MAX_ARGS];
    int argc;
    int result;

    while(1) {
        // Get command from user
        if(g_state.mounted) {
            char prompt[300];
            snprintf(prompt, sizeof(prompt), "mlfs:%s[%u]:%s> ", g_state.image_path, g_state.current_partition, g_state.current_dir);
            line = readline(prompt);
        } else if(g_state.image_file) {
            char prompt[300];
            snprintf(prompt, sizeof(prompt), "mlfs:%s> ", g_state.image_path);
            line = readline(prompt);
        } else {
            line = readline("mlfs> ");
        }

        // Handle EOF (Ctrl-D)
        if(!line) {
            printf("\n");
            break;
        }

        // Skip empty lines
        if(strlen(line) == 0) {
            free(line);
            continue;
        }

        // Add to history
        add_history(line);

        // Parse and execute command
        argc = parse_command(line, args);
        if(argc > 0) {
            result = execute_command(&g_state, argc, args);
            if(result == 1) { // Quit command returns 1
                free(line);
                break;
            }
        }

        free(line);
    }
}
#endif

// Alternative simple CLI loop (fallback if readline not available)
void simple_cli_loop(void)
{
    char line[MAX_CMD_LEN];
    char *args[MAX_ARGS];
    int argc;
    int result;

    while(1) {
        // Print prompt
        print_prompt(&g_state);

        // Read line
        if(!fgets(line, sizeof(line), stdin)) {
            break;
        }

        // Parse and execute command
        argc = parse_command(line, args);
        if(argc > 0) {
            result = execute_command(&g_state, argc, args);
            if(result == 1) { // Quit command returns 1
                break;
            }
        }
    }
}

// Main function
int main(int argc, char **argv)
{
    // Initialize CLI state
    init_cli_state_cwd(&g_state);
    
    // Initialize CLI
    init_cli();

    // If image file provided as argument, try to mount it
    if(argc >= 2) {
        char *mount_args[] = {"mount", argv[1]};
        printf("Attempting to mount '%s'...\n", argv[1]);
        if(cmd_mount(&g_state, 2, mount_args) == 0) {
            printf("\n");
        } else {
            printf("Failed to mount '%s'. You can create a new image with 'format %s'\n\n", argv[1], argv[1]);
        }
    }

    // Run CLI loop
#ifdef HAVE_READLINE
    cli_loop();
#else
    simple_cli_loop();
#endif

    // Cleanup
    if(g_state.mounted) {
        cmd_unmount(&g_state, 0, NULL);
    }

    return 0;
}
