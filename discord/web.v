module discord

// The probe scripts live as .js files so they can be edited and syntax-highlighted
// as JavaScript rather than embedded as V string literals, which cannot hold the
// quotes and backslashes these DOM queries need.
//
// $embed_file bakes them into the binary, so the built server has no runtime
// dependency on the source tree.

// session_js reports the signed-in user, the open server, and whether the page is
// the Discord app rather than the login screen.
pub fn session_js() string {
	return $embed_file('js/session.js').to_string()
}

// list_js reads the sidebar: every server, and every channel of the open one.
pub fn list_js() string {
	return $embed_file('js/list.js').to_string()
}

// messages_js returns a function expression that reads the rendered messages of
// the open channel. The caller appends the limit as an argument.
pub fn messages_js() string {
	return $embed_file('js/messages.js').to_string()
}

// scroll_up_js returns a script that scrolls the message list to the top so
// Discord fetches older history.
pub fn scroll_up_js() string {
	return $embed_file('js/scroll_up.js').to_string()
}

// threads_js reads the post list of an open forum channel.
pub fn threads_js() string {
	return $embed_file('js/threads.js').to_string()
}

// status_js reports what the tab is currently showing.
pub fn status_js() string {
	return $embed_file('js/status.js').to_string()
}

// channel_url builds a Discord channel URL from a guild and channel id, for
// asking the user to open a specific channel.
pub fn channel_url(guild_id string, channel_id string) string {
	return 'https://discord.com/channels/${guild_id}/${channel_id}'
}