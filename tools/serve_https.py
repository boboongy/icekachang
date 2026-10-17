"""Serve build/web over HTTPS on the local network so a phone can run the Godot web build.

Godot web builds need a secure context; plain http on a LAN IP is refused.
Uses the self-signed cert in build/cert (phone will warn once: Advanced > Proceed).
Run with Python312 (it has a firewall allow rule):  python tools/serve_https.py
The big files (.wasm, .pck, .js) go out gzipped, about a quarter of the size, which makes the
phone load several times faster. The .gz copies are made once per export in build/gz.
"""
import gzip
import http.server
import shutil
import ssl
from functools import partial
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / "build" / "web"
GZ = ROOT / "build" / "gz"
PORT = 8443
ZIPPED = {".wasm", ".pck", ".js"}


def gz_copy(src: Path) -> Path:
    """A gzipped copy of src, remade when the export is newer."""
    dst = GZ / (src.name + ".gz")
    if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime:
        GZ.mkdir(parents=True, exist_ok=True)
        tmp = dst.with_suffix(".tmp")
        with open(src, "rb") as f, gzip.open(tmp, "wb", compresslevel=9) as g:
            shutil.copyfileobj(f, g)
        tmp.replace(dst)
    return dst


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm", ".pck": "application/octet-stream",
                      ".js": "text/javascript"}

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")   # a new export always reaches the phone
        super().end_headers()

    def send_head(self):
        src = Path(self.translate_path(self.path))
        if (src.suffix in ZIPPED and src.is_file()
                and "gzip" in self.headers.get("Accept-Encoding", "")):
            dst = gz_copy(src)
            f = open(dst, "rb")
            self.send_response(200)
            self.send_header("Content-Type", self.guess_type(str(src)))
            self.send_header("Content-Encoding", "gzip")
            self.send_header("Content-Length", str(dst.stat().st_size))
            self.end_headers()
            return f
        return super().send_head()


if __name__ == "__main__":
    for p in WEB.iterdir():                  # zip up front, so the first phone load isn't slow
        if p.suffix in ZIPPED:
            gz_copy(p)
    httpd = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), partial(Handler, directory=str(WEB)))
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(ROOT / "build" / "cert" / "cert.pem", ROOT / "build" / "cert" / "key.pem")
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    print(f"Serving https://0.0.0.0:{PORT}", flush=True)
    httpd.serve_forever()
