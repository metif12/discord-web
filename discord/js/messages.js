// messages_probe reads the rendered messages of the open channel.
//
// Discord renders each message as <li id="chat-messages-<channel>-<snowflake>">.
// Two details matter for a faithful read:
//
//   - Consecutive messages from one person omit the author header, and grouped
//     messages omit the timestamp. Both are carried forward from the previous
//     item, matching what a reader sees.
//   - An attachment- or embed-only message has no content div, so the embed text
//     is used instead of dropping the message.
(limit) => {
  const bound = limit > 0 ? limit : 50;
  const items = Array.prototype.slice.call(
    document.querySelectorAll('[id^="chat-messages-"]')
  );

  const out = [];
  let lastAuthor = '';
  let lastStamp = '';

  for (const el of items) {
    const nameEl = el.querySelector('span[class*="username"]');
    if (nameEl) lastAuthor = nameEl.textContent.trim().replace(/^@/, '');
    const timeEl = el.querySelector('time[datetime]');
    if (timeEl) lastStamp = timeEl.getAttribute('datetime') || '';

    const content = el.querySelector('div[id^="message-content-"]');
    let text = content ? content.innerText.trim() : '';
    if (!text) {
      const embed = el.querySelector('[class*="embed"], [class*="attachment"]');
      text = embed ? embed.innerText.trim().slice(0, 400) : '';
    }
    if (!text) continue;

    const idAttr = el.id.replace('chat-messages-', '');
    const parts = idAttr.split('-');
    out.push({
      id: parts.length > 1 ? parts[parts.length - 1] : idAttr,
      channel_id: parts.length > 1 ? parts[0] : '',
      author: lastAuthor,
      timestamp: lastStamp,
      content: text
    });
  }

  const slice = out.length > bound ? out.slice(out.length - bound) : out;
  return JSON.stringify({
    url: location.href,
    rendered: out.length,
    count: slice.length,
    messages: slice
  });
}