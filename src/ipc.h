#ifndef WARPD_IPC_H
#define WARPD_IPC_H

#include <stddef.h>
#include <stdint.h>

#define IPC_SOCKET_PATH "/tmp/warpd.sock"
#define IPC_MAX_MSG_SIZE 65536

struct ipc_server {
	int socket_fd;
	int client_fds[16];
	size_t nr_clients;
};

void ipc_init(struct ipc_server *server);
void ipc_poll(struct ipc_server *server, int timeout_ms);
void ipc_broadcast(struct ipc_server *server, const char *method,
		   const char *params_json);
void ipc_respond(int client_fd, uint64_t id, const char *result_json);
void ipc_error(int client_fd, uint64_t id, int code, const char *message);

#endif
