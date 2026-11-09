#!/usr/bin/env python3
"""M0 read-only probe for the N.I.N.A. Advanced API (2.2.15.x) and PHD2.

Standard library only. Every network action in this file is read-only:

* REST: GET requests restricted to an explicit path allowlist
  (docs/api-capability-matrix.md, section 3). Anything else raises.
* WebSocket: connects to /v2/socket and never sends application messages
  (only the opening handshake, pong replies and a close frame).
* PHD2: connects to the event port and never writes a single byte.

Subcommands:
  rest      capture allowlisted REST responses
  ws        listen passively to Advanced API WebSocket events
  phd2      listen passively to PHD2 event notifications
  sanitize  copy captures with site/network/path values redacted
"""

import argparse
import base64
import datetime as dt
import hashlib
import ipaddress
import json
import os
import re
import socket
import struct
import sys
import time
import urllib.parse
import urllib.request

API_PREFIX = "/v2/api"
WS_PATH = "/v2/socket"

# Path templates (relative to API_PREFIX) that are allowed to be requested.
# Keep in sync with docs/api-capability-matrix.md section 3.
ALLOWED_PATHS = [
    r"/version",
    r"/version/nina",
    r"/time",
    r"/application-start",
    r"/equipment/info",
    r"/equipment/(camera|mount|filterwheel|focuser|guider|rotator|safetymonitor|weather|dome|switch|flatdevice)/info",
    r"/equipment/guider/graph",
    r"/equipment/focuser/last-af",
    r"/sequence/json",
    r"/sequence/state",
    r"/image-history",
    r"/event-history",
    r"/application/plugins",
    r"/framing/info",
    r"/profile/horizon",
    r"/image/thumbnail/\d+",
    r"/image/\d+",
    r"/prepared-image",
    r"/astro-util/moon-separation",
]
_ALLOWED_RE = [re.compile(p) for p in ALLOWED_PATHS]

# Query parameters allowed per request. Prevents e.g. raw_fits or
# profile listings sneaking in.
ALLOWED_QUERY = {
    "friendly", "count", "index", "imageType", "resize", "size",
    "quality", "stream", "autoPrepare", "ra", "dec",
}

# Talk to the LAN host directly; never route through a system proxy.
_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))

MAX_JSON_BYTES = 20 * 1024 * 1024
MAX_IMAGE_BYTES = 50 * 1024 * 1024
MAX_LINE_BYTES = 1024 * 1024


class NotAllowed(Exception):
    pass


def check_allowed(path_and_query):
    """Raise NotAllowed unless the request is on the read-only allowlist."""
    parsed = urllib.parse.urlsplit(path_and_query)
    if parsed.scheme or parsed.netloc:
        raise NotAllowed(f"absolute URL not allowed: {path_and_query}")
    if not any(r.fullmatch(parsed.path) for r in _ALLOWED_RE):
        raise NotAllowed(f"path not on allowlist: {parsed.path}")
    keys = {k for k, _ in urllib.parse.parse_qsl(parsed.query, keep_blank_values=True)}
    bad = keys - ALLOWED_QUERY
    if bad:
        raise NotAllowed(f"query parameter(s) not allowed: {sorted(bad)}")


def http_get(host, port, path_and_query, timeout, max_bytes):
    check_allowed(path_and_query)
    url = f"http://{host}:{port}{API_PREFIX}{path_and_query}"
    req = urllib.request.Request(url, method="GET", headers={"Accept": "*/*"})
    started = time.monotonic()
    try:
        with _OPENER.open(req, timeout=timeout) as resp:
            body = resp.read(max_bytes + 1)
            status, ctype = resp.status, resp.headers.get("Content-Type", "")
    except urllib.error.HTTPError as e:
        body = e.read(max_bytes + 1)
        status, ctype = e.code, e.headers.get("Content-Type", "")
    elapsed = time.monotonic() - started
    truncated = len(body) > max_bytes
    return status, ctype, body[:max_bytes], elapsed, truncated


def _slug(path_and_query):
    return re.sub(r"[^A-Za-z0-9]+", "_", path_and_query).strip("_") or "root"


TIER_A = [
    "/version",
    "/version/nina?friendly=true",
    "/time",
    "/application-start",
    "/equipment/info",
    "/equipment/camera/info",
    "/equipment/mount/info",
    "/equipment/filterwheel/info",
    "/equipment/focuser/info",
    "/equipment/guider/info",
    "/equipment/guider/graph",
    "/equipment/rotator/info",
    "/equipment/safetymonitor/info",
    "/equipment/weather/info",
    "/equipment/dome/info",
    "/equipment/switch/info",
    "/equipment/flatdevice/info",
    "/sequence/json",
    "/sequence/state",
    "/image-history?count=true",
    "/event-history",
    "/application/plugins",
    "/framing/info",
    "/profile/horizon",
]

# /profile/show is deliberately absent: it returns third-party API keys
# (astrometry, weather services) in plain text.
TIER_B = [
    "/equipment/focuser/last-af",
]


def cmd_rest(args):
    out = _outdir(args.out, "rest", args.label)
    log = []
    plan = list(TIER_A) + ([] if args.skip_tier_b else TIER_B)

    def save(pq, status, ctype, body, elapsed, truncated, ext=None):
        ext = ext or ("json" if "json" in ctype or body[:1] in (b"{", b"[") else "bin")
        name = f"{_slug(pq)}.{ext}"
        with open(os.path.join(out, name), "wb") as f:
            f.write(body)
        log.append({"request": pq, "status": status, "contentType": ctype,
                    "bytes": len(body), "seconds": round(elapsed, 3),
                    "truncated": truncated, "file": name})
        print(f"{status} {elapsed:6.2f}s {len(body):>9} B  {pq}")

    for pq in plan:
        try:
            save(pq, *http_get(args.host, args.port, pq, args.timeout, MAX_JSON_BYTES))
        except NotAllowed:
            raise
        except Exception as e:  # network errors are data for M0
            log.append({"request": pq, "error": repr(e)})
            print(f"ERR {pq}: {e!r}")
        time.sleep(args.delay)

    if args.images:
        index = _latest_image_index(args)
        if index is None:
            print("No images in history; skipping image requests.")
        else:
            w, h = args.image_size.split("x")
            image_requests = [
                f"/image-history?index={index}",
                f"/image/thumbnail/{index}",
                f"/image/{index}?resize=true&size={int(w)}x{int(h)}&quality={args.quality}&stream=true&autoPrepare=true",
            ]
            for pq in image_requests:
                try:
                    status, ctype, body, el, tr = http_get(args.host, args.port, pq, max(args.timeout, 60), MAX_IMAGE_BYTES)
                    ext = "jpg" if "jpeg" in ctype else "png" if "png" in ctype else None
                    save(pq, status, ctype, body, el, tr, ext)
                except NotAllowed:
                    raise
                except Exception as e:
                    log.append({"request": pq, "error": repr(e)})
                    print(f"ERR {pq}: {e!r}")
                time.sleep(args.delay)

    _write_json(os.path.join(out, "_requests.json"), {"host": "<redacted>", "port": args.port,
                                                     "capturedAt": _now(), "requests": log})
    print(f"Saved to {out}")


def _latest_image_index(args):
    try:
        status, _, body, _, _ = http_get(args.host, args.port, "/image-history?count=true", args.timeout, MAX_JSON_BYTES)
        count = json.loads(body).get("Response")
        if status == 200 and isinstance(count, int) and count > 0:
            return count - 1
    except Exception as e:
        print(f"ERR image count: {e!r}")
    return None


# --- WebSocket (RFC 6455), receive-only client --------------------------------

def _recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("connection closed")
        buf += chunk
    return buf


def _send_control(sock, opcode, payload=b""):
    # Client frames must be masked (RFC 6455 section 5.3).
    mask = os.urandom(4)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    sock.sendall(bytes([0x80 | opcode, 0x80 | len(payload)]) + mask + masked)


def ws_connect(host, port, timeout):
    sock = socket.create_connection((host, port), timeout=timeout)
    key = base64.b64encode(os.urandom(16)).decode()
    sock.sendall((f"GET {WS_PATH} HTTP/1.1\r\nHost: {host}:{port}\r\nUpgrade: websocket\r\n"
                  f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
    head = b""
    while b"\r\n\r\n" not in head:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("handshake: connection closed")
        head += chunk
        if len(head) > 16384:
            raise ConnectionError("handshake: header too large")
    header, rest = head.split(b"\r\n\r\n", 1)
    lines = header.decode("latin-1").split("\r\n")
    if " 101 " not in lines[0] + " ":
        raise ConnectionError(f"handshake failed: {lines[0]}")
    expected = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
    accept = next((l.split(":", 1)[1].strip() for l in lines[1:] if l.lower().startswith("sec-websocket-accept:")), None)
    if accept != expected:
        raise ConnectionError("handshake: bad Sec-WebSocket-Accept")
    return sock, rest


class _Buffered:
    def __init__(self, sock, initial):
        self.sock, self.buf = sock, initial

    def read(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("connection closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out


def ws_messages(sock, initial, deadline):
    """Yield text messages until deadline. Replies to ping with pong only."""
    r = _Buffered(sock, initial)
    fragments = b""
    while time.monotonic() < deadline:
        sock.settimeout(max(0.1, min(1.0, deadline - time.monotonic())))
        try:
            b0, b1 = r.read(2)
        except socket.timeout:
            continue
        sock.settimeout(10)
        opcode, length = b0 & 0x0F, b1 & 0x7F
        if length == 126:
            length = struct.unpack(">H", r.read(2))[0]
        elif length == 127:
            length = struct.unpack(">Q", r.read(8))[0]
        if length > MAX_LINE_BYTES * 16:
            raise ConnectionError(f"frame too large: {length}")
        mask = r.read(4) if b1 & 0x80 else None
        payload = r.read(length)
        if mask:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        if opcode in (0x1, 0x0):
            fragments += payload
            if b0 & 0x80:
                yield fragments.decode("utf-8", "replace")
                fragments = b""
        elif opcode == 0x9:
            _send_control(sock, 0xA, payload[:125])
        elif opcode == 0x8:
            return


def cmd_ws(args):
    out = _outdir(args.out, "ws", args.label)
    path = os.path.join(out, "events.jsonl")
    sock, rest = ws_connect(args.host, args.port, args.timeout)
    n = 0
    try:
        with open(path, "w", encoding="utf-8") as f:
            for text in ws_messages(sock, rest, time.monotonic() + args.seconds):
                n += 1
                f.write(json.dumps({"receivedAt": _now(), "raw": text}) + "\n")
                f.flush()
                print(text[:160])
    finally:
        try:
            _send_control(sock, 0x8, struct.pack(">H", 1000))
        except OSError:
            pass
        sock.close()
    print(f"{n} message(s) saved to {path}")


# --- PHD2, receive-only -------------------------------------------------------

def phd2_lines(sock, deadline):
    """Yield complete CRLF/LF-terminated lines; never writes to the socket."""
    buf = b""
    while time.monotonic() < deadline:
        sock.settimeout(max(0.1, min(1.0, deadline - time.monotonic())))
        try:
            chunk = sock.recv(65536)
        except socket.timeout:
            continue
        if not chunk:
            break
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            yield line.rstrip(b"\r").decode("utf-8", "replace")
        if len(buf) > MAX_LINE_BYTES:
            raise ConnectionError("line exceeds limit")


def cmd_phd2(args):
    out = _outdir(args.out, "phd2", args.label)
    path = os.path.join(out, "events.jsonl")
    # No write path exists here. Do not half-close (SHUT_WR): PHD2 may treat
    # it as a disconnect.
    sock = socket.create_connection((args.host, args.port), timeout=args.timeout)
    n = 0
    try:
        with open(path, "w", encoding="utf-8") as f:
            for line in phd2_lines(sock, time.monotonic() + args.seconds):
                if not line.strip():
                    continue
                n += 1
                f.write(line + "\n")
                f.flush()
                print(line[:160])
    finally:
        sock.close()
    print(f"{n} event(s) saved to {path}")


# --- Sanitizer ----------------------------------------------------------------

SENSITIVE_KEY = re.compile(
    r"(latitude|longitude|elevation|path|folder|filename|^file$|host|ipaddress|^ip$|serial|"
    r"deviceid|computer|user|email|horizonfile|key|token|password|secret|credential|url)", re.I)
WIN_PATH = re.compile(r"([A-Za-z]:\\|\\\\)")
IPV4 = re.compile(r"\b(\d{1,3}(?:\.\d{1,3}){3})\b")


def _redact_ips(text):
    def repl(m):
        try:
            ip = ipaddress.ip_address(m.group(1))
        except ValueError:
            return m.group(1)
        # Only LAN-style addresses: version strings such as "2.2.15.3" also look like IPv4.
        lan = ip.is_private or ip.is_link_local or ip in ipaddress.ip_network("100.64.0.0/10")
        return "<ip>" if lan and not ip.is_loopback else m.group(1)
    return IPV4.sub(repl, text)


def _placeholder(value):
    # Keep JSON types stable so fixtures still exercise the decoders.
    if isinstance(value, bool) or value is None:
        return value
    if isinstance(value, (int, float)):
        return type(value)(0)
    if isinstance(value, (dict, list)):
        return type(value)()
    return "<redacted>"


def sanitize_value(value, extra_terms=()):
    if isinstance(value, dict):
        return {k: (_placeholder(v) if SENSITIVE_KEY.search(k) else sanitize_value(v, extra_terms))
                for k, v in value.items()}
    if isinstance(value, list):
        return [sanitize_value(v, extra_terms) for v in value]
    if isinstance(value, str):
        if WIN_PATH.search(value):
            return "<path>"
        value = _redact_ips(value)
        for term in extra_terms:
            if term:
                value = re.sub(re.escape(term), "<redacted>", value, flags=re.I)
        return value
    return value


def cmd_sanitize(args):
    terms = tuple(t for t in (args.redact or []) if t)
    os.makedirs(args.dst, exist_ok=True)
    for root, _, files in os.walk(args.src):
        rel = os.path.relpath(root, args.src)
        dst_dir = os.path.join(args.dst, rel)
        os.makedirs(dst_dir, exist_ok=True)
        for name in files:
            src, dst = os.path.join(root, name), os.path.join(dst_dir, name)
            if name.endswith(".json"):
                with open(src, encoding="utf-8") as f:
                    data = json.load(f)
                _write_json(dst, sanitize_value(data, terms))
            elif name.endswith(".jsonl"):
                with open(src, encoding="utf-8") as f, open(dst, "w", encoding="utf-8") as g:
                    for line in f:
                        if line.strip():
                            g.write(json.dumps(_sanitize_jsonl(json.loads(line), terms)) + "\n")
            else:
                print(f"skipped (not JSON, review manually): {src}")
    print(f"Sanitized copy in {args.dst} – review every file before committing.")


def _sanitize_jsonl(obj, terms):
    # WebSocket captures wrap the server text in {"raw": "..."}.
    if isinstance(obj, dict) and isinstance(obj.get("raw"), str):
        try:
            return {**obj, "raw": None, "message": sanitize_value(json.loads(obj["raw"]), terms)}
        except json.JSONDecodeError:
            return sanitize_value(obj, terms)
    return sanitize_value(obj, terms)


# --- helpers ------------------------------------------------------------------

def _now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds")


def _outdir(base, kind, label):
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    path = os.path.join(base, f"{stamp}-{kind}" + (f"-{label}" if label else ""))
    os.makedirs(path, exist_ok=True)
    return path


def _write_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    def common(sp, port):
        sp.add_argument("--host", required=True)
        sp.add_argument("--port", type=int, default=port)
        sp.add_argument("--out", default="captures")
        sp.add_argument("--label", default="")
        sp.add_argument("--timeout", type=float, default=10.0)

    r = sub.add_parser("rest")
    common(r, 1888)
    r.add_argument("--delay", type=float, default=0.5, help="seconds between requests")
    r.add_argument("--images", action="store_true", help="also fetch latest thumbnail and one resized preview")
    r.add_argument("--image-size", default="1920x1080")
    r.add_argument("--quality", type=int, default=85)
    r.add_argument("--skip-tier-b", action="store_true", help="skip /equipment/focuser/last-af")
    r.set_defaults(func=cmd_rest)

    w = sub.add_parser("ws")
    common(w, 1888)
    w.add_argument("--seconds", type=float, default=600)
    w.set_defaults(func=cmd_ws)

    h = sub.add_parser("phd2")
    common(h, 4400)
    h.add_argument("--seconds", type=float, default=600)
    h.set_defaults(func=cmd_phd2)

    s = sub.add_parser("sanitize")
    s.add_argument("src")
    s.add_argument("dst")
    s.add_argument("--redact", action="append", help="extra literal to redact (e.g. hostname); repeatable")
    s.set_defaults(func=cmd_sanitize)

    args = p.parse_args(argv)
    try:
        args.func(args)
    except KeyboardInterrupt:
        print("interrupted")
    return 0


if __name__ == "__main__":
    sys.exit(main())
