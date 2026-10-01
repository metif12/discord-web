module main

import mcp

import discord

const server_name = 'discord-web'
const server_version = '0.1.0'

// main starts the Discord browser MCP server on stdio.
//
// It reads whatever Chrome tab is open on discord.com through the DevTools
// Protocol, so it sees exactly what the signed-in account sees. No token is
// read or stored, and nothing is sent to Discord's API.
fn main() {
	mut server := mcp.new_server(
		name:        server_name
		version:     server_version
		title:       'Discord (browser session)'
		description: 'Reads Discord through an already-signed-in Chrome tab.'
		instructions: 'These tools read the page you already have open in Chrome; ' +
			'they do not call the Discord API and need no token. Start with ' +
			'check_session, then list_channels to see the channels of the open ' +
			'server. read_full_history walks the channel that is on screen from the ' +
			'bottom to the very start of its history, so use it instead of repeated ' +
			'read_messages calls; it takes a while on a busy channel because it has ' +
			'to scroll like a person would. read_messages is the quick way to see ' +
			'only what is already visible. For a different channel, ask the user to ' +
			'open it in the browser. In a forum channel, read_threads lists the ' +
			'posts and open_thread opens one so its replies can be read.'
		enable_logging: true
	)

	register_tools(mut &server)

	server.serve_stdio() or {
		eprintln('discord-web: stdio server failed: ${err}')
		exit(1)
	}
}

// connection_hint is shown when the browser cannot be reached, since the fix is
// always the same and never obvious from a connection error.
const connection_hint = 'Start Chrome with remote debugging enabled, for example:\n' +
	'  chrome.exe --remote-debugging-port=9222\n' +
	'then open https://discord.com and sign in.'

// failure renders a tool result for a browser-side failure.
fn failure(msg string) mcp.ToolResult {
	return mcp.tool_text_result('${msg}\n\n${connection_hint}')
}

// register_tools exposes the browser-backed tools.
fn register_tools(mut server &mcp.Server) {
	server.add_tool(mcp.Tool{
		name:        'check_session'
		title:       'Check session'
		description: 'Report which Discord account and server the browser tab is ' +
			'showing. Call this first: every other tool reads the tab that is ' +
			'open, so this confirms what will be read.'
		input_schema: '{"type":"object","properties":{},' +
			'"additionalProperties":false}'
		annotations: mcp.ToolAnnotations{
			read_only_hint:  true
			open_world_hint: false
		}
	}, fn (_ mcp.Context, _ string) !mcp.ToolResult {
		session := discord.get_session() or { return failure(err.str()) }
		if !session.logged_in {
			return mcp.tool_text_result('The tab is not signed in to Discord. ' +
				'Open discord.com in the browser and sign in, then retry.')
		}
		mut sb := []string{}
		sb << 'Signed in as: ${session.username}'
		if session.server_name != '' {
			sb << 'Open server: ${session.server_name}'
		}
		sb << 'Tab: ${session.url}'
		return mcp.tool_text_result(sb.join('\n'))
	}) or { eprintln('discord-web: failed to register check_session: ${err}') }

	server.add_tool(mcp.Tool{
		name:        'list_channels'
		title:       'List channels'
		description: 'List the channels of the server currently open in the ' +
			'browser, grouped by category, plus the servers in the sidebar.'
		input_schema: '{"type":"object","properties":{},' +
			'"additionalProperties":false}'
		annotations: mcp.ToolAnnotations{
			read_only_hint:  true
			open_world_hint: false
		}
	}, fn (_ mcp.Context, _ string) !mcp.ToolResult {
		b := discord.list_browse() or { return failure(err.str()) }
		mut sb := []string{}
		if b.servers.len > 0 {
			sb << 'Servers in the sidebar (${b.servers.len}):'
			for s in b.servers {
				id_part := if s.id != '' { ' (id: ${s.id})' } else { '' }
				sb << '- ${s.name}${id_part}'
			}
			sb << ''
		}
		if b.channels.len == 0 {
			sb << 'No channels are visible in the open server. It may still be ' +
				'loading, or the sidebar may be collapsed.'
			return mcp.tool_text_result(sb.join('\n'))
		}
		sb << 'Channels of the open server (${b.channels.len}):'
		mut current_category := ''
		for c in b.channels {
			if c.category != '' && c.category != current_category {
				current_category = c.category
				sb << '  [${current_category}]'
			}
			sb << '  - ${c.name} [${c.kind}] (id: ${c.id})'
		}
		return mcp.tool_text_result(sb.join('\n'))
	}) or { eprintln('discord-web: failed to register list_channels: ${err}') }

	server.add_tool(mcp.Tool{
		name:        'read_messages'
		title:       'Read messages'
		description: 'Read the messages currently rendered in the channel that ' +
			'is open in the browser. This is the quick way to see what is on ' +
			'screen; use read_full_history when you need the whole channel.'
		input_schema: '{"type":"object","properties":{' +
			'"limit":{"type":"integer","description":"How many of the most recent ' +
			'messages to return, default 50","default":50}},' +
			'"additionalProperties":false}'
		annotations: mcp.ToolAnnotations{
			read_only_hint:  true
			open_world_hint: false
		}
	}, fn (_ mcp.Context, arguments string) !mcp.ToolResult {
		limit := arg_int(arguments, 'limit', 50)
		page := discord.get_messages(limit) or { return failure(err.str()) }
		if page.messages.len == 0 {
			return mcp.tool_text_result('No messages are rendered in the open ' +
				'channel. It may be empty, still loading, or the tab may not be ' +
				'on a channel. Call check_session for the current page.')
		}
		mut sb := []string{}
		sb << '${page.messages.len} message(s) from ${page.url} (oldest first):'
		for m in page.messages {
			author := if m.author != '' { m.author } else { 'unknown' }
			stamp := if m.timestamp != '' { '[' + m.timestamp + '] ' } else { '' }
			sb << '${stamp}${author}: ${m.content.replace("\n", "\n    ")}'
		}
		return mcp.tool_text_result(sb.join('\n'))
	}) or { eprintln('discord-web: failed to register read_messages: ${err}') }

	server.add_tool(mcp.Tool{
		name:        'read_threads'
		title:       'List forum posts'
		description: 'List the posts in a forum channel that is open in the ' +
			'browser. Shows each post title, author, message count and preview.'
		input_schema: '{"type":"object","properties":{},' +
			'"additionalProperties":false}'
		annotations: mcp.ToolAnnotations{
			read_only_hint:  true
			open_world_hint: false
		}
	}, fn (_ mcp.Context, _ string) !mcp.ToolResult {
		page := discord.get_threads() or { return failure(err.str()) }
		if page.threads.len == 0 {
			return mcp.tool_text_result('No forum posts are rendered. The open ' +
				'channel may not be a forum, or it may still be loading.')
		}
		mut sb := []string{}
		sb << '${page.threads.len} post(s) in ${page.url}:'
		for t in page.threads {
			sb << ''
			sb << '## ${t.name}'
			mut meta := []string{}
			if t.author != '' {
				meta << 'by ${t.author}'
			}
			meta << '${t.message_count} messages'
			if t.posted != '' {
				meta << t.posted
			}
			sb << meta.join(', ')
			if t.preview != '' {
				sb << t.preview
			}
		}
		return mcp.tool_text_result(sb.join('\n'))
	}) or { eprintln('discord-web: failed to register read_threads: ${err}') }

	server.add_tool(mcp.Tool{
		name:        'page_status'
		title:       'Page status'
		description: 'Report what the browser tab is currently showing: page ' +
			'title, channel name, how many messages are rendered, and whether ' +
			'the list can scroll. Useful for telling an empty channel from a ' +
			'tab that has not finished loading.'
		input_schema: '{"type":"object","properties":{},' +
			'"additionalProperties":false}'
		annotations: mcp.ToolAnnotations{
			read_only_hint:  true
			open_world_hint: false
		}
	}, fn (_ mcp.Context, _ string) !mcp.ToolResult {
		s := discord.get_status() or { return failure(err.str()) }
		mut sb := []string{}
		sb << 'title: ${s.title}'
		sb << 'url: ${s.url}'
		sb << 'channel: ${s.channel_name}'
		sb << 'rendered messages: ${s.message_count}'
		sb << 'message list present: ${s.has_list}'
		sb << 'scroll height: ${s.scroll_height}px'
		if s.is_login_page {
			sb << 'this tab is the login page'
		}
		if s.shows_empty {
			sb << 'this channel shows Discord\'s empty state'
		}
		return mcp.tool_text_result(sb.join('\n'))
	}) or { eprintln('discord-web: failed to register page_status: ${err}') }

	register_history_tools(mut server)
}

// register_history_tools exposes the tools that walk a channel's whole history.
fn register_history_tools(mut server &mcp.Server) {
	server.add_tool(mcp.Tool{
		name:        'read_full_history'
		title:       'Read full channel history'
		description: 'Walk the open channel backwards and return its whole ' +
			'readable history, oldest first. Scrolls the message list the way a ' +
			'person would, because Discord only renders a window at a time, and ' +
			'stops when the start of the channel is reached. Prefer this over ' +
			'repeated read_messages calls. A busy channel takes a while; the ' +
			'reported range shows how far back it got.'
		input_schema: '{"type":"object","properties":{' +
			'"max_messages":{"type":"integer","description":"Cap on collected messages",' +
			'"default":500}},' +
			'"additionalProperties":false}'
		annotations: mcp.ToolAnnotations{
			read_only_hint:   true
			destructive_hint: false
			idempotent_hint:  true
			open_world_hint:  false
		}
	}, fn (ctx mcp.Context, arguments string) !mcp.ToolResult {
		mut cap := arg_int(arguments, 'max_messages', 500)
		if cap <= 0 {
			cap = 500
		}
		ctx.notify_progress(0, f64(cap), 'walking channel history')
		page := discord.collect_history(cap) or {
			return failure('Could not read the channel history: ${err}')
		}
		if page.messages.len == 0 {
			return mcp.tool_text_result('No messages collected from ${page.url}. ' +
				'The channel may be empty, still loading, or the tab may not be on ' +
				'a channel. Call page_status for the current state.')
		}
		mut sb := []string{}
		sb << '${page.total} message(s) from ${page.url}'
		sb << 'range: ${page.oldest} to ${page.newest}'
		sb << 'stopped because: ${page.stopped} (${page.passes} scroll passes)'
		sb << ''
		mut lines := []string{}
		for m in page.messages {
			author := if m.author != '' { m.author } else { 'unknown' }
			stamp := if m.timestamp != '' { m.timestamp } else { 'unknown time' }
			lines << '[${stamp}] ${author}: ${m.content.replace("\n", "\n    ")}'
		}
		sb << lines.join('\n')
		return mcp.tool_text_result(sb.join('\n'))
	}) or { eprintln('discord-web: failed to register read_full_history: ${err}') }

	server.add_tool(mcp.Tool{
		name:        'scroll_history'
		title:       'Inspect the message list'
		description: 'Report where the open channel\'s message list sits: how many ' +
			'messages are rendered, the scroll position, and the oldest timestamp. ' +
			'Use it to check progress while history loads.'
		input_schema: '{"type":"object","properties":{},' +
			'"additionalProperties":false}'
		annotations: mcp.ToolAnnotations{
			read_only_hint:   true
			destructive_hint: false
			idempotent_hint:  true
			open_world_hint:  false
		}
	}, fn (_ mcp.Context, _ string) !mcp.ToolResult {
		st := discord.scroll_history() or {
			return failure('Reading the message list failed: ${err}')
		}
		mut sb := []string{}
		sb << 'url: ${st.url}'
		sb << 'rendered messages: ${st.rendered}'
		sb << 'scroll position: ${st.scroll_top} of ${st.scroll_height}' +
			' (viewport ${st.client_height})'
		sb << 'oldest rendered: ${st.oldest_timestamp}'
		sb << 'newest rendered: ${st.newest_timestamp}'
		return mcp.tool_text_result(sb.join('\n'))
	}) or { eprintln('discord-web: failed to register scroll_history: ${err}') }

	server.add_tool(mcp.Tool{
		name:        'open_thread'
		title:       'Open a forum post'
		description: 'Open a forum post in the currently open forum channel so its ' +
			'replies can be read. The title must match what read_threads returned.'
		input_schema: '{"type":"object","properties":{' +
			'"title":{"type":"string","description":"Post title as read_threads showed it"}},' +
			'"required":["title"],"additionalProperties":false}'
		annotations: mcp.ToolAnnotations{
			read_only_hint:   true
			destructive_hint: false
			idempotent_hint:  true
			open_world_hint:  false
		}
	}, fn (_ mcp.Context, arguments string) !mcp.ToolResult {
		title := discord.str_arg(arguments, 'title')
		if title == '' {
			return mcp.tool_text_result('title is required.')
		}
		res := discord.open_thread(title) or {
			return failure('Opening the post failed: ${err}')
		}
		if !discord.json_bool(res, 'ok') {
			return mcp.tool_text_result('Could not open the post: ' +
				discord.json_str(res, 'reason'))
		}
		return mcp.tool_text_result('Opened "${discord.json_str(res, 'opened')}". ' +
			'Wait a moment for the replies to render, then call read_messages or ' +
			'read_full_history to read the discussion.')
	}) or { eprintln('discord-web: failed to register open_thread: ${err}') }
}

// arg_int reads an integer tool argument, falling back to def.
fn arg_int(arguments string, key string, def int) int {
	return discord.arg_int(arguments, key, def)
}