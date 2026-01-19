#include "ipc.h"

#include "warpd.h"

#include <ctype.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef _WIN32
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#endif

struct strbuf {
	char *data;
	size_t len;
	size_t cap;
};

static void get_hint_size(screen_t scr, int *w, int *h)
{
	int sw, sh;

	platform->screen_get_dimensions(scr, &sw, &sh);

	if (sw < sh) {
		int tmp = sw;
		sw = sh;
		sh = tmp;
	}

	*w = (sw * config_get_int("hint_size")) / 1000;
	*h = (sh * config_get_int("hint_size")) / 1000;
}

static int hint_label_length(size_t count, size_t alphabet_len)
{
	int length = 1;
	size_t capacity = alphabet_len;

	if (alphabet_len == 0)
		return 0;

	while (capacity < count && length < (int)(sizeof(((struct hint *)0)->label) - 1)) {
		length++;
		capacity *= alphabet_len;
	}

	return length;
}

static void generate_hint_labels(struct hint *out_hints, size_t count,
				 const char *alphabet)
{
	size_t alphabet_len = strlen(alphabet);
	int label_len = hint_label_length(count, alphabet_len);

	if (!label_len)
		return;

	for (size_t i = 0; i < count; i++) {
		size_t value = i;
		for (int pos = label_len - 1; pos >= 0; pos--) {
			out_hints[i].label[pos] = alphabet[value % alphabet_len];
			value /= alphabet_len;
		}
		out_hints[i].label[label_len] = 0;
	}
}

static void sb_init(struct strbuf *sb)
{
	sb->cap = 1024;
	sb->len = 0;
	sb->data = calloc(1, sb->cap);
}

static void sb_reserve(struct strbuf *sb, size_t extra)
{
	if (sb->len + extra + 1 <= sb->cap)
		return;

	while (sb->len + extra + 1 > sb->cap)
		sb->cap *= 2;

	sb->data = realloc(sb->data, sb->cap);
}

static void sb_append(struct strbuf *sb, const char *fmt, ...)
{
	va_list ap;
	int needed;

	va_start(ap, fmt);
	needed = vsnprintf(NULL, 0, fmt, ap);
	va_end(ap);

	if (needed < 0)
		return;

	sb_reserve(sb, (size_t)needed);

	va_start(ap, fmt);
	vsnprintf(sb->data + sb->len, sb->cap - sb->len, fmt, ap);
	va_end(ap);
	sb->len += (size_t)needed;
}

static void sb_append_char(struct strbuf *sb, char c)
{
	sb_reserve(sb, 1);
	sb->data[sb->len++] = c;
	sb->data[sb->len] = '\0';
}

static void sb_append_escaped(struct strbuf *sb, const char *s)
{
	for (; s && *s; s++) {
		if (*s == '"' || *s == '\\')
			sb_append_char(sb, '\\');
		sb_append_char(sb, *s);
	}
}

static const char *type_to_string(enum option_type type)
{
	switch (type) {
	case OPT_STRING:
		return "string";
	case OPT_INT:
		return "int";
	case OPT_KEY:
		return "key";
	case OPT_BUTTON:
		return "button";
	default:
		return "unknown";
	}
}

static char *config_to_json(void)
{
	struct strbuf sb;
	struct config_entry *entry = config;
	int first = 1;

	sb_init(&sb);
	sb_append(&sb, "{\"entries\":[");

	while (entry) {
		if (!first)
			sb_append_char(&sb, ',');
		first = 0;

		sb_append(&sb, "{\"key\":\"");
		sb_append_escaped(&sb, entry->key);
		sb_append(&sb, "\",\"value\":\"");
		sb_append_escaped(&sb, entry->value);
		sb_append(&sb, "\",\"type\":\"%s\"}", type_to_string(entry->type));

		entry = entry->next;
	}

	sb_append(&sb, "]}");
	return sb.data;
}

static const char *config_get_safe(const char *key)
{
	struct config_entry *entry;

	for (entry = config; entry; entry = entry->next)
		if (!strcmp(entry->key, key))
			return entry->value;

	return NULL;
}

#ifndef _WIN32
static int set_nonblocking(int fd)
{
	int flags = fcntl(fd, F_GETFL, 0);
	if (flags < 0)
		return -1;
	return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

static void remove_client(struct ipc_server *server, size_t idx)
{
	close(server->client_fds[idx]);
	server->client_fds[idx] = -1;
	for (; idx + 1 < server->nr_clients; idx++)
		server->client_fds[idx] = server->client_fds[idx + 1];
	if (server->nr_clients > 0)
		server->nr_clients--;
}

static const char *skip_ws(const char *p)
{
	while (p && *p && isspace((unsigned char)*p))
		p++;
	return p;
}

static int parse_id(const char *msg, uint64_t *out_id)
{
	const char *p = strstr(msg, "\"id\"");
	if (!p)
		return -1;
	p = strchr(p, ':');
	if (!p)
		return -1;
	p = skip_ws(p + 1);
	if (!p || !isdigit((unsigned char)*p))
		return -1;
	*out_id = strtoull(p, NULL, 10);
	return 0;
}

static int parse_method(const char *msg, char *out, size_t out_sz)
{
	const char *p = strstr(msg, "\"method\"");
	size_t len = 0;

	if (!p)
		return -1;
	p = strchr(p, ':');
	if (!p)
		return -1;
	p = skip_ws(p + 1);
	if (!p || *p != '"')
		return -1;
	p++;

	while (*p && *p != '"' && len + 1 < out_sz) {
		out[len++] = *p++;
	}
	out[len] = '\0';
	return (*p == '"') ? 0 : -1;
}

static int parse_string_field(const char *msg, const char *field, char *out,
			      size_t out_sz)
{
	char needle[64];
	const char *p;
	size_t len = 0;

	snprintf(needle, sizeof(needle), "\"%s\"", field);
	p = strstr(msg, needle);
	if (!p)
		return -1;
	p = strchr(p, ':');
	if (!p)
		return -1;
	p = skip_ws(p + 1);
	if (!p || *p != '"')
		return -1;
	p++;

	while (*p && *p != '"' && len + 1 < out_sz)
		out[len++] = *p++;
	out[len] = '\0';
	return (*p == '"') ? 0 : -1;
}

static int parse_uint_field(const char *msg, const char *field, uint64_t *out)
{
	char needle[64];
	const char *p;

	snprintf(needle, sizeof(needle), "\"%s\"", field);
	p = strstr(msg, needle);
	if (!p)
		return -1;
	p = strchr(p, ':');
	if (!p)
		return -1;
	p = skip_ws(p + 1);
	if (!p || !isdigit((unsigned char)*p))
		return -1;
	*out = strtoull(p, NULL, 10);
	return 0;
}

static void send_all(int fd, const char *buf)
{
	size_t len = strlen(buf);
	while (len > 0) {
		ssize_t n = send(fd, buf, len, 0);
		if (n <= 0)
			return;
		buf += (size_t)n;
		len -= (size_t)n;
	}
}

static void handle_message(int client_fd, const char *msg)
{
	uint64_t id = 0;
	char method[64] = {0};
	static struct hint last_hints[MAX_HINTS];
	static size_t last_hint_count = 0;
	static screen_t last_screen = NULL;

	if (parse_id(msg, &id) != 0 || parse_method(msg, method, sizeof(method)) != 0) {
		ipc_error(client_fd, id, -32600, "Invalid Request");
		return;
	}

	if (strcmp(method, "status") == 0) {
		char result[256];
		snprintf(result, sizeof(result), "{\"version\":\"%s\"}", VERSION);
		ipc_respond(client_fd, id, result);
		return;
	}

	if (strcmp(method, "config.get_all") == 0) {
		char *json = config_to_json();
		ipc_respond(client_fd, id, json);
		free(json);
		return;
	}

	if (strcmp(method, "config.get") == 0) {
		char key[64];
		struct strbuf sb;
		const char *value;

		if (parse_string_field(msg, "key", key, sizeof(key)) != 0) {
			ipc_error(client_fd, id, -32602, "Missing key");
			return;
		}

		value = config_get_safe(key);
		if (!value) {
			ipc_error(client_fd, id, -32602, "Unknown key");
			return;
		}

		sb_init(&sb);
		sb_append(&sb, "{\"value\":\"");
		sb_append_escaped(&sb, value);
		sb_append(&sb, "\"}");
		ipc_respond(client_fd, id, sb.data);
		free(sb.data);
		return;
	}

	if (strcmp(method, "config.set") == 0) {
		char key[64];
		char value[128];

		if (parse_string_field(msg, "key", key, sizeof(key)) != 0 ||
		    parse_string_field(msg, "value", value, sizeof(value)) != 0) {
			ipc_error(client_fd, id, -32602, "Missing key/value");
			return;
		}

		if (!config_set_value(key, value)) {
			ipc_error(client_fd, id, -32602, "Invalid value");
			return;
		}

		ipc_respond(client_fd, id, "{\"ok\":true}");
		return;
	}

	if (strcmp(method, "config.get_schema") == 0) {
		char *json = config_schema_json();
		ipc_respond(client_fd, id, json);
		free(json);
		return;
	}

	if (strcmp(method, "elements.list") == 0) {
		struct strbuf sb;
		size_t i;
		int w, h;
		int sw, sh;
		size_t n = 0;
		screen_t scr = NULL;

		if (!platform->collect_interactable_hints) {
			ipc_respond(client_fd, id, "{\"elements\":[]}");
			return;
		}

		memset(last_hints, 0, sizeof(last_hints));
		platform->mouse_get_position(&scr, NULL, NULL);
		if (!scr) {
			ipc_respond(client_fd, id, "{\"elements\":[]}");
			return;
		}

		platform->screen_get_dimensions(scr, &sw, &sh);
		get_hint_size(scr, &w, &h);

		n = platform->collect_interactable_hints(scr, last_hints, MAX_HINTS);
		if (!n) {
			ipc_respond(client_fd, id, "{\"elements\":[]}");
			return;
		}

		for (size_t idx = 0; idx < n; idx++) {
			int max_x = sw - w;
			int max_y = sh - h;
			int x = last_hints[idx].x - w / 2;
			int y = last_hints[idx].y - h / 2;

			if (max_x < 0)
				max_x = 0;
			if (max_y < 0)
				max_y = 0;

			last_hints[idx].w = w;
			last_hints[idx].h = h;
			last_hints[idx].x = MIN(max_x, x < 0 ? 0 : x);
			last_hints[idx].y = MIN(max_y, y < 0 ? 0 : y);
		}

		generate_hint_labels(last_hints, n, config_get("hint_chars"));
		last_hint_count = n;
		last_screen = scr;

		sb_init(&sb);
		sb_append(&sb, "{\"elements\":[");
		for (i = 0; i < n; i++) {
			if (i > 0)
				sb_append_char(&sb, ',');
			sb_append(&sb,
				  "{\"id\":%zu,\"x\":%d,\"y\":%d,\"w\":%d,\"h\":%d,",
				  i, last_hints[i].x, last_hints[i].y,
				  last_hints[i].w, last_hints[i].h);
			sb_append(&sb, "\"hint\":\"");
			sb_append_escaped(&sb, last_hints[i].label);
			sb_append(&sb, "\",\"label\":\"");
			sb_append_escaped(&sb, last_hints[i].title);
			sb_append(&sb, "\",\"role\":\"");
			sb_append_escaped(&sb, last_hints[i].role);
			sb_append(&sb, "\",\"desc\":\"");
			sb_append_escaped(&sb, last_hints[i].desc);
			sb_append(&sb, "\"}");
		}
		sb_append(&sb, "]}");
		ipc_respond(client_fd, id, sb.data);
		free(sb.data);
		return;
	}

	if (strcmp(method, "elements.click") == 0 ||
	    strcmp(method, "elements.focus") == 0) {
		uint64_t elem_id = 0;
		int cx;
		int cy;

		if (parse_uint_field(msg, "id", &elem_id) != 0 ||
		    elem_id >= last_hint_count) {
			ipc_error(client_fd, id, -32602, "Invalid element id");
			return;
		}

		cx = last_hints[elem_id].x + last_hints[elem_id].w / 2;
		cy = last_hints[elem_id].y + last_hints[elem_id].h / 2;
		platform->mouse_move(last_screen, cx, cy);

		if (strcmp(method, "elements.click") == 0)
			platform->mouse_click(1);

		ipc_respond(client_fd, id, "{\"ok\":true}");
		return;
	}

	if (strcmp(method, "elements.info") == 0) {
		uint64_t elem_id = 0;
		struct strbuf sb;

		if (parse_uint_field(msg, "id", &elem_id) != 0 ||
		    elem_id >= last_hint_count) {
			ipc_error(client_fd, id, -32602, "Invalid element id");
			return;
		}

		sb_init(&sb);
		sb_append(&sb, "{\"element\":{");
		sb_append(&sb,
			  "\"id\":%llu,\"x\":%d,\"y\":%d,\"w\":%d,\"h\":%d,",
			  (unsigned long long)elem_id,
			  last_hints[elem_id].x, last_hints[elem_id].y,
			  last_hints[elem_id].w, last_hints[elem_id].h);
		sb_append(&sb, "\"hint\":\"");
		sb_append_escaped(&sb, last_hints[elem_id].label);
		sb_append(&sb, "\",\"label\":\"");
		sb_append_escaped(&sb, last_hints[elem_id].title);
		sb_append(&sb, "\",\"role\":\"");
		sb_append_escaped(&sb, last_hints[elem_id].role);
		sb_append(&sb, "\",\"desc\":\"");
		sb_append_escaped(&sb, last_hints[elem_id].desc);
		sb_append(&sb, "\"}}");
		ipc_respond(client_fd, id, sb.data);
		free(sb.data);
		return;
	}

	ipc_error(client_fd, id, -32601, "Method not found");
}
#endif

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

#ifndef _WIN32
	int fd;
	struct sockaddr_un addr;

	unlink(IPC_SOCKET_PATH);

	fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0)
		return;

	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	strncpy(addr.sun_path, IPC_SOCKET_PATH, sizeof(addr.sun_path) - 1);

	if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		close(fd);
		return;
	}

	if (listen(fd, 4) < 0) {
		close(fd);
		return;
	}

	set_nonblocking(fd);
	server->socket_fd = fd;
#endif
}

void ipc_poll(struct ipc_server *server, int timeout_ms)
{
#ifndef _WIN32
	struct pollfd fds[1 + 16];
	nfds_t nfds = 0;
	size_t i;

	if (!server || server->socket_fd < 0)
		return;

	fds[nfds].fd = server->socket_fd;
	fds[nfds].events = POLLIN;
	nfds++;

	for (i = 0; i < server->nr_clients; i++) {
		fds[nfds].fd = server->client_fds[i];
		fds[nfds].events = POLLIN;
		nfds++;
	}

	if (poll(fds, nfds, timeout_ms) <= 0)
		return;

	if (fds[0].revents & POLLIN) {
		int client_fd = accept(server->socket_fd, NULL, NULL);
		if (client_fd >= 0) {
			set_nonblocking(client_fd);
			if (server->nr_clients < sizeof(server->client_fds) /
						   sizeof(server->client_fds[0])) {
				server->client_fds[server->nr_clients++] = client_fd;
			} else {
				close(client_fd);
			}
		}
	}

	for (i = 0; i < server->nr_clients; i++) {
		char buf[IPC_MAX_MSG_SIZE];
		ssize_t n;

		if (!(fds[i + 1].revents & POLLIN))
			continue;

		n = recv(server->client_fds[i], buf, sizeof(buf) - 1, 0);
		if (n <= 0) {
			remove_client(server, i);
			i--;
			continue;
		}

		buf[n] = '\0';
		char *line = strtok(buf, "\n");
		while (line) {
			if (*line)
				handle_message(server->client_fds[i], line);
			line = strtok(NULL, "\n");
		}
	}
#else
	(void)server;
	(void)timeout_ms;
#endif
}

void ipc_broadcast(struct ipc_server *server, const char *method,
		   const char *params_json)
{
#ifndef _WIN32
	size_t i;
	struct strbuf sb;

	if (!server || !method)
		return;

	sb_init(&sb);
	sb_append(&sb, "{\"method\":\"");
	sb_append_escaped(&sb, method);
	sb_append(&sb, "\"");
	if (params_json)
		sb_append(&sb, ",\"params\":%s", params_json);
	sb_append(&sb, "}\n");

	for (i = 0; i < server->nr_clients; i++)
		send_all(server->client_fds[i], sb.data);

	free(sb.data);
#else
	(void)server;
	(void)method;
	(void)params_json;
#endif
}

void ipc_respond(int client_fd, uint64_t id, const char *result_json)
{
#ifndef _WIN32
	struct strbuf sb;

	sb_init(&sb);
	sb_append(&sb, "{\"id\":%llu,\"result\":%s}\n",
		  (unsigned long long)id, result_json ? result_json : "null");
	send_all(client_fd, sb.data);
	free(sb.data);
#else
	(void)client_fd;
	(void)id;
	(void)result_json;
#endif
}

void ipc_error(int client_fd, uint64_t id, int code, const char *message)
{
#ifndef _WIN32
	struct strbuf sb;

	sb_init(&sb);
	sb_append(&sb, "{\"id\":%llu,\"error\":{\"code\":%d,\"message\":\"",
		  (unsigned long long)id, code);
	sb_append_escaped(&sb, message ? message : "error");
	sb_append(&sb, "\"}}\n");
	send_all(client_fd, sb.data);
	free(sb.data);
#else
	(void)client_fd;
	(void)id;
	(void)code;
	(void)message;
#endif
}
