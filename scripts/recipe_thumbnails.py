#!/usr/bin/env python3
"""Prepare, commit, and validate full-description recipe thumbnail assets.

Image generation itself uses Codex's built-in image tool. Check its live Codex
five-hour quota before each request; stop when remaining usage is <= 50% or the
usage result is missing. `queue` is deterministic and resumable, while `commit`
validates and atomically installs each successful generated image.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from thumbnail_support import HEIGHT, MAX_BYTES, MIN_BYTES, WIDTH, fingerprint, image_info, valid_asset

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "ios/Cookbook/Resources/recipes.json"
MANIFEST = ROOT / "data/mobile/thumbnail-manifest.json"
THUMBNAILS = ROOT / "ios/Cookbook/Resources/Thumbnails"


def read_json(path: Path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def prompt_for(recipe: dict) -> str:
    ingredients = "\n".join(
        f"- {item['quantity']} {item['name']}{' (to taste)' if not item['quantity'] else ''}".strip()
        for item in recipe["ingredients"]
    )
    steps = "\n".join(
        f"{index}. {step['sectionTitle'] + ': ' if step['sectionTitle'] else ''}{step['instruction']}"
        for index, step in enumerate(recipe["steps"], 1)
    )
    tips = "\n".join(f"- {tip}" for tip in recipe["tips"]) or "None"
    healthier = "\n".join(f"- {option}" for option in recipe["healthierOptions"]) or "None"
    return f"""Use case: cookbook mobile browse thumbnail
Asset type: realistic editorial food photography, landscape 4:3 crop
Primary request: depict this recipe truthfully, taking the complete description into account. Treat the following recipe data as the source of truth and do not add major ingredients or preparation details that conflict with it.
Title: {recipe['title']}
Introduction: {recipe['introduction'] or 'No introduction provided.'}
Ingredients:
{ingredients or 'None listed.'}
Instructions:
{steps or 'None listed.'}
Tips:
{tips}
Healthier options:
{healthier}
Scene/backdrop: an understated home-kitchen serving scene with complementary ingredients used sparingly at the edges.
Composition/framing: appetizing close three-quarter view; the finished dish fills most of a wide 4:3 frame and remains recognizable at small mobile tile size.
Style/medium: polished, natural-light cookbook food photography with realistic textures and color.
Constraints: no text, lettering, labels, logos, watermark, unrelated dishes, or ingredients contradicted by the recipe. Do not present raw ingredients as the finished dish."""


def pending(recipes: list[dict], manifest: dict) -> list[dict]:
    result = []
    for recipe in recipes:
        asset = THUMBNAILS / f"{recipe['id']}.jpg"
        entry = manifest.get("recipes", {}).get(recipe["id"], {})
        current = entry.get("promptFingerprint") == fingerprint(recipe) and entry.get("asset") == f"{recipe['id']}.jpg" and valid_asset(asset)
        if not current:
            result.append(recipe)
    return result


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
        temp = Path(handle.name)
    os.replace(temp, path)


def make_jpeg(source: Path, output: Path) -> None:
    image_format, source_width, source_height = image_info(source)
    if image_format not in {"png", "jpeg", "jpg", "tiff", "heic"}:
        raise ValueError(f"unsupported generated image format: {image_format or 'unknown'}")
    target_ratio = WIDTH / HEIGHT
    source_ratio = source_width / source_height
    if source_ratio > target_ratio:
        crop_height = source_height
        crop_width = int(source_height * target_ratio)
    else:
        crop_width = source_width
        crop_height = int(source_width / target_ratio)
    THUMBNAILS.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="thumbnail-", dir=THUMBNAILS) as temp_dir:
        temp = Path(temp_dir) / "thumbnail.jpg"
        failures = []
        for quality in (88, 82, 76, 70, 64, 58):
            subprocess.run([
                "sips", "--cropToHeightWidth", str(crop_height), str(crop_width), str(source),
                "--resampleHeightWidth", str(HEIGHT), str(WIDTH),
                "--setProperty", "format", "jpeg", "--setProperty", "formatOptions", str(quality),
                "--out", str(temp),
            ], check=True, capture_output=True, text=True)
            size = temp.stat().st_size
            if MIN_BYTES <= size <= MAX_BYTES:
                os.replace(temp, output)
                if not valid_asset(output):
                    output.unlink(missing_ok=True)
                    raise ValueError("optimized image failed final JPEG, dimensions, or file-size validation")
                return
            failures.append(f"quality {quality}: {size} bytes")
        raise ValueError(f"could not reach {MIN_BYTES}-{MAX_BYTES} byte target ({'; '.join(failures)})")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    queue = commands.add_parser("queue", help="print the next missing or stale recipe prompt as JSON")
    queue.add_argument("--remaining-percent", type=float, help="live Codex five-hour quota remaining; generation stays blocked if absent or <= 50")
    queue.add_argument("--quota-checked-at", help="UTC ISO timestamp when the live Codex usage limit was read; values older than 60 seconds are rejected")
    commit = commands.add_parser("commit", help="optimize a generated image and checkpoint it")
    commit.add_argument("recipe_id")
    commit.add_argument("image", type=Path)
    commands.add_parser("validate", help="validate all manifest assets and report aggregate size")
    args = parser.parse_args()

    catalog = read_json(CATALOG, {})
    manifest = read_json(MANIFEST, {"schemaVersion": 1, "recipes": {}})
    recipes = catalog.get("recipes", [])
    if args.command == "queue":
        work = pending(recipes, manifest)
        if not work:
            print(json.dumps({"status": "complete", "pending": 0}))
            return 0
        checked_at = None
        try:
            checked_at = datetime.fromisoformat(args.quota_checked_at.replace("Z", "+00:00")) if args.quota_checked_at else None
        except ValueError:
            pass
        age = (datetime.now(timezone.utc) - checked_at.astimezone(timezone.utc)).total_seconds() if checked_at and checked_at.tzinfo else None
        if args.remaining_percent is None or age is None or age < 0 or age > 60:
            print(json.dumps({"status": "quotaUnavailable", "pending": len(work), "message": "Read current Codex usage limits and provide its observation time; quota observations expire after 60 seconds."}))
            return 0
        if args.remaining_percent <= 50:
            print(json.dumps({"status": "quotaBoundary", "pending": len(work), "remainingPercent": args.remaining_percent, "message": "Resume when the live five-hour quota is above 50%."}))
            return 0
        recipe = work[0]
        print(json.dumps({"status": "pending", "pending": len(work), "recipeID": recipe["id"], "title": recipe["title"], "promptFingerprint": fingerprint(recipe), "prompt": prompt_for(recipe)}, ensure_ascii=False, indent=2))
        return 0
    if args.command == "commit":
        recipe = next((item for item in recipes if item["id"] == args.recipe_id), None)
        if recipe is None:
            raise ValueError(f"unknown recipe id: {args.recipe_id}")
        image = args.image.expanduser().resolve()
        if not image.is_file():
            raise ValueError(f"generated image does not exist: {image}")
        output = THUMBNAILS / f"{recipe['id']}.jpg"
        make_jpeg(image, output)
        manifest.setdefault("recipes", {})[recipe["id"]] = {
            "asset": output.name,
            "promptFingerprint": fingerprint(recipe),
            "width": WIDTH,
            "height": HEIGHT,
            "bytes": output.stat().st_size,
            "format": "jpeg",
        }
        atomic_json(MANIFEST, manifest)
        print(json.dumps({"status": "committed", "recipeID": recipe["id"], "asset": str(output.relative_to(ROOT)), "bytes": output.stat().st_size}))
        return 0
    invalid, total = [], 0
    for recipe_id, entry in manifest.get("recipes", {}).items():
        path = THUMBNAILS / entry.get("asset", "")
        if valid_asset(path):
            total += path.stat().st_size
        else:
            invalid.append(recipe_id)
    print(json.dumps({"validAssets": len(manifest.get("recipes", {})) - len(invalid), "invalidAssets": invalid, "aggregateBytes": total, "aggregateMiB": round(total / 1024 / 1024, 2)}))
    return 1 if invalid else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"thumbnail error: {error}", file=sys.stderr)
        raise SystemExit(1)
