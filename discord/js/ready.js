// ready_probe reports whether a channel or thread has finished loading.
//
// After a navigation Discord shows the shell first and fills in the message list
// a moment later, so a read taken too early sees an empty page. This is polled
// until it says ok, at which point the channel is readable.
() => {
  const items = document.querySelectorAll('[id^="chat-messages-"]');
  const href = location.href;
  // A route without a channel id is Discord's home or a DM placeholder.
  const routed = /\/channels\/\d+\/\d+/.test(href);
  return JSON.stringify({
    ok: items.length > 0 || !routed,
    rendered: items.length,
    url: href
  });
}