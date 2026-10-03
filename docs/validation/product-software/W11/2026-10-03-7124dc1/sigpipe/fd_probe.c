#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv) {
    struct sigaction action;
    if (sigaction(SIGPIPE, NULL, &action) != 0) return 20;
    int a[2], b[2];
    if (pipe(a) != 0 || pipe(b) != 0) return 21;
    int protected = argc == 2 && strcmp(argv[1], "protected") == 0;
    int default_signal = action.sa_handler == SIG_DFL;
    int before = fcntl(a[1], F_GETNOSIGPIPE);
    int other_before = fcntl(b[1], F_GETNOSIGPIPE);
    int set_result = protected ? fcntl(a[1], F_SETNOSIGPIPE, 1) : 0;
    int after = fcntl(a[1], F_GETNOSIGPIPE);
    int other_after = fcntl(b[1], F_GETNOSIGPIPE);
    close(a[0]);
    printf("default_SIGPIPE=%d protected=%d set=%d before=%d after=%d other_before=%d other_after=%d\n", default_signal, protected, set_result, before, after, other_before, other_after);
    fflush(stdout);
    errno = 0;
    ssize_t count = write(a[1], "x\n", 2);
    int saved_errno = errno;
    printf("write_result=%zd errno=%d EPIPE=%d\n", count, saved_errno, EPIPE);
    int closed = a[1];
    close(a[1]);
    errno = 0;
    int closed_result = fcntl(closed, F_SETNOSIGPIPE, 1);
    int closed_errno = errno;
    printf("closed_fcntl=%d errno=%d EBADF=%d\n", closed_result, closed_errno, EBADF);
    close(b[0]); close(b[1]);
    return default_signal && protected && set_result == 0 && before == 0 && after == 1 && other_before == 0 && other_after == 0 && count == -1 && saved_errno == EPIPE && closed_result == -1 && closed_errno == EBADF ? 0 : 22;
}
