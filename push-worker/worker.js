// TripSplit push relay: a Cloudflare Worker (free plan, no card).
//
// The app has no server, and Firebase Cloud Messaging can only be sent with a
// service-account key, which must never ship inside the APK. So when someone
// adds an expense, their app POSTs {tripId, expenseId} here with their
// Firebase ID token. This Worker checks the token, checks they really just
// added that expense, and sends every other member of the trip a
// high-priority data push; their phones show it even when TripSplit is
// closed and the screen is locked (see lib/expense_notifier.dart).
//
// Secret (Workers → Settings → Variables and Secrets): SERVICE_ACCOUNT = the
// whole JSON key from Firebase console → Project settings → Service accounts.

const JWKS_URL = 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
const SCOPES = 'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging';
const MAX_AGE_MS = 10 * 60 * 1000; // only fresh expenses: old ones can't be re-announced

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') return new Response('TripSplit push relay\n');
    try {
      const sa = JSON.parse(env.SERVICE_ACCOUNT);
      const projectId = sa.project_id;
      const uid = await verifyIdToken((request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, ''), projectId);
      const { tripId, expenseId } = await request.json();
      if (!isId(tripId) || !isId(expenseId)) throw httpError(400, 'bad request');

      const token = await accessToken(sa);
      const docs = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

      // The sender's write may still be on its way: give it a few seconds.
      let expense = null;
      for (let i = 0; i < 4 && !expense; i++) {
        expense = await getDoc(`${docs}/trips/${tripId}/expenses/${expenseId}`, token);
        if (!expense) await sleep(1500);
      }
      if (!expense) throw httpError(404, 'expense not found');
      if (expense.paidBy !== uid) throw httpError(403, 'not your expense');
      const created = Date.parse(expense.createdAt || '');
      if (!created || Date.now() - created > MAX_AGE_MS) throw httpError(409, 'expense is not new');

      const trip = await getDoc(`${docs}/trips/${tripId}`, token);
      if (!trip || !(trip.memberIds || []).includes(uid)) throw httpError(403, 'not on this trip');
      const recipients = trip.memberIds.filter((id) => id !== uid);
      if (!recipients.length) return json({ sent: 0 });

      const users = await batchGet(projectId, recipients.map((id) => `users/${id}`), token);
      const payer = (trip.members || {})[uid] || {};
      const data = {
        kind: 'expense',
        tripId,
        tripName: trip.name || '',
        expenseId,
        description: expense.description || '',
        amount: String(expense.amount ?? 0),
        category: expense.category || '',
        location: expense.location || '',
        date: expense.date || '',
        paidBy: uid,
        payerName: payer.name || expense.paidByName || 'Someone',
        // A push carries ~4 KB: web photos only. Picked photos are data: URIs,
        // which the phone reads from the trip instead.
        payerPhoto: /^https?:/.test(payer.photoUrl || '') ? payer.photoUrl : '',
        shares: JSON.stringify(expense.shares || {}),
        createdAt: String(created),
      };

      const sends = [];
      for (const [i, user] of users.entries()) {
        for (const fcmToken of (user && user.fcmTokens) || []) {
          sends.push(sendPush(projectId, token, fcmToken, { ...data, to: recipients[i] }));
        }
      }
      const results = await Promise.all(sends);
      return json({ sent: results.filter(Boolean).length, of: results.length });
    } catch (e) {
      return json({ error: String(e.message || e) }, e.status || 500);
    }
  },
};

// --- Firebase ID tokens --------------------------------------------------------------

let jwks = null;
let jwksAt = 0;

/** The uid in a valid Firebase ID token for this project; throws 401 otherwise. */
async function verifyIdToken(idToken, projectId, now = Date.now()) {
  const [h, p, s] = (idToken || '').split('.');
  if (!s) throw httpError(401, 'sign in first');
  const header = JSON.parse(text(b64urlBytes(h)));
  const payload = JSON.parse(text(b64urlBytes(p)));
  if (!jwks || now - jwksAt > 3600e3) {
    jwks = (await (await fetch(JWKS_URL)).json()).keys;
    jwksAt = now;
  }
  const jwk = jwks.find((k) => k.kid === header.kid);
  if (!jwk || header.alg !== 'RS256') throw httpError(401, 'unknown signing key');
  const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, b64urlBytes(s), new TextEncoder().encode(`${h}.${p}`));
  const t = now / 1000;
  if (!ok || payload.aud !== projectId || payload.iss !== `https://securetoken.google.com/${projectId}` ||
      !(payload.exp > t) || !payload.sub) {
    throw httpError(401, 'invalid sign-in');
  }
  return payload.sub;
}

/** Test hook: use these keys instead of Google's. */
function setJwks(keys, now = Date.now()) {
  jwks = keys;
  jwksAt = now;
}

// --- Service account → Google access token ------------------------------------

let cached = null;

async function accessToken(sa) {
  if (cached && cached.exp > Date.now() + 60e3) return cached.token;
  const now = Math.floor(Date.now() / 1000);
  const assertion = await signJwt(
    { iss: sa.client_email, scope: SCOPES, aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600 },
    sa.private_key,
  );
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${assertion}`,
  });
  const j = await r.json();
  if (!j.access_token) throw new Error(`Google token: ${JSON.stringify(j)}`);
  cached = { token: j.access_token, exp: Date.now() + (j.expires_in - 60) * 1000 };
  return cached.token;
}

/** An RS256 JWT signed with a PEM (PKCS#8) private key. */
async function signJwt(claims, privateKeyPem) {
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const body = b64url(new TextEncoder().encode(JSON.stringify(claims)));
  const der = Uint8Array.from(atob(privateKeyPem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '')), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${body}`));
  return `${header}.${body}.${b64url(new Uint8Array(sig))}`;
}

// --- Firestore REST ----------------------------------------------------------------

async function getDoc(url, token) {
  const r = await fetch(url, { headers: { authorization: `Bearer ${token}` } });
  if (r.status === 404) return null;
  if (!r.ok) throw new Error(`Firestore ${r.status}: ${await r.text()}`);
  return fields((await r.json()).fields || {});
}

/** Documents by path, in order (null where missing). */
async function batchGet(projectId, paths, token) {
  const root = `projects/${projectId}/databases/(default)/documents`;
  const r = await fetch(`https://firestore.googleapis.com/v1/${root}:batchGet`, {
    method: 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ documents: paths.map((p) => `${root}/${p}`) }),
  });
  if (!r.ok) throw new Error(`Firestore ${r.status}: ${await r.text()}`);
  const byName = new Map();
  for (const item of await r.json()) {
    if (item.found) byName.set(item.found.name, fields(item.found.fields || {}));
  }
  return paths.map((p) => byName.get(`${root}/${p}`) || null);
}

/** Firestore's typed REST values → plain JS. */
function fields(f) {
  const out = {};
  for (const [k, v] of Object.entries(f)) out[k] = value(v);
  return out;
}

function value(v) {
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('mapValue' in v) return fields(v.mapValue.fields || {});
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(value);
  return null;
}

// --- FCM -----------------------------------------------------------------------------

async function sendPush(projectId, token, fcmToken, data) {
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    // Data-only + high priority: the app draws the notification itself (with
    // the payer's photo) and Android delivers it right away, even in Doze.
    body: JSON.stringify({ message: { token: fcmToken, data, android: { priority: 'HIGH', ttl: '86400s' } } }),
  });
  return r.ok;
}

// --- Helpers -------------------------------------------------------------------------

const isId = (s) => typeof s === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(s);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const text = (bytes) => new TextDecoder().decode(bytes);
const json = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });

function httpError(status, message) {
  const e = new Error(message);
  e.status = status;
  return e;
}

function b64url(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function b64urlBytes(s) {
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4);
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}
