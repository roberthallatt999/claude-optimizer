// Passcode gate for a noslop web-version page. Serves the built page (ASSETS) only to a visitor
// who has entered PASSCODE, a Worker secret. Without the secret every request gets a 503, so a
// forgotten `secret put` never leaves the page open. Every response says noindex.
//
// BASE_PATH ("/q3-traffic-7f3a9c2e") puts the page under its own path of the shared host
// (share.cps.ca/q3-traffic-7f3a9c2e/), so many pages share one host name. Empty serves the root.

const COOKIE = 'noslop_gate';
const MAX_AGE = 60 * 60 * 24 * 30;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const base = (env.BASE_PATH ?? '').replace(/\/+$/, '');
    if (!env.PASSCODE) {
      return page(env, base, 'This page isn’t ready yet.', 503, false);
    }
    if (env.EXPIRES && new Date().toISOString().slice(0, 10) > env.EXPIRES) {
      return page(env, base, `This page expired on ${env.EXPIRES}. Ask the sender for a new link.`, 410, false);
    }
    if (base && url.pathname === base) {
      // Relative asset links only resolve under the trailing slash.
      return noindex(Response.redirect(`${url.origin}${base}/${url.search}`, 301));
    }
    if (base && !url.pathname.startsWith(`${base}/`)) {
      return page(env, base, 'There’s no page here.', 404, false);
    }
    const token = await gateToken(env.PASSCODE, `${url.host}${base}`);

    if (url.pathname === `${base}/__unlock` && request.method === 'POST') {
      const form = await request.formData();
      const tried = String(form.get('passcode') ?? '');
      if (!(await sameText(tried, env.PASSCODE))) {
        return page(env, base, 'That passcode didn’t work. Check it and try again.', 401, true);
      }
      return noindex(new Response(null, {
        status: 303,
        headers: {
          Location: `${base}/`,
          // Scoped to this page's path, so each page on the shared host keeps its own passcode.
          'Set-Cookie': `${COOKIE}=${token}; Path=${base}/; Max-Age=${MAX_AGE}; HttpOnly; Secure; SameSite=Lax`,
        },
      }));
    }

    if (readCookie(request, COOKIE) !== token) {
      return page(env, base, '', 401, true);
    }
    // The built files sit at the root of ASSETS, so drop the page's path before looking them up.
    const assetUrl = new URL(request.url);
    assetUrl.pathname = assetUrl.pathname.slice(base.length) || '/';
    return noindex(await env.ASSETS.fetch(new Request(assetUrl, request)));
  },
};

// The cookie proves the passcode without holding it, and changes when the passcode changes.
async function gateToken(passcode, scope) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(passcode),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${scope}:noslop-gate-v1`));
  return [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// Compares digests so the time taken doesn't reveal how much of the passcode matched.
async function sameText(a, b) {
  const digest = async (s) => new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)));
  const [x, y] = await Promise.all([digest(a), digest(b)]);
  return crypto.subtle.timingSafeEqual(x, y);
}

// Another page's cookie has the same name but a different Path, so the browser never sends it
// here; any value that isn't this page's token simply fails.
function readCookie(request, name) {
  const header = request.headers.get('Cookie') ?? '';
  const match = header.split(/;\s*/).find((part) => part.startsWith(`${name}=`));
  return match ? match.slice(name.length + 1) : '';
}

function noindex(response) {
  const copy = new Response(response.body, response);
  copy.headers.set('X-Robots-Tag', 'noindex, nofollow');
  return copy;
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

// The passcode screen, in the same look as the page behind it (style kit, WCAG AA colours).
function page(env, base, message, status, withForm) {
  const title = escapeHtml(env.PAGE_TITLE || 'Private page');
  const note = message ? `<p class="note" role="alert">${escapeHtml(message)}</p>` : '';
  const form = withForm ? `
      <form method="post" action="${escapeHtml(base)}/__unlock">
        <label for="passcode">Passcode</label>
        <input id="passcode" name="passcode" type="password" autocomplete="current-password" required autofocus>
        <button type="submit">Open the page</button>
      </form>` : '';
  const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex, nofollow">
  <title>${title}</title>
  <style>
    :root { --bg: #fff; --card: #fff; --text: rgba(0,0,0,.9); --text-2: rgba(0,0,0,.6);
      --line: rgba(0,0,0,.12); --shadow: 0 4px 20px rgba(0,0,0,.075); --clay-strong: #b5502f; --bad: #a42528;
      --serif: Georgia, "Times New Roman", serif;
      --sans: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
    @media (prefers-color-scheme: dark) { :root { --bg: #151515; --card: #1f1f1f; --text: rgba(255,255,255,.93);
      --text-2: rgba(255,255,255,.57); --line: rgba(255,255,255,.12); --shadow: none; --bad: #f17778; color-scheme: dark; } }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: var(--bg); color: var(--text);
      font: 16px/1.55 var(--sans); padding: 16px; box-sizing: border-box; }
    main { width: 100%; max-width: 360px; background: var(--card); border: 1px solid var(--line); border-radius: 14px;
      box-shadow: var(--shadow); padding: 24px; box-sizing: border-box; }
    h1 { font: 400 22px/1.3 var(--serif); margin: 0 0 16px; }
    label { display: block; font-size: 13px; color: var(--text-2); margin-bottom: 6px; }
    input { width: 100%; box-sizing: border-box; font: 16px var(--sans); background: var(--card); color: var(--text);
      border: 1px solid var(--line); border-radius: 10px; padding: 10px 12px; margin-bottom: 12px; }
    button { width: 100%; font: 500 16px var(--sans); border: 0; border-radius: 10px; padding: 10px 16px;
      background: var(--clay-strong); color: #fff; cursor: pointer; }
    input:focus-visible, button:focus-visible { outline: 2px solid var(--clay-strong); outline-offset: 2px; }
    .note { color: var(--bad); font-size: 13px; margin: 0 0 12px; }
  </style>
</head>
<body>
  <main>
    <h1>${title}</h1>${note}${form}
  </main>
</body>
</html>`;
  return noindex(new Response(html, { status, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } }));
}
