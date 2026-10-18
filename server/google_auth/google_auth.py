"""Google sign-in + profile endpoints for tripsplit_backend.

Drop this file next to the backend's main app module and register it:

    from google_auth import router as google_auth_router
    app.include_router(google_auth_router)

Needs:  pip install google-auth requests
Env:    GOOGLE_WEB_CLIENT_ID=<the Web application OAuth client ID>

Everything marked ADAPT touches the existing database / session code, which
isn't in the app repo. The reference versions assume SQLite tables
`users(id, name, phone, ...)` and `sessions(token, user_id, ...)`; rename to
match the real schema (or swap in the backend's own helpers).
"""

import os
import secrets
import sqlite3
from typing import Optional

from fastapi import APIRouter, Header, HTTPException
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from pydantic import BaseModel, Field

GOOGLE_WEB_CLIENT_ID = os.environ.get("GOOGLE_WEB_CLIENT_ID", "")

router = APIRouter()
_google_request = google_requests.Request()


# --- ADAPT: database access ---------------------------------------------------

DB_PATH = os.environ.get("TRIPSPLIT_DB", "tripsplit.db")  # ADAPT: the backend's DB file


def _db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def migrate() -> None:
    """Adds the Google columns once; safe to call on every start-up."""
    with _db() as conn:
        cols = {row["name"] for row in conn.execute("PRAGMA table_info(users)")}
        for col, ddl in [
            ("email", "ALTER TABLE users ADD COLUMN email TEXT"),
            ("google_sub", "ALTER TABLE users ADD COLUMN google_sub TEXT"),
            ("photo_url", "ALTER TABLE users ADD COLUMN photo_url TEXT"),
        ]:
            if col not in cols:
                conn.execute(ddl)
        conn.execute("CREATE UNIQUE INDEX IF NOT EXISTS users_google_sub ON users(google_sub)")
        conn.execute("CREATE INDEX IF NOT EXISTS users_email ON users(email)")


def _user_json(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "name": row["name"],
        "phone": row["phone"],
        "email": row["email"],
        "photo_url": row["photo_url"],
    }


def _user_for_token(conn: sqlite3.Connection, token: str) -> Optional[sqlite3.Row]:
    # ADAPT: reuse the backend's existing session lookup. Sessions must NOT
    # expire: drop any expires_at / created_at age check there too, so phone
    # accounts stay signed in as well ("permanent login").
    return conn.execute(
        "SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token = ?",
        (token,),
    ).fetchone()


def _issue_session(conn: sqlite3.Connection, user_id: int) -> str:
    # ADAPT: reuse the backend's session creation; just give it no expiry.
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
    if not GOOGLE_WEB_CLIENT_ID:
        raise HTTPException(500, "GOOGLE_WEB_CLIENT_ID is not set on the server")
    try:
        claims = google_id_token.verify_oauth2_token(raw_token, _google_request, GOOGLE_WEB_CLIENT_ID)
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
            # ADAPT: if users.phone is NOT NULL in the real schema, rebuild the
            # table with phone nullable (SQLite can't ALTER a constraint away).
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
