#include "ipc.h"

#include <string.h>

void ipc_init(struct ipc_server *server)
{
	size_t i;

	if (!server)
		return;

	server->socket_fd = -1;
	server->nr_clients = 0;
	for (i = 0; i < sizeof(server->client_fds) / sizeof(server->client_fds[0]);
	     i++)
		server->client_fds[i] = -1;
}

void ipc_poll(struct ipc_server *server, int timeout_ms)
{
	(void)server;
	(void)timeout_ms;
}

void ipc_broadcast(struct ipc_server *server, const char *method,
		   const char *params_json)
{
	(void)server;
	(void)method;
	(void)params_json;
}

void ipc_respond(int client_fd, uint64_t id, const char *result_json)
{
	(void)client_fd;
	(void)id;
	(void)result_json;
}

void ipc_error(int client_fd, uint64_t id, int code, const char *message)
{
	(void)client_fd;
	(void)id;
	(void)code;
	(void)message;
}
