// find_thread_probe locates a forum post by its title and reports where to click.
//
// It only reports coordinates. Opening a post needs a trusted click, and a
// synthetic MouseEvent on the heading does not route through React's handler the
// way a real click does, so the click has to come from the CDP client as
// Input.dispatchMouseEvent. That is also why the post's heading is scrolled into
// view first: the coordinates are only meaningful if the element is on screen.
//
// The search is scoped to the threads pane. A sidebar category can share a name
// with a post, and clicking that navigates somewhere useless.
(title) => {
  const want = (title || '').trim().toLowerCase();
  if (!want) return JSON.stringify({ ok: false, reason: 'no title given' });

  const heading = [...document.querySelectorAll('h2')].find((h) =>
    /threads/i.test(h.textContent)
  );
  if (!heading) {
    return JSON.stringify({
      ok: false,
      reason: 'the open channel is not a forum, so it has no posts to open'
    });
  }

  // Walk out until the subtree holds more than one post heading.
  let pane = heading;
  for (let i = 0; i < 12 && pane; i++) {
    pane = pane.parentElement;
    if (pane && pane.querySelectorAll('h3').length > 1) break;
  }
  if (!pane) return JSON.stringify({ ok: false, reason: 'no threads pane found' });

  const titles = [...pane.querySelectorAll('h3')].map((h) => h.textContent.trim());
  let match = titles.find((t) => t.toLowerCase() === want);
  if (!match) {
    // Titles get truncated in the pane, so fall back to a prefix match.
    match = titles.find((t) => t.toLowerCase().startsWith(want));
  }
  if (!match) {
    return JSON.stringify({
      ok: false,
      reason: 'no post titled "' + title + '"',
      available: titles.slice(0, 20)
    });
  }

  const target = [...pane.querySelectorAll('h3')].find(
    (h) => h.textContent.trim() === match
  );
  target.scrollIntoView({ block: 'center' });

  const r = target.getBoundingClientRect();
  return JSON.stringify({
    ok: true,
    opened: match,
    x: Math.round(r.left + r.width / 2),
    y: Math.round(r.top + r.height / 2),
    width: Math.round(r.width)
  });
}