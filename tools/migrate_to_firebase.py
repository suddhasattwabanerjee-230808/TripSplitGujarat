#!/usr/bin/env python3
"""Copy TripSplit's data from nav-server's SQLite database into Firebase.

Run on nav-server (where the database is), in a venv with firebase-admin:

    python3 -m venv ~/fbmig && ~/fbmig/bin/pip install firebase-admin
    ~/fbmig/bin/python migrate_to_firebase.py --key service-account.json            # dry run
    ~/fbmig/bin/python migrate_to_firebase.py --key service-account.json --write    # for real

Safe to re-run: every document gets a fixed id derived from the old one
(users u<id>, trips t<id>, expenses e<id>), so a second run overwrites rather
than duplicates. Run it once to check, then again right before releasing the
Firebase build so nothing added in between is lost.

Google accounts are imported into Firebase Auth with uid u<id> and their
Google account id, so signing in with Google lands on the same account and
trips. Don't sign in to the Firebase build before the import, or Firebase
will already have made a different account for that Google user.
"""

import argparse
import sqlite3
from collections import defaultdict
from datetime import datetime, timezone

DEFAULT_DB = "/home/nav/tripsplit_backend/tripsplit.db"


def uid(user_id):
    return f"u{user_id}"


def server_time(value):
    """SQLite's datetime('now') text (UTC) -> aware datetime."""
    if not value:
        return datetime.now(timezone.utc)
    return datetime.strptime(value[:19], "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)


def settlements(nets, names):
    """Same greedy settle-up as the old server and the app's ledger.dart."""
    creditors = sorted([[u, n] for u, n in nets.items() if n > 0.01], key=lambda x: -x[1])
    debtors = sorted([[u, n] for u, n in nets.items() if n < -0.01], key=lambda x: x[1])
    out, i, j = [], 0, 0
    while i < len(debtors) and j < len(creditors):
        amount = round(min(-debtors[i][1], creditors[j][1]), 2)
        if amount > 0.01:
            out.append(f"{names[debtors[i][0]]} -> {names[creditors[j][0]]} {amount:.2f}")
        debtors[i][1] = round(debtors[i][1] + amount, 2)
        creditors[j][1] = round(creditors[j][1] - amount, 2)
        if abs(debtors[i][1]) < 0.01:
            i += 1
        if abs(creditors[j][1]) < 0.01:
            j += 1
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--key", required=True, help="Firebase service-account JSON (never commit it)")
    parser.add_argument("--db", default=DEFAULT_DB)
    parser.add_argument("--write", action="store_true", help="actually write (default: dry run)")
    args = parser.parse_args()

    conn = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    users = {r["id"]: dict(r) for r in conn.execute("SELECT * FROM users")}
    trips = [dict(r) for r in conn.execute("SELECT * FROM trips ORDER BY id")]
    members = defaultdict(list)
    for r in conn.execute("SELECT trip_id, user_id FROM trip_members ORDER BY joined_at, rowid"):
        members[r["trip_id"]].append(r["user_id"])
    expenses = [dict(r) for r in conn.execute("SELECT * FROM expenses ORDER BY id")]
    shares = defaultdict(dict)
    for r in conn.execute("SELECT expense_id, user_id, share_amount FROM expense_shares"):
        shares[r["expense_id"]][uid(r["user_id"])] = round(r["share_amount"], 2)

    def entry(user_id):
        u = users.get(user_id, {})
        return {"name": u.get("name") or "Someone", "photoUrl": u.get("photo_url"), "upiId": u.get("upi_id")}

    # --- Build every document -------------------------------------------------
    docs = []  # (path, data)
    for u in users.values():
        docs.append((f"users/{uid(u['id'])}", {
            "name": u["name"], "email": u.get("email"), "photoUrl": u.get("photo_url"),
            "upiId": u.get("upi_id"), "phone": u.get("phone"), "createdAt": server_time(u.get("created_at")),
        }))

    by_trip = defaultdict(list)
    for e in expenses:
        by_trip[e["trip_id"]].append(e)

    report = []
    for t in trips:
        ids = [uid(m) for m in members[t["id"]]]
        paid, owed, total = defaultdict(float), defaultdict(float), 0.0
        for e in by_trip[t["id"]]:
            paid[uid(e["paid_by"])] += e["amount"]
            for k, v in shares[e["id"]].items():
                owed[k] += v
            if (e.get("category") or "") != "Settlement":
                total += e["amount"]
            docs.append((f"trips/t{t['id']}/expenses/e{e['id']}", {
                "tripId": f"t{t['id']}", "description": e["description"], "amount": e["amount"],
                "paidBy": uid(e["paid_by"]), "paidByName": users.get(e["paid_by"], {}).get("name", "Someone"),
                "category": e.get("category"), "date": e["date"], "location": e.get("location"),
                "splitType": e.get("split_type") or "equal", "shares": shares[e["id"]],
                "memberIds": ids, "createdAt": server_time(e.get("created_at")),
            }))
        docs.append((f"trips/t{t['id']}", {
            "name": t["name"], "destination": t.get("destination"), "startDate": t.get("start_date"),
            "endDate": t.get("end_date"), "kind": t.get("kind"), "inviteCode": t["invite_code"],
            "createdBy": uid(t["created_by"]), "createdAt": server_time(t.get("created_at")),
            "memberIds": ids, "members": {uid(m): entry(m) for m in members[t["id"]]},
            "totalSpent": round(total, 2),
            "paid": {k: round(v, 2) for k, v in paid.items()},
            "owed": {k: round(v, 2) for k, v in owed.items()},
        }))
        docs.append((f"invites/{t['invite_code']}", {"tripId": f"t{t['id']}"}))
        nets = {u: round(paid[u] - owed[u], 2) for u in ids}
        names = {uid(m): users.get(m, {}).get("name", "?") for m in members[t["id"]]}
        report.append((t, len(by_trip[t["id"]]), round(total, 2), settlements(nets, names)))

    google_users = [u for u in users.values() if u.get("google_sub")]

    # --- Report ------------------------------------------------------------------
    print(f"Users: {len(users)} ({len(google_users)} with Google sign-in)")
    print(f"Trips: {len(trips)}   Expenses: {len(expenses)}   Documents to write: {len(docs)}")
    for t, count, total, settle in report:
        print(f"\n  t{t['id']} {t['name']!r}: {count} expenses, spent {total:.2f}, code {t['invite_code']}")
        for line in settle or ["everyone settled up"]:
            print(f"    {line}")
    print("\nCompare these with the old app before switching over.")
    if not args.write:
        print("\nDry run only. Re-run with --write to copy into Firebase.")
        return

    # --- Write -----------------------------------------------------------------------
    import firebase_admin
    from firebase_admin import auth, credentials, firestore

    firebase_admin.initialize_app(credentials.Certificate(args.key))
    db = firestore.client()
    for start in range(0, len(docs), 400):
        batch = db.batch()
        for path, data in docs[start:start + 400]:
            batch.set(db.document(path), data)
        batch.commit()
        print(f"  wrote {min(start + 400, len(docs))}/{len(docs)}")

    records = [
        auth.ImportUserRecord(
            uid=uid(u["id"]), email=u.get("email"), email_verified=bool(u.get("email")),
            display_name=u["name"], photo_url=u.get("photo_url"),
            provider_data=[auth.UserProvider(
                uid=u["google_sub"], provider_id="google.com", email=u.get("email"),
                display_name=u["name"], photo_url=u.get("photo_url"),
            )],
        )
        for u in google_users
    ]
    if records:
        result = auth.import_users(records)
        print(f"Auth import: {result.success_count} ok, {result.failure_count} failed")
        for err in result.errors:
            print(f"  user #{err.index}: {err.reason}")
    print("Done.")


if __name__ == "__main__":
    main()
