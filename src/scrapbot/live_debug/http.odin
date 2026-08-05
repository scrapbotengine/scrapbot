package live_debug

import "core:crypto"
import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

MAX_HTTP_REQUEST_BYTES :: 64 * 1024

HTTP_Server :: struct {
	service: ^Service,
	listener: net.TCP_Socket,
	worker: ^thread.Thread,
}

HTTP_Request :: struct {
	method: string,
	path: string,
	authorization: string,
	accept: string,
	content_type: string,
	body: []byte,
}

Discovery :: struct {
	schema_version: int,
	process_id: int,
	url: string,
	token: string,
	project_root: string,
}

start_http_server :: proc(
	server: ^HTTP_Server,
	service: ^Service,
	requested_port: int = 0,
) -> string {
	if server == nil || service == nil {
		return "live debug HTTP server is unavailable"
	}
	if requested_port < 0 || requested_port > 65535 {
		return "live debug port must be between 0 and 65535"
	}
	server^ = {}
	listener, listen_err := net.listen_tcp({address = net.IP4_Loopback, port = requested_port}, 32)
	if listen_err != nil {
		return fmt.tprintf("failed to listen for live debug HTTP: %v", listen_err)
	}
	server.listener = listener
	server.service = service
	bound, bound_err := net.bound_endpoint(listener)
	if bound_err != nil {
		net.close(listener)
		server^ = {}
		return fmt.tprintf("failed to inspect live debug HTTP listener: %v", bound_err)
	}
	service.port = bound.port
	service.running = true
	if discovery_err := write_discovery(service); discovery_err != "" {
		service.running = false
		net.close(listener)
		server^ = {}
		return discovery_err
	}
	server.worker = thread.create_and_start_with_data(server, http_server_loop)
	return ""
}

stop_http_server :: proc(server: ^HTTP_Server) {
	if server == nil || server.service == nil {
		return
	}
	sync.mutex_lock(&server.service.mutex)
	server.service.running = false
	sync.mutex_unlock(&server.service.mutex)
	net.close(server.listener)
	if server.worker != nil {
		thread.join(server.worker)
		thread.destroy(server.worker)
	}
	if server.service.discovery_path != "" {
		_ = os.remove(server.service.discovery_path)
	}
	server^ = {}
}

write_discovery :: proc(service: ^Service) -> string {
	url := fmt.aprintf("http://127.0.0.1:%d", service.port)
	defer delete(url)
	discovery := Discovery {
		schema_version = SCHEMA_VERSION,
		process_id = service.process_id,
		url = url,
		token = service.token,
		project_root = service.root,
	}
	data, marshal_err := json.marshal(discovery)
	if marshal_err != nil {
		return fmt.tprintf("failed to encode live debug discovery: %v", marshal_err)
	}
	defer delete(data)
	if write_err := write_private_file(service.discovery_path, data); write_err != nil {
		return fmt.tprintf("failed to write live debug discovery: %v", write_err)
	}
	return ""
}

http_server_loop :: proc(data: rawptr) {
	server := cast(^HTTP_Server)data
	if server == nil || server.service == nil {
		return
	}
	for {
		client, _, accept_err := net.accept_tcp(server.listener)
		if accept_err != nil {
			if !service_is_running(server.service) {
				return
			}
			continue
		}
		_ = net.set_option(client, .Receive_Timeout, 2 * time.Second)
		_ = net.set_option(client, .Send_Timeout, 2 * time.Second)
		handle_http_client(server.service, client)
		net.close(client)
	}
}

service_is_running :: proc(service: ^Service) -> bool {
	if service == nil {
		return false
	}
	sync.mutex_lock(&service.mutex)
	defer sync.mutex_unlock(&service.mutex)
	return service.running
}

handle_http_client :: proc(service: ^Service, client: net.TCP_Socket) {
	request_data, read_err := read_http_request(client)
	if read_err != "" {
		write_http_error(client, 400, "BAD_REQUEST", read_err, .JSON)
		return
	}
	defer delete(request_data)
	request, parse_err := parse_http_request(request_data)
	if parse_err != "" {
		write_http_error(client, 400, "BAD_REQUEST", parse_err, .JSON)
		return
	}
	response_codec := codec_from_accept(request.accept)
	if !authorized(service, request.authorization) {
		write_http_error(
			client,
			401,
			"UNAUTHORIZED",
			"a valid bearer token is required",
			response_codec,
		)
		return
	}
	handle_http_request(service, client, request, response_codec)
}

read_http_request :: proc(client: net.TCP_Socket) -> ([]byte, string) {
	buffer := make([]byte, MAX_HTTP_REQUEST_BYTES)
	used := 0
	header_end := -1
	content_length := 0
	for used < len(buffer) {
		count, recv_err := net.recv_tcp(client, buffer[used:])
		if recv_err != nil {
			delete(buffer)
			return nil, fmt.tprintf("failed to read HTTP request: %v", recv_err)
		}
		if count == 0 {
			break
		}
		used += count
		if header_end < 0 {
			header_marker := strings.index(string(buffer[:used]), "\r\n\r\n")
			if header_marker >= 0 {
				header_end = header_marker + 4
				content_length = http_content_length(string(buffer[:header_marker]))
				if content_length < 0 || header_end + content_length > len(buffer) {
					delete(buffer)
					return nil, "invalid or oversized HTTP Content-Length"
				}
			}
		}
		if header_end >= 0 && used >= header_end + content_length {
			result := make([]byte, header_end + content_length)
			copy(result, buffer[:len(result)])
			delete(buffer)
			return result, ""
		}
	}
	delete(buffer)
	return nil, "incomplete or oversized HTTP request"
}

http_content_length :: proc(headers: string) -> int {
	lines := strings.split(headers, "\r\n")
	defer delete(lines)
	for line in lines[1:] {
		separator := strings.index(line, ":")
		if separator < 0 ||
		   !strings.equal_fold(strings.trim_space(line[:separator]), "Content-Length") {
			continue
		}
		value := line[separator + 1:]
		length, ok := strconv.parse_int(strings.trim_space(value))
		if !ok || length < 0 {
			return -1
		}
		return length
	}
	return 0
}

parse_http_request :: proc(data: []byte) -> (HTTP_Request, string) {
	header_marker := strings.index(string(data), "\r\n\r\n")
	if header_marker < 0 {
		return {}, "HTTP request has no header terminator"
	}
	header := string(data[:header_marker])
	lines := strings.split(header, "\r\n")
	defer delete(lines)
	if len(lines) == 0 {
		return {}, "HTTP request line is missing"
	}
	request_parts := strings.fields(lines[0])
	defer delete(request_parts)
	if len(request_parts) != 3 || request_parts[2] != "HTTP/1.1" {
		return {}, "expected an HTTP/1.1 request line"
	}
	request := HTTP_Request {
		method = request_parts[0],
		path = request_parts[1],
		body = data[header_marker + 4:],
	}
	for line in lines[1:] {
		separator := strings.index(line, ":")
		if separator < 0 {
			continue
		}
		key := line[:separator]
		value := line[separator + 1:]
		value = strings.trim_space(value)
		switch {
			case strings.equal_fold(key, "Authorization"):
				request.authorization = value
			case strings.equal_fold(key, "Accept"):
				request.accept = value
			case strings.equal_fold(key, "Content-Type"):
				request.content_type = value
		}
	}
	return request, ""
}

authorized :: proc(service: ^Service, header: string) -> bool {
	prefix := "Bearer "
	if !strings.has_prefix(header, prefix) {
		return false
	}
	candidate := header[len(prefix):]
	return(
		crypto.compare_constant_time(transmute([]byte)candidate, transmute([]byte)service.token) ==
		1 \
	)
}

codec_from_accept :: proc(value: string) -> Codec {
	if strings.contains(value, "application/cbor") {
		return .CBOR
	}
	return .JSON
}

codec_from_content_type :: proc(value: string) -> (Codec, bool) {
	if value == "" || strings.contains(value, "application/json") {
		return .JSON, true
	}
	if strings.contains(value, "application/cbor") {
		return .CBOR, true
	}
	return .JSON, false
}

handle_http_request :: proc(
	service: ^Service,
	client: net.TCP_Socket,
	request: HTTP_Request,
	response_codec: Codec,
) {
	if request.method == "GET" &&
	   (request.path == "/v1/session" || request.path == "/v1/snapshot") {
		data, encode_err := encode_snapshot(service, response_codec)
		if encode_err != "" {
			write_http_error(client, 500, "ENCODE_FAILED", encode_err, response_codec)
			return
		}
		defer delete(data)
		write_http_response(client, 200, response_codec, data)
		return
	}
	if request.method == "GET" && request.path == "/v1/captures/current" {
		data, encode_err := encode_capture(service, response_codec)
		if encode_err != "" {
			write_http_error(client, 500, "ENCODE_FAILED", encode_err, response_codec)
			return
		}
		defer delete(data)
		write_http_response(client, 200, response_codec, data)
		return
	}
	if request.method == "POST" && request.path == "/v1/captures" {
		request_codec, supported := codec_from_content_type(request.content_type)
		if !supported {
			write_http_error(
				client,
				415,
				"UNSUPPORTED_MEDIA_TYPE",
				"use application/json or application/cbor",
				response_codec,
			)
			return
		}
		capture_request, decode_err := decode_capture_request(request.body, request_codec)
		if decode_err != "" {
			write_http_error(client, 400, "INVALID_CAPTURE", decode_err, response_codec)
			return
		}
		_, enqueue_err := enqueue_capture(service, capture_request.frames)
		if enqueue_err != "" {
			write_http_error(client, 409, "CAPTURE_ACTIVE", enqueue_err, response_codec)
			return
		}
		data, encode_err := encode_capture(service, response_codec)
		if encode_err != "" {
			write_http_error(client, 500, "ENCODE_FAILED", encode_err, response_codec)
			return
		}
		defer delete(data)
		write_http_response(client, 202, response_codec, data)
		return
	}
	write_http_error(client, 404, "NOT_FOUND", "unknown live debug endpoint", response_codec)
}

write_http_error :: proc(
	client: net.TCP_Socket,
	status: int,
	code, message: string,
	codec: Codec,
) {
	data := encode_error(code, message, codec)
	defer delete(data)
	write_http_response(client, status, codec, data)
}

write_http_response :: proc(client: net.TCP_Socket, status: int, codec: Codec, body: []byte) {
	content_type := "application/json"
	if codec == .CBOR {
		content_type = "application/cbor"
	}
	status_text := "OK"
	switch status {
		case 202:
			status_text = "Accepted"
		case 400:
			status_text = "Bad Request"
		case 401:
			status_text = "Unauthorized"
		case 404:
			status_text = "Not Found"
		case 409:
			status_text = "Conflict"
		case 415:
			status_text = "Unsupported Media Type"
		case 500:
			status_text = "Internal Server Error"
	}
	header := fmt.aprintf(
		"HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n",
		status,
		status_text,
		content_type,
		len(body),
	)
	defer delete(header)
	write_http_bytes(client, transmute([]byte)header)
	write_http_bytes(client, body)
}

write_http_bytes :: proc(client: net.TCP_Socket, data: []byte) {
	written := 0
	for written < len(data) {
		count, send_err := net.send_tcp(client, data[written:])
		if send_err != nil || count <= 0 {
			return
		}
		written += count
	}
}
