// history_probe reports the message list's state: which messages are rendered,
// where the scroller sits, and where its centre is so the caller can dispatch a
// trusted wheel there.
//
// This probe does not scroll. It cannot: Discord's message list is driven by its
// own scroller component, which ignores synthetic wheel events and overwrites
// scrollTop. Only a trusted Input.dispatchMouseEvent moves it, and that has to
// come from the CDP client. So this returns coordinates and the driver in
// discord/history.v does the stepping.
() => {
  const items = Array.prototype.slice.call(
    document.querySelectorAll('[id^="chat-messages-"]')
  );

  // Find the scroll container by walking up from a message and taking the first
  // ancestor whose overflow-y allows scrolling.
  let scroller = null;
  let node = items.length ? items[0] : document.body;
  for (let i = 0; i < 14 && node; i++) {
    const cs = getComputedStyle(node);
    if ((cs.overflowY === 'scroll' || cs.overflowY === 'auto') &&
        node.scrollHeight > node.clientHeight + 10) {
      scroller = node;
      break;
    }
    node = node.parentElement;
  }

  const stamps = items.map((el) => {
    const t = el.querySelector('time[datetime]');
    return t ? t.getAttribute('datetime') || '' : '';
  }).filter(Boolean);

  // Point the wheel at the middle of the scroller, which is what a human aims at.
  let cx = 0;
  let cy = 0;
  if (scroller) {
    const r = scroller.getBoundingClientRect();
    cx = Math.round(r.left + r.width / 2);
    cy = Math.round(r.top + r.height / 2);
  }

  return JSON.stringify({
    url: location.href,
    rendered: items.length,
    scroll_top: scroller ? Math.round(scroller.scrollTop) : null,
    scroll_height: scroller ? scroller.scrollHeight : null,
    client_height: scroller ? scroller.clientHeight : null,
    x: cx,
    y: cy,
    oldest_timestamp: stamps.length ? stamps[0] : '',
    newest_timestamp: stamps.length ? stamps[stamps.length - 1] : ''
  });
}