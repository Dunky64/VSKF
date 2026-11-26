"""Transcribe audio or video files on this PC, fully offline after the first model download.

Used by transcribe.bat (drag a file onto it). Writes <name>.transcript.txt next to each file.
Runs on the CPU: faster-whisper does not support AMD graphics cards, and the Ryzen 7 5800X3D is quick enough.
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

MEDIA_EXT = {".mp3", ".m4a", ".wav", ".ogg", ".flac", ".aac",
             ".mp4", ".mov", ".mkv", ".webm", ".avi", ".m4v"}
MODELS = ["tiny", "base", "small", "medium", "large-v3"]


def fmt(seconds: float) -> str:
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    return f"{h:02d}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"


def transcribe_file(model, path: Path, language: str | None) -> Path:
    segments, info = model.transcribe(str(path), language=language, beam_size=5, vad_filter=True)
    print(f"  Language: {info.language} ({info.language_probability:.0%} sure), "
          f"length {fmt(info.duration)}")
    out = path.with_name(path.stem + ".transcript.txt")
    start = time.monotonic()
    lines = []
    for seg in segments:
        text = seg.text.strip()
        if text:
            lines.append(f"[{fmt(seg.start)}] {text}")
            print(f"    {fmt(seg.start)}  {text}")
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"  Done in {time.monotonic() - start:.0f} s. Saved: {out}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Transcribe audio/video files offline.")
    ap.add_argument("files", nargs="+", help="file(s) to transcribe")
    ap.add_argument("--model", default="small", choices=MODELS,
                    help="small = fast and good (default); medium = slower, more accurate")
    ap.add_argument("--language", default=None, help="e.g. en. Leave out to auto-detect.")
    args = ap.parse_args()

    files = [Path(f.strip('"')) for f in args.files]
    bad = [f for f in files if not f.is_file() or f.suffix.lower() not in MEDIA_EXT]
    for f in bad:
        print(f"SKIPPED (not a supported audio/video file, or not found): {f}")
    files = [f for f in files if f not in bad]
    if not files:
        print("Nothing to transcribe.")
        return 2

    try:
        from faster_whisper import WhisperModel
    except ImportError:
        print("The transcription library is not installed. Run setup.bat again.")
        return 3

    print(f"Loading the '{args.model}' model (first time only: it downloads once)...")
    model = WhisperModel(args.model, device="cpu", compute_type="int8", cpu_threads=8)
    failed = 0
    for f in files:
        print(f"\n==> {f.name}")
        try:
            transcribe_file(model, f, args.language)
        except Exception as exc:  # keep going with the next file
            failed += 1
            print(f"  FAILED: {exc}")
    print(f"\nFinished. {len(files) - failed} of {len(files)} transcribed.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
