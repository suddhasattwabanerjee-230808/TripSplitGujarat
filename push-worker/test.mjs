// Tests for worker.js (node push-worker/test.mjs): sign-in token checks with a
// throwaway RSA key, and Firestore REST decoding. worker.js only exports the
// Worker (Cloudflare treats other exports as entrypoints), so this imports a
// temporary copy with its helpers exported.
import { readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import assert from 'node:assert/strict';

const copy = join(tmpdir(), `tripsplit-worker-${process.pid}.mjs`);
writeFileSync(copy, readFileSync(new URL('./worker.js', import.meta.url), 'utf8') +
  '\nexport { verifyIdToken, setJwks, signJwt, fields, b64url };\n');
const { verifyIdToken, setJwks, signJwt, fields, b64url } = await import(copy);
const { privateKey, publicKey } = await crypto.subtle.generateKey(
  { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
const pkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', privateKey));
const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8)).match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----\n`;
const jwk = { ...(await crypto.subtle.exportKey('jwk', publicKey)), kid: 'k1', alg: 'RS256', use: 'sig' };
setJwks([jwk]);

// A Firebase-style ID token: signJwt makes {alg,typ}; add the kid like Google does.
async function idToken(claims, kid = 'k1') {
  const jwt = await signJwt(claims, pem);
  const [, body] = jwt.split('.');
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'RS256', kid, typ: 'JWT' })));
  const key = await crypto.subtle.importKey('pkcs8', pkcs8, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${body}`)));
  return `${header}.${body}.${b64url(sig)}`;
}
const now = Math.floor(Date.now() / 1000);
const good = { aud: 'tripsplit-237a5', iss: 'https://securetoken.google.com/tripsplit-237a5', sub: 'uidA', iat: now, exp: now + 3600 };

assert.equal(await verifyIdToken(await idToken(good), 'tripsplit-237a5'), 'uidA');
const rejects = async (p, why) => assert.rejects(p, (e) => e.status === 401, why);
await rejects(verifyIdToken(await idToken({ ...good, aud: 'other' }), 'tripsplit-237a5'), 'wrong project');
await rejects(verifyIdToken(await idToken({ ...good, exp: now - 10 }), 'tripsplit-237a5'), 'expired');
await rejects(verifyIdToken(await idToken(good, 'nope'), 'tripsplit-237a5'), 'unknown kid');
const t = await idToken(good); const [h, p, s] = t.split('.');
const forged = b64url(new TextEncoder().encode(JSON.stringify({ ...good, sub: 'attacker' })));
await rejects(verifyIdToken(`${h}.${forged}.${s}`, 'tripsplit-237a5'), 'tampered payload');
await rejects(verifyIdToken('', 'tripsplit-237a5'), 'no token');

// Firestore REST decoding
assert.deepEqual(fields({
  name: { stringValue: 'Gujarat' }, amount: { doubleValue: 1840.5 }, n: { integerValue: '3' },
  memberIds: { arrayValue: { values: [{ stringValue: 'a' }, { stringValue: 'b' }] } },
  members: { mapValue: { fields: { a: { mapValue: { fields: { name: { stringValue: 'A' }, photoUrl: { nullValue: null } } } } } } },
  createdAt: { timestampValue: '2026-10-21T10:00:00Z' },
}), { name: 'Gujarat', amount: 1840.5, n: 3, memberIds: ['a', 'b'], members: { a: { name: 'A', photoUrl: null } }, createdAt: '2026-10-21T10:00:00Z' });

console.log('worker tests: all passed');
