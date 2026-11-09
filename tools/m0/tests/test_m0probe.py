"""Self-tests for m0probe against local fake servers. No real hardware."""

import base64
import hashlib
import http.server
import json
import os
import re
import socket
import socketserver
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import m0probe  # noqa: E402


class FakeNINA(http.server.BaseHTTPRequestHandler):
    requests = []

    def log_message(self, *args):
        pass

    def do_GET(self):
        FakeNINA.requests.append(("GET", self.path))
        path = self.path.split("?")[0]
        if path.startswith("/v2/api/image/thumbnail/") or path.startswith("/v2/api/image/"):
            body, ctype = b"\xff\xd8\xff\xd9", "image/jpeg"
        elif path == "/v2/api/image-history" and "count=true" in self.path:
            body, ctype = json.dumps({"Response": 3, "Success": True}).encode(), "application/json"
        else:
            body, ctype = json.dumps({"Response": {"path": path}, "Success": True, "StatusCode": 200}).encode(), "application/json"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        FakeNINA.requests.append(("POST", self.path))
        self.send_response(405)
        self.end_headers()


class _FastHTTPServer(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def server_bind(self):
        # Skip HTTPServer's getfqdn() reverse lookup, which can stall for many seconds.
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


def _start_http():
    srv = _FastHTTPServer(("127.0.0.1", 0), FakeNINA)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


def _listener():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    s.listen(1)
    return s


class AllowlistTests(unittest.TestCase):
    def test_allowed(self):
        for pq in m0probe.TIER_A + m0probe.TIER_B + [
            "/image/thumbnail/4", "/image/4?resize=true&size=1920x1080&quality=85&stream=true&autoPrepare=true",
        ]:
            m0probe.check_allowed(pq)

    def test_control_endpoints_rejected(self):
        for pq in [
            "/equipment/mount/park", "/equipment/mount/slew?ra=1&dec=2", "/equipment/camera/capture",
            "/equipment/camera/capture/statistics", "/sequence/start", "/equipment/dome/open",
            "/equipment/camera/connect", "/equipment/guider/start", "/application/windows/close",
            "/profile/change-value", "/image/3/solve", "/application/screenshot", "/application/logs",
            "/version/../equipment/mount/park", "http://evil/v2/api/version",
        ]:
            with self.assertRaises(m0probe.NotAllowed, msg=pq):
                m0probe.check_allowed(pq)

    def test_dangerous_query_rejected(self):
        with self.assertRaises(m0probe.NotAllowed):
            m0probe.check_allowed("/image/1?raw_fits=true")
        with self.assertRaises(m0probe.NotAllowed):
            m0probe.check_allowed("/profile/show?active=true")

    def test_every_tier_entry_is_in_capability_matrix(self):
        with open(os.path.join(os.path.dirname(__file__), "..", "..", "..", "docs", "api-capability-matrix.md"),
                  encoding="utf-8") as f:
            doc = f.read()
        documented = set()
        for m in re.finditer(r"`GET (/[^`?\s]*)", doc):
            path = m.group(1)
            group = re.search(r"\{([a-z,]+)\}", path)
            if group and "," in group.group(1):
                documented |= {path.replace(group.group(0), d) for d in group.group(1).split(",")}
            else:
                documented.add(path)
        for pq in m0probe.TIER_A + m0probe.TIER_B:
            self.assertIn(pq.split("?")[0], documented, f"{pq} missing from capability matrix")


class RestCaptureTests(unittest.TestCase):
    def test_rest_capture_only_issues_allowlisted_gets(self):
        srv = _start_http()
        FakeNINA.requests = []
        with tempfile.TemporaryDirectory() as out:
            m0probe.main(["rest", "--host", "127.0.0.1", "--port", str(srv.server_address[1]),
                          "--out", out, "--delay", "0", "--images"])
            run = os.path.join(out, os.listdir(out)[0])
            with open(os.path.join(run, "_requests.json")) as f:
                log = json.load(f)
            self.assertEqual(log["host"], "<redacted>")
            self.assertTrue(any(f.endswith(".jpg") for f in os.listdir(run)))
        srv.shutdown()
        srv.server_close()
        self.assertTrue(FakeNINA.requests)
        for method, path in FakeNINA.requests:
            self.assertEqual(method, "GET")
            self.assertTrue(path.startswith("/v2/api/"))
            m0probe.check_allowed(path[len("/v2/api"):])
        self.assertIn(("GET", "/v2/api/image/thumbnail/2"), FakeNINA.requests)


class WebSocketTests(unittest.TestCase):
    def test_passive_listener_sends_no_application_data(self):
        lst = _listener()
        port = lst.getsockname()[1]
        inbound_opcodes = []

        def server():
            conn, _ = lst.accept()
            lst.close()
            req = b""
            while b"\r\n\r\n" not in req:
                req += conn.recv(4096)
            key = [l.split(b":", 1)[1].strip() for l in req.split(b"\r\n") if l.lower().startswith(b"sec-websocket-key")][0]
            accept = base64.b64encode(hashlib.sha1(key + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest())
            conn.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                         b"Sec-WebSocket-Accept: " + accept + b"\r\n\r\n")
            msg = json.dumps({"Response": {"Event": "IMAGE-SAVE"}, "Type": "Socket"}).encode()
            conn.sendall(bytes([0x81, len(msg)]) + msg)
            conn.sendall(bytes([0x89, 0]))  # ping
            big = json.dumps({"Response": {"Event": "FILTERWHEEL-CHANGED", "pad": "x" * 300}}).encode()
            # fragmented text frame, 126-length encoding
            conn.sendall(bytes([0x01, 126]) + len(big[:150]).to_bytes(2, "big") + big[:150])
            conn.sendall(bytes([0x80, 126]) + len(big[150:]).to_bytes(2, "big") + big[150:])
            conn.settimeout(3)
            try:
                while True:
                    hdr = conn.recv(2)
                    if len(hdr) < 2:
                        break
                    n = hdr[1] & 0x7F
                    conn.recv(4 + n)
                    inbound_opcodes.append(hdr[0] & 0x0F)
                    if hdr[0] & 0x0F == 0x8:
                        break
            except socket.timeout:
                pass
            conn.close()

        t = threading.Thread(target=server, daemon=True)
        t.start()
        with tempfile.TemporaryDirectory() as out:
            m0probe.main(["ws", "--host", "127.0.0.1", "--port", str(port), "--out", out, "--seconds", "1.5"])
            run = os.path.join(out, os.listdir(out)[0])
            with open(os.path.join(run, "events.jsonl")) as f:
                lines = f.read().splitlines()
        t.join(5)
        self.assertEqual(len(lines), 2)
        self.assertIn("FILTERWHEEL-CHANGED", json.loads(lines[1])["raw"])
        # Only pong (0xA) and close (0x8) are ever sent by the client.
        self.assertTrue(set(inbound_opcodes) <= {0xA, 0x8}, inbound_opcodes)
        self.assertIn(0xA, inbound_opcodes)


class PHD2Tests(unittest.TestCase):
    def test_reads_split_frames_and_never_writes(self):
        lst = _listener()
        port = lst.getsockname()[1]
        received = []
        events = [
            {"Event": "Version", "PHDVersion": "2.6.13", "MsgVersion": 1, "Host": "OBS-PC", "Inst": 1},
            {"Event": "AppState", "State": "Guiding"},
            {"Event": "GuideStep", "Frame": 1, "RADistanceRaw": 0.12, "DECDistanceRaw": -0.08},
        ]
        wire = b"".join(json.dumps(e).encode() + b"\r\n" for e in events)

        def server():
            conn, _ = lst.accept()
            lst.close()
            for i in range(0, len(wire), 7):  # partial TCP frames
                conn.sendall(wire[i:i + 7])
                time.sleep(0.002)
            conn.settimeout(1.0)
            try:
                data = conn.recv(1024)
                if data:
                    received.append(data)
            except socket.timeout:
                pass
            conn.close()

        t = threading.Thread(target=server, daemon=True)
        t.start()
        with tempfile.TemporaryDirectory() as out:
            m0probe.main(["phd2", "--host", "127.0.0.1", "--port", str(port), "--out", out, "--seconds", "2"])
            run = os.path.join(out, os.listdir(out)[0])
            with open(os.path.join(run, "events.jsonl")) as f:
                lines = f.read().splitlines()
        t.join(5)
        self.assertEqual([json.loads(l)["Event"] for l in lines], ["Version", "AppState", "GuideStep"])
        self.assertEqual(received, [], "client must never write to PHD2")


class SanitizeTests(unittest.TestCase):
    def test_redacts_site_network_and_paths(self):
        data = {"Response": {"SiteLatitude": 12.5, "SiteLongitude": -45.25, "SiteElevation": 40,
                             "AstrometrySettings": {"Latitude": 12.5, "HorizonFilePath": "C:\\x\\h.hrz"},
                             "ImageStatistics": {"Filename": "C:\\Astro\\M31\\L_001.fits", "HFR": 2.1, "TargetName": "M31"},
                             "Note": "server at 192.168.1.50 and 127.0.0.1", "Host": "OBS-PC",
                             "Version": "2.2.15.3", "Other": "10.0.0.7 169.254.1.2 100.64.3.4",
                             "CameraName": "Camera on OBS-PC", "AtPark": False,
                             "AstrometryAPIKey": "abc123", "OpenWeatherMapAPIKey": "def456",
                             "SkyGuardServerUrl": "http://x", "PinPointAllSkyApiKey": ""}}
        s = m0probe.sanitize_value(data, ("OBS-PC",))["Response"]
        self.assertEqual(s["SiteLatitude"], 0.0)
        self.assertEqual(s["SiteElevation"], 0)
        self.assertEqual(s["AstrometrySettings"]["Latitude"], 0.0)
        self.assertEqual(s["AstrometrySettings"]["HorizonFilePath"], "<redacted>")
        self.assertEqual(s["ImageStatistics"]["Filename"], "<redacted>")
        self.assertEqual(s["ImageStatistics"]["HFR"], 2.1)
        self.assertEqual(s["Note"], "server at <ip> and 127.0.0.1")
        self.assertEqual(s["Version"], "2.2.15.3")
        self.assertEqual(s["Other"], "<ip> <ip> <ip>")
        self.assertEqual(s["Host"], "<redacted>")
        self.assertEqual(s["CameraName"], "Camera on <redacted>")
        self.assertIs(s["AtPark"], False)
        for key in ("AstrometryAPIKey", "OpenWeatherMapAPIKey", "SkyGuardServerUrl", "PinPointAllSkyApiKey"):
            self.assertEqual(s[key], "<redacted>", key)


if __name__ == "__main__":
    unittest.main(verbosity=2)
