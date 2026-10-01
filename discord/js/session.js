// session_probe reports the signed-in user, the open server, and whether the
// page is the Discord app rather than the login screen.
(() => {
  const user = document.querySelector('[class*="username"]');
  const serverName = document.querySelector(
    'nav[aria-label$="(server)"] h2, [class*="serverName"]'
  );
  return JSON.stringify({
    logged_in: location.pathname.startsWith('/channels'),
    username: user ? user.textContent.trim() : '',
    server_name: serverName ? serverName.textContent.trim() : '',
    url: location.href
  });
})()