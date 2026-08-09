import argparse
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


class SpaRequestHandler(SimpleHTTPRequestHandler):
    def send_head(self):
        requested_path = urlsplit(self.path).path
        translated_path = self.translate_path(requested_path)
        if requested_path != "/" and not os.path.exists(translated_path):
            self.path = "/index.html"
        return super().send_head()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=5000)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.bind, args.port), SpaRequestHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
