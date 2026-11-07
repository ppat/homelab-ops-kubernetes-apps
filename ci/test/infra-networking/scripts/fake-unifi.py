"""A record store that answers the UniFi Network Integration API calls the
external-dns-unifi-webhook makes, and nothing else.

Runs INSIDE the fake-unifi pod (test-resources/fake-unifi.yaml), not on the chainsaw runner.
The wire shapes follow internal/unifi/{client,dto}.go in home-operations/external-dns-unifi-webhook
at the tag components/external-dns-provider/unifi pins:

  GET    {base}/sites?filter=...                 one site, found by internalReference
  GET    {base}/sites/{site}/dns/policies        every record in one page
  POST   {base}/sites/{site}/dns/policies        store the envelope, echo it back with an id
  DELETE {base}/sites/{site}/dns/policies/{id}   404 when absent, which the webhook treats as done

where base is /proxy/network/integration/v1. A request without the expected X-API-KEY gets a
401, so a key that never reaches the webhook fails the webhook's startup site lookup.

GET /records is the fake's own read endpoint for assertions: one line per record,
`<type> <domain> <value>`, in creation order.
"""

import json
import os
import re
import ssl
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE = "/proxy/network/integration/v1"
SITE_ID = "88f7af54-98f8-306a-a1c7-c9349722b1f6"
API_KEY = os.environ["FAKE_UNIFI_API_KEY"]
VALUE_FIELD = {
    "A_RECORD": "ipv4Address",
    "AAAA_RECORD": "ipv6Address",
    "CNAME_RECORD": "targetDomain",
    "TXT_RECORD": "text",
}

POLICIES = re.compile(rf"^{BASE}/sites/{SITE_ID}/dns/policies(?:/(?P<id>[^/]+))?$")
records = {}
lock = threading.Lock()


def page(data):
    return {"offset": 0, "limit": len(data), "count": len(data), "totalCount": len(data), "data": data}


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
        self.reply(401, {"statusCode": 401, "statusName": "UNAUTHORIZED", "message": "bad X-API-KEY"})
        return False

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/records":
            with lock:
                lines = [f"{r['type']} {r['domain']} {r.get(VALUE_FIELD.get(r['type'], ''), '-')}\n"
                         for r in records.values()]
            return self.reply(200, "".join(lines).encode(), "text/plain")
        if not self.authorized():
            return None
        if path == f"{BASE}/sites":
            return self.reply(200, page([{"id": SITE_ID, "internalReference": "default", "name": "Default"}]))
        match = POLICIES.match(path)
        if match and not match["id"]:
            with lock:
                return self.reply(200, page(list(records.values())))
        return self.reply(404, {"statusCode": 404, "message": f"no route {path}"})

    def do_POST(self):
        if not self.authorized():
            return None
        match = POLICIES.match(self.path)
        if not match or match["id"]:
            return self.reply(404, {"statusCode": 404, "message": f"no route {self.path}"})
        record = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        record["id"] = str(uuid.uuid4())
        with lock:
            records[record["id"]] = record
        return self.reply(200, record)

    def do_DELETE(self):
        if not self.authorized():
            return None
        match = POLICIES.match(self.path)
        with lock:
            found = bool(match and match["id"]) and records.pop(match["id"], None) is not None
        return self.reply(200) if found else self.reply(404, {"statusCode": 404, "message": "not found"})

    def log_message(self, format, *args):  # noqa: A002 - BaseHTTPRequestHandler's signature
        print(f"{self.command} {self.path} -> {args[1] if len(args) > 1 else '-'}", flush=True)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("", 8443), Handler)
    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls.load_cert_chain("/tls/tls.crt", "/tls/tls.key")
    server.socket = tls.wrap_socket(server.socket, server_side=True)
    server.serve_forever()
