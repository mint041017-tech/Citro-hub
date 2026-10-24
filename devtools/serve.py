# -*- coding: utf-8 -*-
"""本地静态服务器：支持 gzip（贴近生产 nginx 行为）+ 正确 MIME"""
import os
import sys
import gzip
import mimetypes
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8019

mimetypes.add_type('font/woff2', '.woff2')
mimetypes.add_type('image/jpeg', '.jpeg')
mimetypes.add_type('image/jpeg', '.jpg')

GZIP_TYPES = ('text/', 'application/javascript', 'application/json', 'image/svg+xml')


class H(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *a):
        pass

    def do_HEAD(self):
        self._serve(False)

    def do_GET(self):
        self._serve(True)

    def _serve(self, body):
        path = self.path.split('?')[0].split('#')[0]
        # 站点里有大量中文目录/文件名，必须 URL 解码后再拼路径
        path = urllib.parse.unquote(path)
        if path == '/':
            path = '/index.html'
        fp = os.path.join(ROOT, path.lstrip('/').replace('/', os.sep))
        if not os.path.isfile(fp):
            msg = ('404 not found: ' + path).encode()
            self.send_response(404)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.send_header('Content-Length', str(len(msg)))
            self.end_headers()
            if body:
                self.wfile.write(msg)
            return
        ct = mimetypes.guess_type(fp)[0] or 'application/octet-stream'
        if ct.startswith('text/') and 'charset' not in ct:
            ct += '; charset=utf-8'
        data = open(fp, 'rb').read()
        headers = {'Content-Type': ct, 'Cache-Control': 'no-cache'}
        ae = self.headers.get('Accept-Encoding', '')
        if any(t in ct for t in GZIP_TYPES) and 'gzip' in ae and len(data) > 512:
            data = gzip.compress(data, 6)
            headers['Content-Encoding'] = 'gzip'
        headers['Content-Length'] = str(len(data))
        self.send_response(200)
        for k, v in headers.items():
            self.send_header(k, v)
        self.end_headers()
        if body:
            self.wfile.write(data)


if __name__ == '__main__':
    print('serving %s on http://127.0.0.1:%d (gzip on)' % (ROOT, PORT))
    ThreadingHTTPServer(('127.0.0.1', PORT), H).serve_forever()
