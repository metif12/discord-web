// scroll_up_probe scrolls the message list to the top so Discord fetches older
// history.
//
// The message list is a virtualiser, so assigning scrollTop is not enough: the
// history fetch is triggered by a wheel event on the scroller. Both are done.
(() => {
  const list =
    document.querySelector('[class*="messageList"]') ||
    document.querySelector('[class*="chatContent"]') ||
    document.scrollingElement;
  if (!list) return JSON.stringify({ ok: false, reason: 'no message list found' });

  const before = list.scrollHeight;
  const renderedBefore = document.querySelectorAll('[id^="chat-messages-"]').length;

  list.scrollTop = 0;
  list.dispatchEvent(
    new WheelEvent('wheel', { deltaY: -2000, bubbles: true, cancelable: true })
  );

  return JSON.stringify({
    ok: true,
    rendered_before: renderedBefore,
    scroll_height_before: before,
    scroll_top: list.scrollTop
  });
})()