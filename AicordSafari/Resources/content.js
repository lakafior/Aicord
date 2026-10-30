// Hands Discord invite pages over to Aicord: discord.gg/abc and
// discord.com/invite/abc open aicord://invite/abc, where the app shows the
// server and a Join button. Going back to the page doesn't bounce again.
(() => {
  const host = location.hostname.replace(/^(www|ptb|canary)\./, "");
  const path = location.pathname.split("/").filter(Boolean);
  let code = null;
  if (host === "discord.gg") {
    code = path[0] === "invite" ? path[1] : path[0];
  } else if ((host === "discord.com" || host === "discordapp.com") && path[0] === "invite") {
    code = path[1];
  }
  if (!code || !/^[A-Za-z0-9-]{2,64}$/.test(code)) return;

  const key = "aicord-handed-over";
  try {
    if (sessionStorage.getItem(key) === code) return;
    sessionStorage.setItem(key, code);
  } catch (_) {
    // storage blocked: hand over anyway
  }
  location.href = "aicord://invite/" + encodeURIComponent(code);
})();
