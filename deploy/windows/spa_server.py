import argparse
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


class SpaRequestHandler(SimpleHTTPRequestHandler):
    base_path = ""

    def end_headers(self) -> None:
        # The local Flutter build reuses asset names such as main.dart.js.
        # Caching one generation while index.html points at another causes a
        # blank Flutter page after a refresh.  This local/SP A server must
        # always serve one coherent generation while developing or testing.
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def send_head(self):
        requested_path = urlsplit(self.path).path
        if self.base_path and requested_path.startswith(self.base_path):
            requested_path = requested_path[len(self.base_path) :] or "/"
            self.path = requested_path
        translated_path = self.translate_path(requested_path)
        if requested_path != "/" and not os.path.exists(translated_path):
            self.path = "/index.html"
        return super().send_head()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=5000)
    parser.add_argument("--base-path", default="")
    args = parser.parse_args()
    SpaRequestHandler.base_path = args.base_path.rstrip("/")
    server = ThreadingHTTPServer((args.bind, args.port), SpaRequestHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
