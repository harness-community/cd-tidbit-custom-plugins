import http.server
import os

PORT = int(os.environ.get("PORT", "8080"))
CONTENT_PATH = "/app/content/index.html"
DEFAULT_PAGE = "<html><body><h1>Custom Plugins Demo</h1><p>No content configured.</p></body></html>"


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(self._get_content().encode())

    def _get_content(self):
        if os.path.isfile(CONTENT_PATH):
            with open(CONTENT_PATH) as f:
                return f.read()
        return os.environ.get("PAGE_CONTENT", DEFAULT_PAGE)

    def log_message(self, format, *args):  # noqa: ARG002
        pass


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("", PORT), Handler)
    print(f"Serving on port {PORT}")
    server.serve_forever()
