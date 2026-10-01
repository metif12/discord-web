module cdp

import net.http
import json2 as json

// HttpResponse is a parsed HTTP/1.1 response.
pub struct HttpResponse {
pub:
	status_code int
	body        string
}

// host_and_port splits "host:port" into its parts. The port is required because
// the DevTools endpoint is a local HTTP server, not an HTTPS one.
fn host_and_port(addr string) (string, int) {
	idx := addr.last_index(':') or { return addr, 80 }
	return addr[..idx], int(addr[idx + 1..].i64())
}

// get_json performs a plain HTTP GET against the local DevTools endpoint and
// decodes the response as T.
//
// The Chrome DevTools Protocol is served over HTTP on localhost, so this needs
// no TLS. It is a loopback-only convenience wrapper, not a general HTTP client.
pub fn get_json[T](addr string, path string) !T {
	host, port := host_and_port(addr)
	url := 'http://${host}:${port}${path}'
	mut r := http.Request{
		url:    url
		method: .get
	}
	r.header.add(.host, '${host}:${port}')
	r.header.add(.accept, 'application/json')
	r.header.add(.user_agent, 'discord-web')
	resp := r.do() or { return error('devtools request to ${url} failed: ${err}') }
	if resp.status_code !in [200, 201] {
		return error('devtools endpoint ${url} returned ${resp.status_code}')
	}
	return json.decode[T](resp.body)
}

// post_json sends a JSON body to the DevTools endpoint. Chrome's /json/new and
// /json/activate endpoints accept POST for navigation.
pub fn post_json(addr string, path string) !string {
	host, port := host_and_port(addr)
	url := 'http://${host}:${port}${path}'
	mut r := http.Request{
		url:    url
		method: .post
	}
	r.header.add(.host, '${host}:${port}')
	r.header.add(.content_length, '0')
	resp := r.do() or { return error('devtools POST ${url} failed: ${err}') }
	return resp.body
}

// put_bytes sends a raw body to the DevTools endpoint. Only used for the
// WebSocket upgrade probe, which needs exact bytes rather than JSON.
pub fn put_raw(addr string, path string, body []u8) !int {
	host, port := host_and_port(addr)
	url := 'http://${host}:${port}${path}'
	mut r := http.Request{
		url:    url
		method: .put
		data:   body.bytestr()
	}
	r.header.add(.host, '${host}:${port}')
	r.header.add(.content_type, 'text/plain')
	resp := r.do() or { return error('devtools PUT ${url} failed: ${err}') }
	return resp.status_code
}