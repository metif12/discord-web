module cdp

import json2 as json
import net.websocket

// Target is one entry from Chrome's /json/list endpoint. Chrome spells several
// keys in camelCase, which V does not allow as field names, so they are mapped
// explicitly.
pub struct Target {
pub:
	id                   string
	type                 string
	title                string
	url                  string
	web_socket_debugger_url string @[json: webSocketDebuggerUrl]
}

// Client talks to one Chrome tab through the DevTools Protocol.
@[heap]
pub struct Client {
mut:
	ws      &websocket.Client = unsafe { nil }
	next_id int
}

// connect attaches to the given target's debugger socket.
pub fn connect(target Target) !&Client {
	if target.web_socket_debugger_url == '' {
		return error('target ${target.id} has no debugger socket')
	}
	mut client := websocket.new_client(target.web_socket_debugger_url, websocket.ClientOpt{}) or {
		return error('opening the debugger socket failed: ${err}')
	}
	client.connect() or { return error('connecting the debugger socket failed: ${err}') }
	return &Client{
		ws:      client
		next_id: 0
	}
}

// close shuts the debugger socket down.
pub fn (mut c Client) close() {
	if c.ws != unsafe { nil } {
		c.ws.close(1000, 'done') or {}
	}
}

// json_int_field narrows a decoded JSON value to an int, accepting the float
// shape json2 produces for every JSON number.
fn json_int_field(v json.Any) int {
	if v is f64 {
		return int(v as f64)
	}
	if v is int {
		return v as int
	}
	return -1
}

// as_obj narrows a decoded JSON value to an object. Discord's and Chrome's
// replies are deeply nested and variant-typed, so every lookup needs this and
// a bare `as map[string]json.Any` copies the map.
fn as_obj(v json.Any) ?map[string]json.Any {
	if v is map[string]json.Any {
		return v as map[string]json.Any
	}
	return none
}

// eval runs a JavaScript expression in the page and returns its value decoded as
// json2.Any.
//
// The request is written by hand because Chrome's parameter names are camelCase
// and V forbids uppercase in field names; json2 mishandles a camelCase-mapped
// struct when it reaches a sum-typed field. The reply is then read out of a
// generic object for the same reason.
pub fn (mut c Client) eval(expression string) !json.Any {
	c.next_id++
	id := c.next_id
	// expression is embedded as a JSON string literal, so quotes and backslashes
	// inside the script cannot break the envelope.
	encoded_expr := json.encode(expression)
	req := '{"id":${id},"method":"Runtime.evaluate","params":' +
		'{"expression":${encoded_expr},"returnByValue":true,"awaitPromise":true}}'

	c.ws.write_string(req) or { return error('sending the evaluate request failed: ${err}') }

	for {
		mut msg := c.ws.read_next_message() or {
			return error('reading the evaluate reply failed: ${err}')
		}
		defer {
			unsafe {
				msg.free()
			}
		}
		if msg.opcode != .text_frame && msg.opcode != .binary_frame {
			continue
		}
		reply := json.decode[json.Any](msg.payload.bytestr()) or {
			// Chrome interleaves events on the same socket; anything that is not
			// a JSON object is not our reply.
			continue
		}
		env := as_obj(reply) or { continue }
		id_field := env['id'] or { continue }
		if json_int_field(id_field) != id {
			continue
		}
		if e := env['error'] {
			eo := as_obj(e) or { return error('devtools error') }
			return error('devtools error: ' + json_str(eo, 'message'))
		}
		result := as_obj(env['result'] or { json.Any('null') }) or {
			return error('devtools reply had no result object')
		}
		if d := result['exceptionDetails'] {
			do := as_obj(d) or { return error('script threw') }
			return error('script threw: ' + json_str(do, 'text'))
		}
		inner := as_obj(result['result'] or { json.Any('null') }) or {
			return error('devtools reply had no inner result')
		}
		return inner['value'] or { json.Any('null') }
	}
}

// json_str reads a string field from a decoded JSON object, or an empty string.
fn json_str(obj map[string]json.Any, key string) string {
	v := obj[key] or { return '' }
	if v is string {
		return v as string
	}
	return ''
}

// json_int reads an integer field from a decoded JSON object.
fn json_int(obj map[string]json.Any, key string) int {
	v := obj[key] or { return 0 }
	if v is f64 {
		return int(v as f64)
	}
	if v is int {
		return v as int
	}
	return 0
}