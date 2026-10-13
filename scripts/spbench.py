#!/usr/bin/python3 -I
# spbench.py <label> [chrome flags...]: run Speedometer 3.1 in a throw-away Chrome profile through quigon-chrome,
# driven over the DevTools protocol (minimal WebSocket client, stdlib only). Prints the Speedometer score. Run as the desktop user with WAYLAND_DISPLAY/XDG_RUNTIME_DIR set.
import base64, json, os, socket, struct, subprocess, sys, time, urllib.request

PORT = 9334
label, flags = sys.argv[1], sys.argv[2:]
prof = f"/tmp/spbench-{label}"
subprocess.run(["rm", "-rf", prof])
chrome = subprocess.Popen(["/usr/local/bin/quigon-chrome", f"--remote-debugging-port={PORT}", f"--user-data-dir={prof}",
                           "--no-first-run", "--no-default-browser-check", "--disable-background-timer-throttling", "--ozone-platform=wayland",
                           *flags, "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def get(path):
    return json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}{path}", timeout=5))

class WS:
    def __init__(self, url):
        host, path = url.split("//", 1)[1].split("/", 1)
        h, p = host.split(":")
        self.s = socket.create_connection((h, int(p)))
        key = base64.b64encode(os.urandom(16)).decode()
        self.s.sendall(f"GET /{path} HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                       f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n".encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            buf += self.s.recv(4096)
        self.rest = buf.split(b"\r\n\r\n", 1)[1]
        self.id = 0

    def _recv(self, n):
        while len(self.rest) < n:
            self.rest += self.s.recv(1 << 16)
        out, self.rest = self.rest[:n], self.rest[n:]
        return out

    def frame(self):
        b1, b2 = self._recv(2)
        n = b2 & 0x7F
        if n == 126: n = struct.unpack(">H", self._recv(2))[0]
        elif n == 127: n = struct.unpack(">Q", self._recv(8))[0]
        return self._recv(n)

    def call(self, method, **params):
        self.id += 1
        msg = json.dumps({"id": self.id, "method": method, "params": params}).encode()
        hdr = bytes([0x81]) + (bytes([0x80 | len(msg)]) if len(msg) < 126 else bytes([0x80 | 126]) + struct.pack(">H", len(msg)))
        mask = os.urandom(4)
        self.s.sendall(hdr + mask + bytes(c ^ mask[i % 4] for i, c in enumerate(msg)))
        while True:
            r = json.loads(self.frame())
            if r.get("id") == self.id:
                return r.get("result", r)

    def js(self, expr):
        r = self.call("Runtime.evaluate", expression=expr, returnByValue=True)
        return r.get("result", {}).get("value")

for _ in range(60):
    try:
        ver = get("/json/version"); break
    except Exception:
        time.sleep(0.5)
browser = WS(ver["webSocketDebuggerUrl"])
print(f"[{label}] flags: {' '.join(flags) or '(defaults)'}")

page = [t for t in get("/json/list") if t["type"] == "page"][0]
ws = WS(page["webSocketDebuggerUrl"])
ws.call("Page.navigate", url="https://browserbench.org/Speedometer3.1/")
for _ in range(60):
    time.sleep(1)
    if ws.js("!!document.querySelector('.start-tests-button') && document.readyState === 'complete'"):
        break
time.sleep(3)
ws.js("document.querySelector('.start-tests-button').click()")
t0 = time.time(); score = None
while time.time() - t0 < 1200:
    time.sleep(10)
    score = ws.js("(location.hash === '#summary' && (document.querySelector('#result-number')||{}).textContent) || ''")
    if score:
        break
print(f"  Speedometer 3.1 score: {score or 'TIMEOUT'}  ({time.time() - t0:.0f} s)")
try:
    browser.call("Browser.close")
except Exception:
    pass
chrome.wait(timeout=20)
subprocess.run(["rm", "-rf", prof])
