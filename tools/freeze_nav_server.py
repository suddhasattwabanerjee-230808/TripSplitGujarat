#!/usr/bin/env python3
"""Make nav-server's TripSplit API read-only after the move to Firebase.

Old app versions (1.6.x and earlier) keep talking to nav-server. Once the data
has been copied to Firebase, anything they save there would be lost, so this
patch makes every change (POST/PUT/PATCH/DELETE) fail with a message telling
them to update. Reading still works, and so do /releases/* (how old phones
find the update) and /auth/* (so they can still sign in to see the message).

    python3 freeze_nav_server.py ~/tripsplit_backend/tripsplit_server.py
    (then restart the service)
"""

import sys

MARKER = "# --- Frozen: TripSplit moved to Firebase ---"

PATCH = f'''
{MARKER}
from fastapi import Request as _FrozenRequest
from fastapi.responses import JSONResponse as _FrozenResponse


@app.middleware("http")
async def _frozen_after_firebase_move(request: _FrozenRequest, call_next):
    if request.method in ("POST", "PUT", "PATCH", "DELETE") and not request.url.path.startswith(
        ("/releases", "/auth")
    ):
        return _FrozenResponse(
            status_code=410,
            content={{"detail": "TripSplit has moved. Update the app (Profile → Check for updates) to keep syncing."}},
        )
    return await call_next(request)
'''

ANCHOR = "app.include_router(google_auth_router)\n"


def main():
    path = sys.argv[1]
    source = open(path).read()
    if MARKER in source:
        print("Already frozen.")
        return
    if source.count(ANCHOR) != 1:
        sys.exit(f"Couldn't find the place to patch ({ANCHOR.strip()!r}); not changed.")
    open(path, "w").write(source.replace(ANCHOR, ANCHOR + PATCH))
    print("Patched. Restart the TripSplit service.")


if __name__ == "__main__":
    main()
