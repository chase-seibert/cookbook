"""Shared fingerprint and image inspection helpers for generated thumbnails."""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path

PROMPT_VERSION = "recipe-photo-v1"
WIDTH = 1024
HEIGHT = 768
MIN_BYTES = 50_000
MAX_BYTES = 300_000


def fingerprint(recipe: dict) -> str:
    """Fingerprint every recipe field that can affect the full-description prompt."""
    payload = {
        "promptVersion": PROMPT_VERSION,
        "output": {"format": "jpeg", "width": WIDTH, "height": HEIGHT},
        "sourceHash": recipe["sourceHash"],
        "title": recipe["title"],
        "introduction": recipe["introduction"],
        "ingredients": [(item["quantity"], item["name"]) for item in recipe["ingredients"]],
        "steps": [(step["sectionTitle"], step["instruction"]) for step in recipe["steps"]],
        "tips": recipe["tips"],
        "healthierOptions": recipe["healthierOptions"],
    }
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def image_info(path: Path) -> tuple[str, int, int]:
    """Return image format and pixel dimensions using macOS's built-in sips decoder."""
    result = subprocess.run(
        ["sips", "-g", "format", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
        check=True, capture_output=True, text=True,
    ).stdout
    values = {}
    for line in result.splitlines():
        if ":" in line:
            key, value = line.rsplit(":", 1)
            values[key.strip().split()[-1]] = value.strip()
    return values.get("format", "").lower(), int(values["pixelWidth"]), int(values["pixelHeight"])


def valid_asset(path: Path) -> bool:
    try:
        image_format, width, height = image_info(path)
        size = path.stat().st_size
        return image_format in {"jpeg", "jpg"} and width == WIDTH and height == HEIGHT and MIN_BYTES <= size <= MAX_BYTES
    except (OSError, subprocess.CalledProcessError, KeyError, ValueError):
        return False
