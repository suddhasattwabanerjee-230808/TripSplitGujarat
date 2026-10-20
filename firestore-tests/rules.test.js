// Security-rule tests for firestore.rules, run against the local emulator:
//   cd firestore-tests && npm install && npm test
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  arrayUnion, collection, collectionGroup, deleteDoc, doc, getDoc, getDocs, increment, limit,
  orderBy, query, setDoc, updateDoc, where, writeBatch,
} from 'firebase/firestore';

let env;
const db = (uid) => env.authenticatedContext(uid).firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-tripsplit',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 },
  });
});
after(() => env.cleanup());

// Trip t1 with members a and b, invite code ABCDEF, one expense paid by a.
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const fs = ctx.firestore();
    await setDoc(doc(fs, 'trips/t1'), {
      name: 'Gujarat', inviteCode: 'ABCDEF', createdBy: 'a', memberIds: ['a', 'b'],
      members: { a: { name: 'A' }, b: { name: 'B' } }, totalSpent: 100, paid: { a: 100 }, owed: { a: 50, b: 50 },
    });
    await setDoc(doc(fs, 'invites/ABCDEF'), { tripId: 't1' });
    await setDoc(doc(fs, 'trips/t1/expenses/e1'), {
      tripId: 't1', paidBy: 'a', amount: 100, description: 'Dinner', memberIds: ['a', 'b'],
      shares: { a: 50, b: 50 }, createdAt: new Date(),
    });
    await setDoc(doc(fs, 'users/a'), { name: 'A', email: 'a@x.com', upiId: 'a@okhdfc' });
  });
});

test('outsiders cannot read a trip or its expenses', async () => {
  await assertFails(getDoc(doc(db('x'), 'trips/t1')));
  await assertFails(getDocs(collection(db('x'), 'trips/t1/expenses')));
  await assertSucceeds(getDoc(doc(db('b'), 'trips/t1')));
  await assertSucceeds(getDocs(collection(db('b'), 'trips/t1/expenses')));
});

test('trip lists must be filtered to your own trips', async () => {
  await assertFails(getDocs(collection(db('a'), 'trips')));
  await assertSucceeds(getDocs(query(collection(db('a'), 'trips'), where('memberIds', 'array-contains', 'a'))));
});

test('profiles are private to their owner', async () => {
  await assertSucceeds(getDoc(doc(db('a'), 'users/a')));
  await assertFails(getDoc(doc(db('b'), 'users/a')));
  await assertFails(getDocs(collection(db('b'), 'users')));
  await assertFails(setDoc(doc(db('b'), 'users/a'), { name: 'Hacked' }));
});

test('joining with a code adds only yourself', async () => {
  const x = db('x');
  await assertSucceeds(getDoc(doc(x, 'invites/ABCDEF')));
  await assertFails(getDocs(collection(x, 'invites')));
  await assertFails(updateDoc(doc(x, 'trips/t1'), { memberIds: arrayUnion('x', 'y'), 'members.x': { name: 'X' } }));
  await assertFails(updateDoc(doc(x, 'trips/t1'), { memberIds: arrayUnion('x'), 'members.x': { name: 'X' }, name: 'Mine' }));
  await assertFails(updateDoc(doc(x, 'trips/t1'), { memberIds: arrayUnion('x'), 'members.a': { name: 'Evil' } }));
  await assertSucceeds(updateDoc(doc(x, 'trips/t1'), { memberIds: arrayUnion('x'), 'members.x': { name: 'X' } }));
  await assertSucceeds(getDoc(doc(x, 'trips/t1')));
});

test('members cannot remove people or edit someone else’s entry', async () => {
  const b = db('b');
  await assertFails(updateDoc(doc(b, 'trips/t1'), { memberIds: ['b'] }));
  await assertFails(updateDoc(doc(b, 'trips/t1'), { 'members.a': { name: 'Changed' } }));
  await assertFails(updateDoc(doc(b, 'trips/t1'), { inviteCode: 'ZZZZZZ' }));
  await assertSucceeds(updateDoc(doc(b, 'trips/t1'), { 'members.b': { name: 'B2', upiId: 'b@ybl' } }));
  await assertSucceeds(updateDoc(doc(b, 'trips/t1'), { totalSpent: increment(10), 'paid.b': increment(10) }));
});

test('only the payer edits or deletes an expense; you can only add as yourself', async () => {
  await assertFails(updateDoc(doc(db('b'), 'trips/t1/expenses/e1'), { amount: 1 }));
  await assertFails(deleteDoc(doc(db('b'), 'trips/t1/expenses/e1')));
  await assertSucceeds(updateDoc(doc(db('a'), 'trips/t1/expenses/e1'), { amount: 120 }));
  await assertFails(setDoc(doc(db('b'), 'trips/t1/expenses/e2'), { tripId: 't1', paidBy: 'a', amount: 5 }));
  await assertFails(setDoc(doc(db('x'), 'trips/t1/expenses/e3'), { tripId: 't1', paidBy: 'x', amount: 5 }));
  await assertSucceeds(setDoc(doc(db('b'), 'trips/t1/expenses/e4'), {
    tripId: 't1', paidBy: 'b', amount: 5, memberIds: ['a', 'b'], shares: { a: 2.5, b: 2.5 },
  }));
  await assertSucceeds(deleteDoc(doc(db('a'), 'trips/t1/expenses/e1')));
});

test('the bell query only returns your trips’ expenses', async () => {
  const feed = (uid) => query(collectionGroup(db(uid), 'expenses'), where('memberIds', 'array-contains', uid),
    orderBy('createdAt', 'desc'), limit(50));
  await assertSucceeds(getDocs(feed('b')));
  await assertFails(getDocs(collectionGroup(db('x'), 'expenses')));
});

test('creating a trip with its invite code in one batch', async () => {
  const c = db('c');
  const batch = writeBatch(c);
  batch.set(doc(c, 'trips/t2'), { name: 'New', inviteCode: 'QWERTY', createdBy: 'c', memberIds: ['c'], members: { c: { name: 'C' } } });
  batch.set(doc(c, 'invites/QWERTY'), { tripId: 't2' });
  await assertSucceeds(batch.commit());
  await assertFails(setDoc(doc(c, 'invites/HIJACK'), { tripId: 't1' }));
  await assertFails(setDoc(doc(c, 'trips/t3'), { name: 'Sneaky', createdBy: 'c', memberIds: ['c', 'a'] }));
});

// Invite by email.
const asEmail = (uid, email) => env.authenticatedContext(uid, { email, email_verified: true }).firestore();
const invite = (over = {}) => ({
  email: 'friend@gmail.com', tripId: 't1', tripName: 'Gujarat', inviteCode: 'ABCDEF',
  invitedBy: 'a', invitedByName: 'A', ...over,
});

test('only a member can invite by email, with the trip\'s real code', async () => {
  await assertSucceeds(setDoc(doc(db('a'), 'emailInvites/t1_friend@gmail.com'), invite()));
  await assertFails(setDoc(doc(db('x'), 'emailInvites/t1_friend@gmail.com'), invite({ invitedBy: 'x' })));
  await assertFails(setDoc(doc(db('a'), 'emailInvites/t1_friend@gmail.com'), invite({ invitedBy: 'b' })));
  await assertFails(setDoc(doc(db('a'), 'emailInvites/t1_friend@gmail.com'), invite({ inviteCode: 'ZZZZZZ' })));
  await assertFails(setDoc(doc(db('a'), 'emailInvites/t1_friend@gmail.com'), invite({ email: 'Friend@Gmail.com' })));
});

test('only the invited Google account (and the inviter) can see and clear an invite', async () => {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'emailInvites/i1'), invite()));
  const mine = (fs, email) => query(collection(fs, 'emailInvites'), where('email', '==', email));
  await assertSucceeds(getDocs(mine(asEmail('f', 'friend@gmail.com'), 'friend@gmail.com')));
  await assertSucceeds(getDocs(mine(asEmail('f', 'Friend@Gmail.com'), 'friend@gmail.com')));
  await assertFails(getDocs(mine(asEmail('y', 'other@gmail.com'), 'friend@gmail.com')));
  await assertFails(getDocs(collection(asEmail('y', 'other@gmail.com'), 'emailInvites')));
  await assertFails(getDoc(doc(db('b'), 'emailInvites/i1')));
  await assertSucceeds(getDoc(doc(db('a'), 'emailInvites/i1')));
  await assertFails(deleteDoc(doc(asEmail('y', 'other@gmail.com'), 'emailInvites/i1')));
  await assertSucceeds(deleteDoc(doc(asEmail('f', 'friend@gmail.com'), 'emailInvites/i1')));
});

test('an unverified email address gets nothing', async () => {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'emailInvites/i1'), invite()));
  const unverified = env.authenticatedContext('f', { email: 'friend@gmail.com', email_verified: false }).firestore();
  await assertFails(getDocs(query(collection(unverified, 'emailInvites'), where('email', '==', 'friend@gmail.com'))));
});
