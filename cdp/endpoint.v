module cdp

import os

// default_endpoint is the Chrome DevTools HTTP endpoint. It can be overridden
// with CHROME_DEBUG_PORT so the port does not have to be assumed.
pub const default_endpoint = '127.0.0.1:9222'

// endpoint resolves the DevTools endpoint, preferring the environment override.
pub fn endpoint() string {
	mut port := os.getenv('CHROME_DEBUG_PORT')
	if port == '' {
		port = '9222'
	}
	return '127.0.0.1:${port}'
}

// discord_tabs lists the discord.com tabs worth trying, most recently used first.
// A caller should try each until one returns rendered content, since a background
// tab has a DOM that has not been laid out.
pub fn discord_tabs() ![]Target {
	targets := get_json[[]Target](endpoint(), '/json/list') or {
		return error('could not reach Chrome at ${endpoint()}. Start Chrome with ' +
			'--remote-debugging-port=9222 so this server can attach.')
	}
	mut out := []Target{}
	mut devtools := []Target{}
	for t in targets {
		if t.type != 'page' || !t.url.contains('discord.com') {
			continue
		}
		if t.title.starts_with('devtools://') {
			devtools << t
		} else {
			out << t
		}
	}
	// Fall back to any discord tab, including a devtools preview one, rather than
	// failing outright.
	if out.len == 0 {
		return devtools
	}
	return out
}

// find_discord_tab returns the first usable discord.com tab.
pub fn find_discord_tab() !Target {
	tabs := discord_tabs() or { return err }
	if tabs.len == 0 {
		return error('no discord.com tab is open in that Chrome instance')
	}
	return tabs[0]
}

// is_connected reports whether the DevTools endpoint answers.
pub fn is_connected() bool {
	_ := get_json[[]Target](endpoint(), '/json/list') or { return false }
	return true
}