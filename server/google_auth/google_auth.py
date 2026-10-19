"""Google sign-in + profile endpoints for tripsplit_backend.

Lives next to tripsplit_server.py on nav-server, which registers it:

    from google_auth import router as google_auth_router, migrate as google_auth_migrate
    google_auth_migrate()            # in the startup hook, after init_db()
    app.include_router(google_auth_router)

Needs:  pip install google-auth requests   (in /home/nav/nav_backend/venv)

The Web application OAuth client ID is read on every request from
`google_web_client_id.txt` beside this file (or the GOOGLE_WEB_CLIENT_ID env
var), so it can be set or changed without a restart or sudo.

Sessions never expire: tripsplit_server's require_user only checks that the
token exists, which is what makes the login permanent.
"""

import os
import secrets
import sqlite3
from contextlib import contextmanager
from typing import Optional

from fastapi import APIRouter, Header, HTTPException
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from pydantic import BaseModel, Field

HERE = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.environ.get("TRIPSPLIT_DB", os.path.join(HERE, "tripsplit.db"))
CLIENT_ID_FILE = os.path.join(HERE, "google_web_client_id.txt")

router = APIRouter()
_google_request = google_requests.Request()


@contextmanager
def _db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def _web_client_id() -> str:
    try:
        with open(CLIENT_ID_FILE) as f:
            value = f.read().strip()
    except FileNotFoundError:
        value = ""
    return value or os.environ.get("GOOGLE_WEB_CLIENT_ID", "").strip()


def migrate() -> None:
    """Makes users.phone nullable and adds the Google columns; safe on every start-up."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        cols = {row["name"]: row for row in conn.execute("PRAGMA table_info(users)")}
        if cols["phone"]["notnull"]:
            # SQLite can't drop a NOT NULL constraint, so rebuild the table
            # (https://sqlite.org/lang_altertable.html#otheralter). Ids are
            # copied as-is, so every foreign key keeps pointing at the same row.
            conn.execute("PRAGMA foreign_keys = OFF")
            conn.execute("BEGIN")
            conn.execute(
                """
                CREATE TABLE users_new (
                    id INTEGER PRIMARY KEY,
                    phone TEXT UNIQUE,
                    name TEXT NOT NULL,
                    created_at TEXT DEFAULT (datetime('now'))
                )
                """
            )
            conn.execute(
                "INSERT INTO users_new (id, phone, name, created_at) "
                "SELECT id, phone, name, created_at FROM users"
            )
            conn.execute("DROP TABLE users")
            conn.execute("ALTER TABLE users_new RENAME TO users")
            if conn.execute("PRAGMA foreign_key_check").fetchall():
                conn.execute("ROLLBACK")
                raise RuntimeError("users rebuild broke a foreign key; rolled back")
            conn.execute("COMMIT")
            conn.execute("PRAGMA foreign_keys = ON")
            cols = {row["name"]: row for row in conn.execute("PRAGMA table_info(users)")}

        for col in ("email", "google_sub", "photo_url"):
            if col not in cols:
                conn.execute(f"ALTER TABLE users ADD COLUMN {col} TEXT")
        conn.execute("CREATE UNIQUE INDEX IF NOT EXISTS users_google_sub ON users(google_sub)")
        conn.execute("CREATE INDEX IF NOT EXISTS users_email ON users(email)")
        conn.commit()
    finally:
        conn.close()


def _user_json(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "name": row["name"],
        "phone": row["phone"],
        "email": row["email"],
        "photo_url": row["photo_url"],
    }


def _user_for_token(conn: sqlite3.Connection, token: str) -> Optional[sqlite3.Row]:
    return conn.execute(
        "SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token = ?",
        (token,),
    ).fetchone()


def _issue_session(conn: sqlite3.Connection, user_id: int) -> str:
    token = secrets.token_urlsafe(32)
    conn.execute("INSERT INTO sessions (token, user_id) VALUES (?, ?)", (token, user_id))
    return token


# --- Helpers ------------------------------------------------------------------


def _bearer(authorization: Optional[str]) -> Optional[str]:
    if authorization and authorization.lower().startswith("bearer "):
        return authorization[7:].strip() or None
    return None


def _current_user(conn: sqlite3.Connection, authorization: Optional[str]) -> sqlite3.Row:
    token = _bearer(authorization)
    user = _user_for_token(conn, token) if token else None
    if user is None:
        raise HTTPException(401, "Invalid or expired session")
    return user


def _verify_google(raw_token: str) -> dict:
    client_id = _web_client_id()
    if not client_id:
        raise HTTPException(503, "Google sign-in isn't set up on the server yet")
    try:
        claims = google_id_token.verify_oauth2_token(raw_token, _google_request, client_id)
    except ValueError:
        raise HTTPException(401, "Google sign-in could not be verified. Try again.")
    if not claims.get("email") or not claims.get("email_verified"):
        raise HTTPException(401, "Your Google account has no verified email.")
    return claims


# --- Endpoints ----------------------------------------------------------------


class GoogleBody(BaseModel):
    id_token: str


class MeUpdate(BaseModel):
    name: str = Field(min_length=1, max_length=60)


@router.post("/auth/google")
def auth_google(body: GoogleBody, authorization: Optional[str] = Header(None)):
    """Signs in with a Google ID token, creating the account on first use.

    If the request also carries a valid session (an old phone account), Google
    is linked to *that* account instead, so its trips are kept.
    """
    claims = _verify_google(body.id_token)
    sub, email = claims["sub"], claims["email"].lower()
    name = (claims.get("name") or claims.get("given_name") or email.split("@")[0])[:60]
    photo = claims.get("picture")

    with _db() as conn:
        owner = conn.execute(
            "SELECT * FROM users WHERE google_sub = ? OR (google_sub IS NULL AND lower(email) = ?)",
            (sub, email),
        ).fetchone()

        token = _bearer(authorization)
        current = _user_for_token(conn, token) if token else None
        if current is not None:
            if owner is not None and owner["id"] != current["id"]:
                raise HTTPException(409, "That Google account is already used by another TripSplit account.")
            if current["google_sub"] not in (None, sub):
                raise HTTPException(409, "This account is already connected to a different Google account.")
            user_id = current["id"]
        elif owner is not None:
            user_id = owner["id"]
        else:
            user_id = conn.execute(
                "INSERT INTO users (name, phone, email, google_sub, photo_url) VALUES (?, NULL, ?, ?, ?)",
                (name, email, sub, photo),
            ).lastrowid

        conn.execute(
            "UPDATE users SET google_sub = ?, email = ?, photo_url = ? WHERE id = ?",
            (sub, email, photo, user_id),
        )
        new_token = token if current is not None else _issue_session(conn, user_id)
        user = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        return {"token": new_token, "user": _user_json(user)}


@router.get("/me")
def get_me(authorization: Optional[str] = Header(None)):
    with _db() as conn:
        return _user_json(_current_user(conn, authorization))


@router.patch("/me")
def update_me(body: MeUpdate, authorization: Optional[str] = Header(None)):
    with _db() as conn:
        user = _current_user(conn, authorization)
        conn.execute("UPDATE users SET name = ? WHERE id = ?", (body.name.strip(), user["id"]))
        return _user_json(conn.execute("SELECT * FROM users WHERE id = ?", (user["id"],)).fetchone())
