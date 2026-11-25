#!/usr/bin/env python3
"""Fake catalog / Nexus staging / Tribe REST server for the integration tests.

GET  /catalog/<file>                          -> the file from <catalog dir>
POST /service/local/staging/profiles/<p>/start -> {"data":{"stagedRepositoryId":"repo-<n>"}}
POST /tasks/comments/<task>                  -> 200
Every POST is appended as one JSON line to <requests file>.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

catalog_dir, requests_file, port_file = sys.argv[1:4]
counter = {"n": 0}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _reply(self, code, body=b"", ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        name = os.path.basename(self.path)
        path = os.path.join(catalog_dir, name)
        if self.path.startswith("/catalog/") and os.path.isfile(path):
            with open(path, "rb") as f:
                self._reply(200, f.read(), "text/plain")
        else:
            self._reply(404, b"not found", "text/plain")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode()
        with open(requests_file, "a") as f:
            f.write(json.dumps({"path": self.path, "auth": self.headers.get("Authorization"),
                                "agent": self.headers.get("User-Agent"), "body": body}) + "\n")
        if "/service/local/staging/profiles/" in self.path and self.path.endswith("/start"):
            counter["n"] += 1
            self._reply(201, json.dumps({"data": {"stagedRepositoryId": "repo-%d" % counter["n"]}}).encode())
        elif self.path.startswith("/tasks/comments/"):
            self._reply(200, b"{}")
        else:
            self._reply(404, b"unknown", "text/plain")


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
