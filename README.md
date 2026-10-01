# discord-web

A Discord MCP server that reads Discord through a Chrome tab you are already
signed into, over the DevTools Protocol.

No token. No API calls. No self-bot. It reads the page in front of you.

## Why this exists

Discord gives no read access to ordinary user accounts, so a bot has to be
invited to every server you want to read, and only members with **Manage Server**
can invite one. For a large public server you do not moderate, that means asking
a stranger to add a bot.

There is a third option this project takes: use the browser session you already
have. The MCP server attaches to a Chrome tab via `--remote-debugging-port` and
evaluates small DOM probes against it. What it reads is exactly what you see, and
what it can reach is exactly what you can reach.

This is not automating your account. Nothing is sent to Discord, no credentials
are read or stored, and no user token is involved. It is the same as reading a web
page that happens to be logged in.

## Requirements

- **V 0.5.2 or newer** to build from source.
- **Google Chrome**, started with remote debugging. A helper script does this.
- **A signed-in Discord session** in that Chrome window.

## Setup

### 1. Start Chrome with remote debugging

```powershell
.\scripts\start-chrome.ps1
```

That opens Chrome with a **separate profile** under
`%TEMP%\chrome-discord-web`, so your daily driver is untouched and this session's
cookies are not reachable from your other windows. Override with
`$env:DISCORD_WEB_PROFILE`.

Sign in to Discord in the window that opens, then open the channel you want to
read. The server reads whichever Discord tab Chrome lists first.

Set `$env:CHROME_DEBUG_PORT` if 9222 is taken.

### 2. Build

```powershell
v.exe -cc tcc -o discord-web.exe main.v
```

### 3. Register with your MCP client

```json
{
  "mcpServers": {
    "discord_web": {
      "command": ["C:\\path\\to\\discord-web\\discord-web.exe"]
    }
  }
}
```

No environment variables are needed.

## Tools

| Tool | Purpose |
| --- | --- |
| `check_session` | Which account and server the tab is showing. Start here. |
| `list_channels` | Channels of the open server, plus the servers in the sidebar. |
| `read_messages` | Messages currently rendered in the open channel. |
| `scroll_up` | Scroll the channel to the top so Discord loads older messages. |
| `read_threads` | Posts in an open forum channel, with reply counts. |
| `page_status` | What the tab is showing, to tell empty from still-loading. |

A sensible sequence:

```
check_session → list_channels → read_messages
scroll_up → read_messages        # for older messages, repeat as needed
```

## Limits

These are properties of reading a rendered page, not bugs to be worked around.

- **Only the open tab is read.** To read a different channel, open it in the
  browser first. There is no navigation: the server will not click around, so it
  cannot be made to navigate somewhere and get stuck.
- **Only loaded messages are visible.** Discord fetches history on demand, so
  use `scroll_up` and re-read to walk backwards. A long walk means many round
  trips.
- **No search.** Discord's search needs the API. This reads what is on screen.
- **Forum posts are lists, not threads.** `read_threads` returns titles, authors,
  reply counts and previews. Opening one post to read it is a browser action.
- **Rendered text only.** Markdown, embeds and code blocks come through as the
  visible text; formatting and attachments are flattened.

## Security

Attaching to a real profile opens the DevTools endpoint on `127.0.0.1:9222`, which
means any local process can read and drive that browser window. The helper script
uses a throwaway profile to avoid putting your daily driver in that position.

Sign-in is manual on purpose: the script does not accept a password, and this
project never asks for one.

## Implementation

```
main.v                MCP server: tool registration, output formatting
discord/parse.v       probe result → V structs
discord/web.v         embeds the probe scripts
discord/js/*.js       the probes: session, list, messages, threads, scroll, status
cdp/client.v          Runtime.evaluate over the debugger WebSocket
cdp/http.v            loopback HTTP client for /json/list
cdp/endpoint.v        picks the Discord tab to attach to
```

The probes live as `.js` files rather than V string literals: a V raw string
cannot hold the quotes and backslashes these DOM queries need, and as separate
files they stay syntax-highlighted. `$embed_file` bakes them into the binary, so
the built server needs nothing from the source tree.

### Notes on Discord's DOM

Two details shaped the message probe, and both are visible on screen:

- Consecutive messages from one person omit the author header, and grouped
  messages omit the timestamp. Both are carried forward from the previous item,
  matching what a reader sees.
- Class names are hashed (`messageListItem__5126c`) and change between builds, so
  every selector keys off `data-list-item-id`, `aria-label` and `time[datetime]`,
  which are stable.

Forum posts needed more work: the sidebar shares the `h3` element, so the
threads probe scopes itself to the pane under the "Threads" heading, then to each
post's own `li`, so one post's reply count cannot leak into the next.

### Notes on V

Two compiler issues shaped the CDP client, both worked around rather than
patched:

- `json2` miscompiles a sum-typed field reached through a `@[json: camelCase]`
  struct, producing `json__Any undeclared` in the C output. Chrome's parameter
  names are camelCase and V forbids uppercase in field names, so the request
  envelope is written by hand and the reply is read out of a generic object.
- Chrome evaluates `Runtime.evaluate` as an *expression*, so a probe starting
  with a line comment would comment out everything. Every probe is wrapped in
  parentheses.

## Relationship to torabot

[`torabot`](https://github.com/metif12/torabot) is the other approach: a real bot
using the official API. It can search, page through history without rendering, and
read any server the bot was invited to, but inviting it needs Manage Server.

Use torabot when you can invite the bot. Use this when you cannot.

## Licence

MIT.