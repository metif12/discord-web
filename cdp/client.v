module cdp

import time
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
	return c.call('Runtime.evaluate',
		'{"expression":${json.encode(expression)},"returnByValue":true,"awaitPromise":true}')
}

// send_input dispatches a trusted input event, such as a real mouse wheel.
//
// Trusted events matter for scrolling: Discord drives its message list from its
// own scroller component, which ignores synthetic wheel events and reacts only to
// events the browser itself produced. A synthetic WheelEvent looks plausible but
// does nothing, so loading older history requires this path.
pub fn (mut c Client) wheel(x int, y int, delta_y int) !void {
	c.call('Input.dispatchMouseEvent',
		'{"type":"mouseWheel","x":${x},"y":${y},"deltaX":0,"deltaY":${delta_y},"pointerType":"mouse"}') or {
		return err
	}
}

// press sends a key press, which some scrollers accept as a scroll command.
pub fn (mut c Client) press(key string, key_code int) !void {
	c.call('Input.dispatchKeyEvent',
		'{"type":"rawKeyDown","key":"${key}","code":"${key}","windowsVirtualKeyCode":${key_code},"nativeVirtualKeyCode":${key_code}}') or {
		return err
	}
	c.call('Input.dispatchKeyEvent',
		'{"type":"keyUp","key":"${key}","code":"${key}","windowsVirtualKeyCode":${key_code},"nativeVirtualKeyCode":${key_code}}') or {
		return err
	}
}

// navigate loads a URL in the tab and returns once the document has committed.
//
// A full load rather than an in-page route change: Discord's SPA router swallows
// synthetic navigation, and a real document load is what actually boots the
// channel view with a fresh message list.
pub fn (mut c Client) navigate(url string) !void {
	c.call('Page.navigate', '{"url":${json.encode(url)}}') or { return err }
}

// wait_for_poll evaluates an expression until it returns true, or the timeout
// expires. Discord renders a channel asynchronously after a navigation, so
// reading straight after a load usually returns an empty page.

// now_ms is the monotonic clock in milliseconds.
fn now_ms() i64 {
	return time.sys_mono_now() / 1_000_000
}

// sleep_ms waits for the given number of milliseconds.
fn sleep_ms(dur int) {
	time.sleep(dur * time.millisecond)
}

// poll_ready evaluates a script until it reports that the page is ready.
//
// Discord renders a channel asynchronously after a navigation, so a read taken
// immediately after a load usually sees an empty page. The readiness probe
// returns a JSON document with an "ok" field, and matching the field name in the
// raw text avoids decoding it.
//
// A failed eval means the socket is busy with the load, so it counts as "not
// ready" rather than an error; only the timeout decides the outcome.
pub fn (mut c Client) poll_ready(script string, timeout_ms int, gap_ms int) bool {
	deadline := now_ms() + i64(timeout_ms)
	for {
		raw := c.eval(script) or { json.Any('null') }
		text := raw as string
		if text.contains(ready_marker) {
			return true
		}
		if now_ms() > deadline {
			return false
		}
		sleep_ms(gap_ms)
	}
}

// ready_marker is the substring the readiness probe's output must contain.
const ready_marker = '\"ok\":true'

// click sends a trusted left click, which is how a post or link is opened.
//
// A synthetic MouseEvent in the page is not enough: React's delegated handler
// discards events it did not observe at the browser input layer, so opening a
// forum post needs this path.
pub fn (mut c Client) click(x int, y int) !void {
	c.call('Input.dispatchMouseEvent', '{"type":"mousePressed","x":${x},"y":${y},"button":"left","clickCount":1,"pointerType":"mouse"}') or {
		return err
	}
	c.call('Input.dispatchMouseEvent', '{"type":"mouseReleased","x":${x},"y":${y},"button":"left","clickCount":1,"pointerType":"mouse"}') or {
		return err
	}
}

// bring_to_front activates the tab.
//
// This is required, not cosmetic: input dispatch blocks until the renderer
// acknowledges it, and a background tab never acknowledges. Mouse events hang
// without this call.
pub fn (mut c Client) bring_to_front() !void {
	c.call('Page.bringToFront', '{}') or { return err }
}

// call sends one DevTools command with a hand-written params object and returns
// the command's result value, or null for commands that produce none.
fn (mut c Client) call(method string, params string) !json.Any {
	c.next_id++
	id := c.next_id
	req := '{"id":${id},"method":"${method}","params":${params}}'
	c.ws.write_string(req) or { return error('sending ${method} failed: ${err}') }

	for {
		mut msg := c.ws.read_next_message() or {
			return error('reading the ${method} reply failed: ${err}')
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
			return error('${method} failed: ' + json_str(eo, 'message'))
		}
		result := as_obj(env['result'] or { json.Any('null') }) or {
			return error('${method} reply had no result object')
		}
		if d := result['exceptionDetails'] {
			do := as_obj(d) or { return error('${method} script threw') }
			return error('${method} script threw: ' + json_str(do, 'text'))
		}
		inner := as_obj(result['result'] or { json.Any('null') }) or {
			// Most commands reply with an empty result object and no value.
			return json.Any('null')
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
