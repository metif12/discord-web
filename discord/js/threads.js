// threads_probe reads the post list of an open forum channel.
//
// A forum's sidebar also contains headings, so the query is scoped to the
// threads pane: the element carrying the "Threads" heading, walking up until the
// ancestor holds more than one post heading. Without that scope the sidebar's
// category headings are picked up instead of the posts.
(() => {
  const heading = Array.prototype.slice.call(document.querySelectorAll('h2')).find((h) =>
    /threads/i.test(h.textContent)
  );
  if (!heading) {
    return JSON.stringify({ url: location.href, threads: [], error: 'not a forum channel' });
  }

  let pane = heading;
  for (let i = 0; i < 10 && pane; i++) {
    pane = pane.parentElement;
    if (pane && pane.querySelectorAll('h3').length > 1) break;
  }
  if (!pane) {
    return JSON.stringify({ url: location.href, threads: [], error: 'threads pane not found' });
  }

  // Each post is a sibling <li class="card_..."> inside the list container. There
    // is no <ul> in the way, so the container is found from the first post's
    // parent. Scoping to each li keeps one post's button from leaking into the
    // next one's reply count.
  const cards = pane.querySelectorAll('li');
  if (cards.length === 0) {
    return JSON.stringify({ url: location.href, threads: [], error: 'no post cards found' });
  }

  const out = [];
  Array.prototype.forEach.call(cards, (li) => {
      const h = li.querySelector('h3');
      if (!h) return;
      const title = h.textContent.trim();
      if (!title) return;

      // The card's own button reads "Post <title>, 3,127 messages".
      let count = 0;
      const labelled = Array.prototype.slice
        .call(li.querySelectorAll('button[aria-label], [aria-label]'))
        .map((el) => el.getAttribute('aria-label') || '')
        .find((l) => /messages?$/i.test(l));
      if (labelled) {
        const m = labelled.match(/([\d,]+)\s+messages?/i);
        if (m) count = parseInt(m[1].replace(/,/g, ''), 10);
      }

      let author = '';
      const a = li.querySelector('a[href*="/users/"]');
      if (a) {
        author = (a.getAttribute('aria-label') || a.textContent || '')
          .replace(/,\s*post author$/i, '')
          .replace(/^@/, '')
          .trim();
      }

      let posted = '';
      const t = li.querySelector('time[datetime]');
      if (t) posted = t.getAttribute('datetime') || '';

      const text = li.innerText || '';

      // The preview is what follows the title and the "Author:" line, so strip
      // both rather than echoing the heading back to the caller.
      let preview = text.replace(/\s+/g, ' ');
      if (preview.startsWith(title)) preview = preview.slice(title.length);
      preview = preview.replace(/^\s*[^\s:]{1,40}\s*:\s*/, '').trim();
      if (count === 0) {
        const stats = text.match(/([\d,]+)\s+messages?/i);
        if (stats) count = parseInt(stats[1].replace(/,/g, ''), 10);
      }

      out.push({
        name: title,
        author: author,
        message_count: count,
        posted: posted,
        preview: preview.slice(0, 400)
      });
    });

    return JSON.stringify({ url: location.href, count: out.length, threads: out });
})()