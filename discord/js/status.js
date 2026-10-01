// page_status_probe reports what the tab is showing.
//
// This distinguishes three states that look the same from the outside: a channel
// that is genuinely empty, a tab that has not finished loading, and a tab that is
// on the login page.
(() => {
  const list =
    document.querySelector('[class*="messageList"]') ||
    document.querySelector('[class*="chatContent"]');
  const msgCount = document.querySelectorAll('[id^="chat-messages-"]').length;

  const header =
    document.querySelector('header h2') ||
    document.querySelector('[class*="channelName"]');
  let channelName = '';
  if (header) {
    const label = header.getAttribute('aria-label') || '';
    channelName = label ? label.split('|')[1] || label : header.textContent.trim();
  }

  return JSON.stringify({
    url: location.href,
    title: document.title,
    channel_name: channelName,
    message_count: msgCount,
    has_list: !!list,
    scroll_height: list ? list.scrollHeight : 0,
    shows_empty_state: /no messages yet|this is the beginning/i.test(
      document.body.innerText
    ),
    is_login_page: location.pathname === '/login'
  });
})()