#define _GNU_SOURCE
#include <unistd.h>
#include <sys/types.h>
#include <string.h>

extern char *program_invocation_short_name;

/*
 * Overrides getuid() to return 1000 (regular non-root user 'ubuntu')
 * ONLY if the calling program is 'claude', 'claude-real', or 'node'.
 * Otherwise returns 0 (root).
 */
uid_t getuid(void) {
    if (program_invocation_short_name && 
        (strcmp(program_invocation_short_name, "claude") == 0 || 
         strcmp(program_invocation_short_name, "claude-real") == 0 ||
         strcmp(program_invocation_short_name, "node") == 0)) {
        return 1000;
    }
    return 0;
}

/*
 * Overrides geteuid() to return 1000 (regular non-root user 'ubuntu')
 * ONLY if the calling program is 'claude', 'claude-real', or 'node'.
 * Otherwise returns 0 (root).
 */
uid_t geteuid(void) {
    if (program_invocation_short_name && 
        (strcmp(program_invocation_short_name, "claude") == 0 || 
         strcmp(program_invocation_short_name, "claude-real") == 0 ||
         strcmp(program_invocation_short_name, "node") == 0)) {
        return 1000;
    }
    return 0;
}
