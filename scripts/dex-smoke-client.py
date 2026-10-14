#!/usr/bin/env python3
"""Dex-direct smoke client (feature 013, T008 / quickstart G4).

Runs a laptop-side OIDC authorization-code flow (PKCE, public client — no
secret) against the dex TEST staticClient `dex-substrate-test`
(redirect http://127.0.0.1:5555/callback) and prints the id_token payload.
The C1 evidence needs the `groups` claim showing tempest-concorde team
membership. The openshell gateway is untouched by this flow (inert-dex
phase).

Usage:
  python3 scripts/dex-smoke-client.py            # opens browser, waits for callback
  python3 scripts/dex-smoke-client.py --no-browser

First login shows BOTH consent screens (record occurrence per G4): the
one-time GitHub org-authorization prompt for the `openshell-authz` OAuth
App, then the dex approval page for the TEST client.

Deny-flip runs (SC-002): with orgs flipped to a nonexistent org, the login
is denied at dex — the browser shows the dex error page and this script
either times out or receives an error redirect; both are recorded evidence.
"""
import argparse
import base64
import hashlib
import http.server
import json
import secrets
import socketserver
import sys
import time
import urllib.parse
import urllib.request
import webbrowser


def b64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def jwt_payload(token: str) -> dict:
    payload = token.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload))


class Handler(http.server.BaseHTTPRequestHandler):
    result = {}

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        if u.path != "/callback":
            return self.send_error(404)
        Handler.result["query"] = {k: v[0] for k, v in urllib.parse.parse_qs(u.query).items()}
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(b"<html><body><h3>OK &mdash; return to the terminal.</h3></body></html>")

    def log_message(self, *a):
        pass


class Server(socketserver.TCPServer):
    allow_reuse_address = True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--issuer", default="https://dex.tokyo-brunch.com")
    ap.add_argument("--client-id", default="dex-substrate-test")
    ap.add_argument("--port", type=int, default=5555)
    ap.add_argument("--timeout", type=int, default=240)
    ap.add_argument("--scope", default="openid groups email profile")
    ap.add_argument("--no-browser", action="store_true")
    args = ap.parse_args()

    redirect_uri = f"http://127.0.0.1:{args.port}/callback"
    verifier = b64url(secrets.token_bytes(48))
    challenge = b64url(hashlib.sha256(verifier.encode()).digest())
    state, nonce = secrets.token_urlsafe(24), secrets.token_urlsafe(24)

    auth_url = f"{args.issuer}/auth?" + urllib.parse.urlencode({
        "client_id": args.client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": args.scope,
        "state": state,
        "nonce": nonce,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    })

    print("Open this URL in your browser and complete the GitHub login:")
    print(f"\n  {auth_url}\n")
    if not args.no_browser:
        webbrowser.open(auth_url)
    print(f"Waiting for callback on {redirect_uri} (timeout {args.timeout}s)...")

    with Server(("127.0.0.1", args.port), Handler) as httpd:
        httpd.timeout = 1
        deadline = time.time() + args.timeout
        while "query" not in Handler.result and time.time() < deadline:
            httpd.handle_request()
    if "query" not in Handler.result:
        sys.exit("timeout: no callback arrived (login denied/aborted at dex? record the browser error page)")

    q = Handler.result["query"]
    if "error" in q:
        sys.exit(f"dex returned error at callback: {q}")
    if q.get("state") != state:
        sys.exit(f"state mismatch: {q.get('state')!r}")
    code = q["code"]

    data = urllib.parse.urlencode({
        "grant_type": "authorization_code",
        "client_id": args.client_id,
        "code": code,
        "redirect_uri": redirect_uri,
        "code_verifier": verifier,
    }).encode()
    req = urllib.request.Request(
        f"{args.issuer}/token", data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req) as r:
        tokens = json.load(r)

    print("\ntoken endpoint response keys:", sorted(tokens))
    claims = jwt_payload(tokens["id_token"])
    print("\n=== id_token payload ===")
    print(json.dumps(claims, indent=2))
    groups = claims.get("groups")
    print("\n=== groups claim:", groups)
    if groups and "tempest-concorde:openshell-users" in groups:
        print("C1 evidence: member groups claim present "
              "(tempest-concorde:openshell-users"
              + (" + openshell-admins)" if "tempest-concorde:openshell-admins" in groups else ")"))
    else:
        print("NOTE: groups claim missing or no openshell-users membership "
              "— check requested scope and team membership")


if __name__ == "__main__":
    main()
