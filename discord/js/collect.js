// read_probe snapshots the messages currently in the DOM.
//
// It only reports what is rendered, because that is all the virtualised list
// holds at any moment. Accumulating a channel's history means calling this
// repeatedly while the driver scrolls, and letting the caller deduplicate by
// message id. Attempting the scroll here would not work: Discord's scroller
// ignores synthetic events and overwrites scrollTop, so scrolling has to arrive
// as a trusted input event from outside the page.
() => {
  const items = Array.prototype.slice.call(
    document.querySelectorAll('[id^="chat-messages-"]')
  );

  // Discord renders consecutive messages from the same author without repeating
  // the avatar and name, so the author and timestamp carry forward.
  let lastAuthor = '';
  let lastStamp = '';
  const messages = [];

  for (const el of items) {
    const nameEl = el.querySelector('span[class*="username"]');
    if (nameEl) lastAuthor = nameEl.textContent.trim().replace(/^@/, '');
    const timeEl = el.querySelector('time[datetime]');
    if (timeEl) lastStamp = timeEl.getAttribute('datetime') || '';

    let text = '';
    const content = el.querySelector('div[id^="message-content-"]');
    if (content) text = content.innerText.trim();
    // A post with only an embed or attachment has no message-content element.
    if (!text) {
      const rich = el.querySelector('[class*="embedContent"], [class*="attachment"], [class*="media"]');
      if (rich) text = rich.innerText.trim().slice(0, 400);
    }
    if (!text) continue;

    // The id looks like chat-messages-<channel>-<snowflake>; the snowflake is
    // the message id and is enough for dedupe and chronological ordering.
    const raw = el.id.replace('chat-messages-', '');
    const parts = raw.split('-');
    messages.push({
      id: parts.length > 1 ? parts[parts.length - 1] : raw,
      author: lastAuthor,
      timestamp: lastStamp,
      content: text
    });
  }

  return JSON.stringify({ rendered: items.length, messages: messages });
}