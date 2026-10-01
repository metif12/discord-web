// list_probe reads the sidebar: every server, and every channel of the open one.
//
// Each row's data-list-item-id identifies it:
//   guildsnav__<guild_id>        a server in the leftmost column
//   channels___channels-<guild>  the sidebar container itself
//   channels___<channel_id>      a channel
//   <guild>_<category>           the category a row belongs to
//
// The visible name comes from the row's aria-label, which reads
// "compiler-and-vlib-dev (text channel)". Class names are hashed and unstable,
// so the label is the dependable source.
(() => {
  const servers = [];
  document
    .querySelectorAll('nav[aria-label*="Servers"] [data-list-item-id^="guildsnav__"]')
    .forEach((el) => {
      const img = el.querySelector('img[alt]');
      // The pill shows an initial-letter avatar on this build, so fall back to
      // the tooltip text before giving up on the name.
      let name = img ? (img.getAttribute('alt') || '').trim() : '';
      if (!name) {
        const labelled = el.querySelector('[aria-label]');
        if (labelled) {
          name = (labelled.getAttribute('aria-label') || '')
            .replace(/\s*\(.*\)\s*$/, '')
            .trim();
        }
      }
      if (!name) name = (el.innerText || '').trim();
      servers.push({
        name: name,
        id: (el.getAttribute('data-list-item-id') || '').replace('guildsnav__', '')
      });
    });
  // The non-server entries share the same prefix shape but carry ids starting
  // with "_", so they are dropped rather than listed as servers.
  const real = [];
  servers.forEach((s) => {
    if (/^\d+$/.test(s.id)) real.push(s);
  });

  const channels = [];
  const nav = document.querySelector('nav[aria-label$="(server)"]');
  if (nav) {
    nav.querySelectorAll('[data-list-item-id]').forEach((el) => {
      const raw = el.getAttribute('data-list-item-id') || '';
      const label = el.getAttribute('aria-label') || '';

      const guildNav = raw.match(/^guildsnav__(\d+)/);
      if (guildNav) {
        channels.push({ name: '>', id: guildNav[1], kind: 'server', category: '' });
        return;
      }

      const ch = raw.match(/^channels___(\d+)$/);
      if (!ch) {
        // A category header is a row with no channel id; its label is the name.
        if (label && label !== 'Browse Channels' && !label.includes('category')) {
          // Rows shaped "<guild>_<category>" also land here and set the group.
        }
        return;
      }

      // "name (kind channel)" -> name, kind. The unread badge and the "Invite to
      // Channel" affordance leak into the aria-label, so strip both.
      const m = label.match(/^(.*?)\s*\((.*?)\)\s*$/);
      let name = m ? m[1].trim() : label.trim();
      let kindLabel = m ? m[2].trim() : '';

      name = name
        .replace(/^unread,\s*/i, '')
        .replace(/^#/, '')
        .replace(/\s*Invite to Channel\s*$/i, '')
        .trim();

      if (!name) {
        const labelEl = el.querySelector('[class*="channelName"]');
        if (labelEl) name = labelEl.textContent.trim();
      }

      let kind = 'text';
      if (/forum/i.test(kindLabel)) kind = 'forum';
      else if (/announcement/i.test(kindLabel)) kind = 'announcement';
      else if (/thread/i.test(kindLabel)) kind = 'thread';

      channels.push({ name: name, id: ch[1], kind: kind, category: '' });
    });
  }

  return JSON.stringify({ servers: real, channels: channels, url: location.href });
})()