module discord

import json2 as json
import cdp

// Browse is the parsed result of the sidebar probe.
pub struct Browse {
pub mut:
	servers   []ServerEntry
	channels  []ChannelEntry
	current_url string
}

// ServerEntry is one server in the sidebar.
pub struct ServerEntry {
pub:
	name string
	id   string
}

// ChannelEntry is one channel of the open server.
pub struct ChannelEntry {
pub:
	name     string
	id       string
	kind     string
	category string
}

// SessionInfo describes the logged-in browser session.
pub struct SessionInfo {
pub:
	username    string
	server_name string
	url         string
	logged_in   bool
}

// ChatMessage is one Discord message as rendered in the page.
//
// Named ChatMessage rather than Message so it does not collide with
// net.websocket.Message inside this module.
pub struct ChatMessage {
pub:
	id          string
	channel_id  string
	author      string
	content     string
	timestamp   string // ISO 8601, from the <time datetime> attribute
}

// MessagesPage is the parsed message list.
pub struct MessagesPage {
pub mut:
	url      string
	count    int
	messages []ChatMessage
}

// ThreadsPage is the parsed forum thread list.
pub struct ThreadsPage {
pub mut:
	url    string
	threads []ThreadEntry
}

// ThreadEntry is one forum post.
pub struct ThreadEntry {
pub:
	name          string
	author        string
	message_count int
	posted        string
	preview       string
}

// PageStatus reports what the tab is currently showing.
pub struct PageStatus {
pub:
	url            string
	title          string
	channel_name   string
	message_count  int
	has_list       bool
	scroll_height  int
	shows_empty    bool
	is_login_page  bool
}

// json_str reads a string field, tolerating absence.
pub fn json_str(obj map[string]json.Any, key string) string {
	v := obj[key] or { return '' }
	if v is string {
		return v as string
	}
	return ''
}

// json_int reads an integer field, accepting the float shape json2 produces.
pub fn json_int(obj map[string]json.Any, key string) int {
	v := obj[key] or { return 0 }
	if v is f64 {
		return int(v as f64)
	}
	if v is int {
		return v as int
	}
	if v is string {
		return int((v as string).i64())
	}
	return 0
}

// json_bool reads a boolean field.
pub fn json_bool(obj map[string]json.Any, key string) bool {
	v := obj[key] or { return false }
	if v is bool {
		return v as bool
	}
	return false
}

// json_array reads an array field.
fn json_array(obj map[string]json.Any, key string) []json.Any {
	v := obj[key] or { return []json.Any{} }
	if v is []json.Any {
		return v as []json.Any
	}
	return []json.Any{}
}

// run_probe evaluates a probe script and decodes its JSON string result.
//
// The script is wrapped in parentheses so a leading line comment cannot comment
// out the whole expression. Chrome evaluates it as an expression, not a program,
// so the bare form would throw "Unexpected token '('" or silently do nothing.
fn run_probe(script string) !map[string]json.Any {
	raw := cdp_client_eval('(' + script + ')') or { return err }
	text := raw as string
	decoded := json.decode[map[string]json.Any](text) or {
		return error('probe returned malformed JSON')
	}
	return decoded
}

// get_session reports which account and server the browser is showing.
pub fn get_session() !SessionInfo {
	obj := run_probe(session_js()) or { return err }
	return SessionInfo{
		username:    json_str(obj, 'username')
		server_name: json_str(obj, 'server_name')
		url:         json_str(obj, 'url')
		logged_in:   json_bool(obj, 'logged_in')
	}
}

// list_browse returns the servers in the sidebar and the channels of the server
// currently open.
pub fn list_browse() !Browse {
	obj := run_probe(list_js()) or { return err }
	mut out := Browse{
		current_url: json_str(obj, 'url')
	}
	for item in json_array(obj, 'servers') {
		if item !is map[string]json.Any {
			continue
		}
		entry := item as map[string]json.Any
		out.servers << ServerEntry{
			name: json_str(entry, 'name')
			id:   json_str(entry, 'id')
		}
	}
	for item in json_array(obj, 'channels') {
		if item !is map[string]json.Any {
			continue
		}
		entry := item as map[string]json.Any
		out.channels << ChannelEntry{
			name:     json_str(entry, 'name')
			id:       json_str(entry, 'id')
			kind:     json_str(entry, 'kind')
			category: json_str(entry, 'category')
		}
	}
	return out
}

// get_messages reads the messages currently rendered in the open channel.
//
// The probe is a function expression, so it is wrapped in parentheses before the
// limit is appended: without them a leading line comment would swallow the
// whole expression and the call.
pub fn get_messages(limit int) !MessagesPage {
	obj := run_probe('(' + messages_js() + ')(' + limit.str() + ')') or { return err }
	mut page := MessagesPage{
		url:   json_str(obj, 'url')
		count: json_int(obj, 'count')
	}
	for item in json_array(obj, 'messages') {
		if item !is map[string]json.Any {
			continue
		}
		entry := item as map[string]json.Any
		page.messages << ChatMessage{
			id:        json_str(entry, 'id')
			author:    json_str(entry, 'author')
			content:   json_str(entry, 'content')
			timestamp: json_str(entry, 'timestamp')
		}
	}
	return page
}

// get_threads reads the post list of an open forum channel.
pub fn get_threads() !ThreadsPage {
	obj := run_probe(threads_js()) or { return err }
	mut page := ThreadsPage{
		url: json_str(obj, 'url')
	}
	for item in json_array(obj, 'threads') {
		if item !is map[string]json.Any {
			continue
		}
		entry := item as map[string]json.Any
		page.threads << ThreadEntry{
			name:          json_str(entry, 'name')
			author:        json_str(entry, 'author')
			message_count: json_int(entry, 'message_count')
			posted:        json_str(entry, 'posted')
			preview:       json_str(entry, 'preview')
		}
	}
	return page
}

// get_status reports what the tab is showing, which distinguishes an empty
// channel from one that has not finished loading.
pub fn get_status() !PageStatus {
	obj := run_probe(status_js()) or { return err }
	return PageStatus{
		url:           json_str(obj, 'url')
		title:         json_str(obj, 'title')
		channel_name:  json_str(obj, 'channel_name')
		message_count: json_int(obj, 'message_count')
		has_list:      json_bool(obj, 'has_list')
		scroll_height: json_int(obj, 'scroll_height')
		shows_empty:   json_bool(obj, 'shows_empty_state')
		is_login_page: json_bool(obj, 'is_login_page')
	}
}

// arg_int reads an integer field from a raw tool-arguments JSON string, falling
// back to def when the string is absent, unparseable, or has no such field.
// Exposed here so the tool layer does not need its own JSON import.
pub fn arg_int(arguments string, key string, def int) int {
	if arguments == '' {
		return def
	}
	obj := json.decode[map[string]json.Any](arguments) or { return def }
	return json_int(obj, key)
}

// scroll_up scrolls the open channel's message list to the top, which makes
// Discord fetch older messages.
pub fn scroll_up() !map[string]json.Any {
	return run_probe(scroll_up_js())
}
// cdp_client_eval attaches to the open discord.com tab and evaluates a probe,
// returning the JSON document the script produced.
//
// When more than one tab matches, each is tried until one produces a usable
// result. Chrome keeps a background copy of a duplicated window whose DOM exists
// but has not been laid out, so probes against it report an empty message list;
// falling through to the next tab avoids reporting a channel as empty when it is
// merely unread.
fn cdp_client_eval(script string) !json.Any {
	tabs := cdp.discord_tabs() or { return err }
	if tabs.len == 0 {
		return error('no discord.com tab is open in that Chrome instance')
	}
	mut last := 'no usable tab responded'
	for tab in tabs {
		mut client := cdp.connect(tab) or { continue }
		value := client.eval(script) or {
			client.close()
			last = err.str()
			continue
		}
		client.close()
		if !probe_is_empty(value) {
			return value
		}
		last = 'the page returned no rendered content'
	}
	return error(last)
}

// probe_is_empty reports whether a probe result indicates the page had nothing
// rendered, which is the signal to try another tab.
//
// A sidebar probe with channels but no server entries is a valid result, so an
// empty array alone does not mean "nothing here"; a populated `url` alongside a
// real page is treated as usable.
fn probe_is_empty(value json.Any) bool {
	obj := as_object(value) or { return false }
	// A session probe reporting a signed-in state is usable whatever else it
	// contains, so this is checked first.
	if json_bool(obj, 'logged_in') {
		return false
	}
	for key in ['messages', 'threads', 'channels', 'servers'] {
		if v := obj[key] {
			if arr := as_array(v) {
				if arr.len > 0 {
					return false
				}
			}
		}
	}
	if un := obj['username'] {
		if un is string && (un as string).len > 0 {
			return false
		}
	}
	if json_int(obj, 'message_count') > 0 {
		return false
	}
	if json_str(obj, 'channel_name') != '' {
		return false
	}
	// A url on its own is weak evidence, but it does mean a page responded.
	if json_str(obj, 'url') != '' {
		return false
	}
	return true
}

// as_object narrows a decoded JSON value to an object.
fn as_object(v json.Any) ?map[string]json.Any {
	if v is map[string]json.Any {
		return v as map[string]json.Any
	}
	return none
}

// as_array narrows a decoded JSON value to an array.
fn as_array(v json.Any) ?[]json.Any {
	if v is []json.Any {
		return v as []json.Any
	}
	return none
}