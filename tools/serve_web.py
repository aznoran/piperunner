#!/usr/bin/env python3
"""Serves the web build locally.

`python3 -m http.server` is not enough: it hands back .wasm as
application/octet-stream, and the streaming compiler refuses it — the game
loads to a blank canvas with one console line about the MIME type.

    python3 tools/serve_web.py            # http://127.0.0.1:4173
    python3 tools/serve_web.py 5000
"""

import functools
import http.server
import pathlib
import socketserver
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "build" / "web"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4173


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "text/javascript",
        ".pck": "application/octet-stream",
    }

    def end_headers(self):
        # The platform does not serve these, so neither does this: a build that
        # only works cross-origin-isolated would pass here and fail there.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        if "200" not in fmt % args:
            super().log_message(fmt, *args)


if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(
        ("127.0.0.1", PORT),
        functools.partial(Handler, directory=str(ROOT)),
    ) as httpd:
        print(f"serving {ROOT} at http://127.0.0.1:{PORT}")
        httpd.serve_forever()
