"""A record store that answers the UniFi Network static-dns API calls the
external-dns-unifi-webhook makes, and nothing else.

Runs INSIDE the fake-unifi pod (test-resources/fake-unifi.yaml), not on the chainsaw runner.
The wire shapes follow internal/unifi/{client,dto}.go in home-operations/external-dns-unifi-webhook
at the tag components/external-dns-provider/unifi pins:

  GET    {base}/site/{site}/static-dns        every record, as one unpaginated JSON array
  POST   {base}/site/{site}/static-dns        store the record, echo it back with an `_id`
  DELETE {base}/site/{site}/static-dns/{id}   404 when absent, which the webhook treats as done

where base is /proxy/network/v2/api and site is the site's short name, `default` unless the
component sets UNIFI_SITE. The webhook lists the records once at startup and exits if that
fails, so an unknown site gets a 404 and a request without the expected X-API-KEY gets a 401.

GET /records is the fake's own read endpoint for assertions: one line per record,
`<TYPE>_RECORD <domain> <value>`, in creation order. That format is independent of the API
above, so the assertion scripts do not change when the webhook's API does.
"""

import json
import os
import re
import ssl
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE = "/proxy/network/v2/api"
SITE = "default"
API_KEY = os.environ["FAKE_UNIFI_API_KEY"]

STATIC_DNS = re.compile(rf"^{BASE}/site/(?P<site>[^/]+)/static-dns(?:/(?P<id>[^/]+))?$")
records = {}
lock = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    def reply(self, status, body=None, content_type="application/json"):
        payload = b"" if body is None else (body if isinstance(body, bytes) else json.dumps(body).encode())
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def authorized(self):
        if self.headers.get("X-API-KEY") == API_KEY:
            return True
        self.reply(401, {"error": {"code": 401, "message": "bad X-API-KEY"}})
        return False

    def route(self):
        """The static-dns match for this request, or None after replying 404."""
        match = STATIC_DNS.match(self.path.split("?", 1)[0])
        if match and match["site"] == SITE:
            return match
        self.reply(404, {"error": {"code": 404, "message": f"no route {self.path}"}})
        return None

    def do_GET(self):
        if self.path.split("?", 1)[0] == "/records":
            with lock:
                lines = [f"{r['record_type']}_RECORD {r['key']} {r['value']}\n" for r in records.values()]
            return self.reply(200, "".join(lines).encode(), "text/plain")
        if not self.authorized():
            return None
        match = self.route()
        if match is None:
            return None
        if match["id"]:
            return self.reply(404, {"error": {"code": 404, "message": "no single-record GET"}})
        with lock:
            return self.reply(200, list(records.values()))

    def do_POST(self):
        if not self.authorized():
            return None
        match = self.route()
        if match is None:
            return None
        if match["id"]:
            return self.reply(404, {"error": {"code": 404, "message": f"no route {self.path}"}})
        record = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        record["_id"] = uuid.uuid4().hex
        with lock:
            records[record["_id"]] = record
        return self.reply(200, record)

    def do_DELETE(self):
        if not self.authorized():
            return None
        match = self.route()
        if match is None:
            return None
        with lock:
            found = bool(match["id"]) and records.pop(match["id"], None) is not None
        return self.reply(200) if found else self.reply(404, {"error": {"code": 404, "message": "not found"}})

    def log_message(self, format, *args):  # noqa: A002 - BaseHTTPRequestHandler's signature
        print(f"{self.command} {self.path} -> {args[1] if len(args) > 1 else '-'}", flush=True)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("", 8443), Handler)
    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls.load_cert_chain("/tls/tls.crt", "/tls/tls.key")
    server.socket = tls.wrap_socket(server.socket, server_side=True)
    server.serve_forever()
