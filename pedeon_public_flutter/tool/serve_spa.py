"""Servidor local mínimo com fallback para rotas do Flutter Web."""

from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import os
from urllib.parse import urlsplit


class SpaHandler(SimpleHTTPRequestHandler):
    url_prefix = ""

    def translate_path(self, path):
        """Serve builds mounted below an optional reverse-proxy path prefix."""
        if self.url_prefix:
            parsed = urlsplit(path)
            request_path = parsed.path
            if request_path == self.url_prefix:
                request_path = "/"
            elif request_path.startswith(self.url_prefix + "/"):
                request_path = request_path[len(self.url_prefix):] or "/"
            path = request_path
        return super().translate_path(path)

    def end_headers(self):
        # O servidor local deve sempre entregar o build atual durante os testes.
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        return super().end_headers()

    def send_error(self, code, message=None, explain=None):
        request_path = self.path.split("?", 1)[0]
        if code == 404 and not Path(request_path).suffix:
            self.path = "/index.html"
            return self.do_GET()
        return super().send_error(code, message, explain)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5001)
    parser.add_argument("--directory", default="build/web")
    parser.add_argument("--url-prefix", default="", help="reverse-proxy URL prefix to strip")
    args = parser.parse_args()
    root = Path(args.directory).resolve()
    os.chdir(root)
    SpaHandler.url_prefix = args.url_prefix.rstrip("/")
    server = ThreadingHTTPServer((args.host, args.port), SpaHandler)
    print(f"PedeOn público em http://{args.host}:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
