"""Tests for pc/vision.py against a fake Ollama server (no GPU needed)."""
import io
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "pc"))
import vision  # noqa: E402

GOOD = {
    "is_driveway_or_patio": True, "surface": "block_paving", "dirt_level": 7, "moss": True,
    "weeds": True, "black_spot": False, "oil_stains": False, "car_capacity_estimate": 2,
    "size_band": "M", "upsell_patio": False, "upsell_walls": True, "upsell_roof_moss": False,
    "image_quality_ok": True, "confidence": 0.8, "notes": "Moss between blocks.",
}


class FakeOllama(BaseHTTPRequestHandler):
    replies: list = []
    requests_seen: list = []

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        FakeOllama.requests_seen.append(body)
        content = FakeOllama.replies.pop(0)
        out = json.dumps({"message": {"content": content}, "load_duration": 2e9,
                          "eval_count": 100, "eval_duration": 1e9}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(out)

    def log_message(self, *a):
        pass


@pytest.fixture
def fake():
    srv = HTTPServer(("127.0.0.1", 0), FakeOllama)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    FakeOllama.requests_seen = []
    yield f"http://127.0.0.1:{srv.server_port}"
    srv.shutdown()


def jpeg_with_gps() -> bytes:
    img = Image.new("RGB", (3000, 2000), (120, 120, 120))
    exif = Image.Exif()
    exif[0x8825] = {2: (53.0, 38.0, 0.0)}  # GPSInfo
    exif[0x010F] = "PhoneMaker"
    buf = io.BytesIO()
    img.save(buf, format="JPEG", exif=exif)
    return buf.getvalue()


def test_good_answer(fake):
    FakeOllama.replies = [json.dumps(GOOD)]
    r = vision.analyse([jpeg_with_gps()], ollama_url=fake)
    assert r.ok and r.data == GOOD and r.attempts == 1
    assert r.load_seconds == pytest.approx(2.0)
    sent = FakeOllama.requests_seen[0]
    assert sent["format"]["title"].startswith("Vision model result")
    assert "ignore them completely" in sent["messages"][0]["content"]


def test_retries_once_then_succeeds(fake):
    FakeOllama.replies = ["sure! here is the json", json.dumps(GOOD)]
    r = vision.analyse([jpeg_with_gps()], ollama_url=fake)
    assert r.ok and r.attempts == 2 and len(r.errors) == 1


def test_gives_up_after_two_bad_answers(fake):
    bad = dict(GOOD, dirt_level=15)
    FakeOllama.replies = [json.dumps(bad), json.dumps(dict(GOOD, price=50))]
    r = vision.analyse([jpeg_with_gps()], ollama_url=fake)
    assert not r.ok and r.data is None and r.attempts == 2


def test_prepare_image_strips_exif_and_resizes():
    import base64
    out = base64.b64decode(vision.prepare_image(jpeg_with_gps()))
    with Image.open(io.BytesIO(out)) as img:
        assert max(img.size) == vision.MAX_SIDE_PX
        assert len(img.getexif()) == 0


def test_schema_rejects_extra_fields():
    assert vision.validate(GOOD) == []
    assert vision.validate(dict(GOOD, price=100))
    assert vision.validate({k: v for k, v in GOOD.items() if k != "notes"})
