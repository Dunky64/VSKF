"""Milestone A test: run the vision model on 5 driveway photos and report speed + GPU use.

Run by setup.bat and diagnose.bat. Writes pc/local/last_gpu_test.json for the report.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vision  # noqa: E402

PHOTOS = vision.REPO_ROOT / "samples" / "photos"
LOCAL = vision.REPO_ROOT / "pc" / "local"
RESULT_FILE = LOCAL / "last_gpu_test.json"
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp"}
WANTED = 5

COMMONS_API = "https://commons.wikimedia.org/w/api.php"
HEADERS = {"User-Agent": "DrivewayButler-GPUTest/0.1 (sample photo download)"}
SEARCHES = ["block paving driveway", "driveway house UK", "moss paving",
            "tarmac driveway", "patio slabs garden", "concrete driveway"]
FREE_LICENCE = re.compile(r"^(CC0|CC BY|CC-BY|Public domain|PD)", re.I)


def local_photos() -> list[Path]:
    if not PHOTOS.exists():
        return []
    return sorted(p for p in PHOTOS.iterdir() if p.suffix.lower() in IMAGE_EXT)


def download_samples(needed: int) -> None:
    """Fetch freely licensed driveway photos from Wikimedia Commons, with credits."""
    PHOTOS.mkdir(parents=True, exist_ok=True)
    credits_path = PHOTOS / "CREDITS.txt"
    credits = credits_path.read_text(encoding="utf-8") if credits_path.exists() else ""
    got, seen = 0, set()
    for query in SEARCHES:
        if got >= needed:
            break
        params = {"action": "query", "format": "json", "generator": "search",
                  "gsrsearch": f"{query} filetype:bitmap", "gsrnamespace": 6, "gsrlimit": 10,
                  "prop": "imageinfo", "iiprop": "url|extmetadata|mime", "iiurlwidth": 1024}
        try:
            pages = requests.get(COMMONS_API, params=params, headers=HEADERS, timeout=30) \
                .json().get("query", {}).get("pages", {})
        except (requests.RequestException, ValueError) as exc:
            print(f"  ! Could not search Wikimedia for '{query}': {exc}")
            continue
        for page in sorted(pages.values(), key=lambda p: p.get("index", 99)):
            if got >= needed:
                break
            title = page.get("title", "")
            info = (page.get("imageinfo") or [{}])[0]
            meta = info.get("extmetadata", {})
            licence = meta.get("LicenseShortName", {}).get("value", "")
            if title in seen or not FREE_LICENCE.match(licence) or "jpeg" not in info.get("mime", ""):
                continue
            seen.add(title)
            try:
                img = requests.get(info["thumburl"], headers=HEADERS, timeout=60)
                img.raise_for_status()
            except (requests.RequestException, KeyError):
                continue
            name = f"sample_{len(local_photos()) + 1:02d}.jpg"
            (PHOTOS / name).write_bytes(img.content)
            artist = re.sub(r"<[^>]+>", "", meta.get("Artist", {}).get("value", "unknown")).strip()
            credits += f"{name}: {title} by {artist}, {licence}, {info.get('descriptionurl', '')}\n"
            got += 1
            print(f"  + downloaded {name} ({licence})")
    credits_path.write_text(credits, encoding="utf-8")


def gpu_share() -> tuple[float | None, int, int]:
    """(fraction of the model on the GPU, bytes on GPU, total model bytes)."""
    try:
        for m in vision.loaded_models():
            if m.get("name", "").startswith(MODEL.split(":")[0]):
                size, vram = m.get("size", 0), m.get("size_vram", 0)
                return (vram / size if size else None), vram, size
    except requests.RequestException:
        pass
    return None, 0, 0


def main() -> int:
    LOCAL.mkdir(parents=True, exist_ok=True)
    photos = local_photos()
    if len(photos) < WANTED:
        print(f"Getting {WANTED - len(photos)} sample driveway photo(s) from Wikimedia Commons...")
        download_samples(WANTED - len(photos))
        photos = local_photos()
    photos = photos[:COUNT]
    if not photos:
        print("ERROR: no photos to test with. Put some driveway photos in samples\\photos and try again.")
        return 2

    print(f"\nTesting {MODEL} on {len(photos)} photo(s). The first one is slower (model loading).\n")
    rows, load_s = [], 0.0
    for i, photo in enumerate(photos, 1):
        res = vision.analyse([photo], model=MODEL)
        load_s += res.load_seconds
        secs = max(0.0, res.seconds - res.load_seconds)  # time per image, excluding one-off model loading
        d = res.data or {}
        print(f"  [{i}/{len(photos)}] {photo.name}: {secs:5.1f} s  "
              + (f"{d.get('surface')}, dirt {d.get('dirt_level')}/10, size {d.get('size_band')}, "
                 f"confidence {d.get('confidence')}" if res.ok else f"FAILED: {'; '.join(res.errors)}"))
        rows.append({"photo": photo.name, "ok": res.ok, "seconds": round(secs, 2),
                     "attempts": res.attempts, "tokens_per_sec": round(res.eval_tokens_per_sec, 1),
                     "result": res.data, "errors": res.errors})
        if i == 1:
            share, vram, size = gpu_share()

    good = [r["seconds"] for r in rows if r["ok"]]
    summary = {
        "when": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "model": MODEL,
        "photos_tested": len(rows),
        "valid_json": len(good),
        "avg_seconds_per_image": round(sum(good) / len(good), 1) if good else None,
        "model_load_seconds": round(load_s, 1),
        "gpu_share": None if share is None else round(share, 3),
        "model_vram_gb": round(vram / 1e9, 2),
        "model_total_gb": round(size / 1e9, 2),
        "rows": rows,
    }
    out = RESULT_FILE if COUNT >= WANTED else LOCAL / "last_quick_test.json"
    out.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print("\n----- RESULT -----")
    print(f"Valid answers:        {len(good)} of {len(rows)}")
    print(f"Average per image:    {summary['avg_seconds_per_image']} s (model load: {summary['model_load_seconds']} s)")
    print(f"Model in GPU memory:  {summary['model_vram_gb']} GB of {summary['model_total_gb']} GB")
    if share is None:
        print("GPU check:            UNKNOWN (could not read Ollama's status)")
        return 1
    if share >= 0.99:
        print("GPU check:            PASS - running fully on the graphics card")
        return 0
    if share > 0:
        print(f"GPU check:            PARTIAL - only {share:.0%} on the graphics card, the rest on the CPU")
        return 1
    print("GPU check:            FAIL - running on the CPU, not the graphics card")
    return 1


_args = argparse.ArgumentParser(description=__doc__)
_args.add_argument("model", nargs="?", default=vision.DEFAULT_MODEL)
_args.add_argument("--count", type=int, default=WANTED, help="how many photos to test")
_parsed = _args.parse_args()
MODEL, COUNT = _parsed.model, max(1, _parsed.count)

if __name__ == "__main__":
    t = time.monotonic()
    code = main()
    print(f"(test took {time.monotonic() - t:.0f} s)")
    sys.exit(code)
