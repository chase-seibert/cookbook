#!/usr/bin/env python3
"""Build the iOS offline catalog from the authoritative Markdown recipes."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

from cookbook_index import load_index, subsection_slug
from recipe_markdown import Recipe, validate_recipe

ROOT = Path(__file__).resolve().parents[1]
METADATA_PATH = ROOT / "data/mobile/metadata.json"
THUMBNAIL_MANIFEST_PATH = ROOT / "data/mobile/thumbnail-manifest.json"
THUMBNAIL_DIRECTORY = ROOT / "ios/Cookbook/Resources/Thumbnails"
def recipe_segments(recipe: Recipe) -> list[tuple[str, str, list[dict]]]:
    """Return title, stable ID, and ordered body blocks for each mobile recipe."""
    if recipe.kind != "collection":
        return [(recipe.title, recipe.recipe_id, recipe.blocks)]

    headings = [i for i, block in enumerate(recipe.blocks) if block["type"] == "subsection"]
    if not headings:
        raise ValueError(f"{recipe.path.name}: collection requires at least one H2 recipe heading")
    result = []
    for position, heading_index in enumerate(headings):
        title = recipe.blocks[heading_index]["text"]
        end = headings[position + 1] if position + 1 < len(headings) else len(recipe.blocks)
        stable_id = f"{recipe.recipe_id}-{subsection_slug(title)}"
        result.append((title, stable_id, recipe.blocks[heading_index + 1:end]))
    return result


def mobile_recipe(recipe: Recipe, slug: str, category: str, title: str, stable_id: str,
                  blocks: list[dict], metadata: dict) -> dict:
    ingredients: list[dict] = []
    steps: list[dict] = []
    tips: list[str] = []
    healthier_options: list[str] = []
    introduction = ""
    section_title = title if recipe.kind == "collection" else ""
    latest_ingredient_ids: list[str] = []
    ingredient_overrides = metadata.get("ingredientOverrides", {})
    staple_names = {" ".join(item.casefold().split()) for item in metadata.get("stapleGroceryNames", [])}
    excluded_names = {" ".join(item.casefold().split()) for item in metadata.get("excludedGroceryNames", [])}
    staple_patterns = metadata.get("pantryStaplePatterns", [])

    def add_ingredient(quantity: str, name: str) -> str:
        ingredient_id = f"{stable_id}-ingredient-{len(ingredients) + 1}"
        override = ingredient_overrides.get(ingredient_id, {})
        grocery_name = clean_grocery_name(override.get("groceryName", name))
        normalized = " ".join(grocery_name.casefold().split())
        is_staple = normalized in staple_names or any(re.search(pattern, normalized, re.I) for pattern in staple_patterns)
        is_excluded = normalized in excluded_names
        ingredients.append({
            "id": ingredient_id,
            "quantity": quantity,
            "name": name,
            "groceryName": grocery_name,
            "staple": override.get("staple", is_staple),
            "excludeFromGroceries": override.get("excludeFromGroceries", is_excluded),
        })
        return ingredient_id

    for block in blocks:
        kind = block["type"]
        if kind == "subsection":
            section_title = block["text"]
        elif kind == "intro" and not introduction:
            introduction = block["text"]
        elif kind == "tip":
            tips.append(block["text"])
        elif kind == "healthier":
            healthier_options.append(block["text"])
        elif kind in {"ingredients", "schedule"}:
            current_ids = []
            for first, second in block["rows"]:
                if kind == "schedule":
                    first, second = "", " ".join((first, second)).strip()
                current_ids.append(add_ingredient(first, second))
            latest_ingredient_ids = current_ids
        elif kind == "step":
            step_id = f"{stable_id}-step-{len(steps) + 1}"
            assigned = metadata.get("stepIngredientIDs", {}).get(step_id, latest_ingredient_ids)
            steps.append({
                "id": step_id,
                "sectionTitle": section_title,
                "instruction": block["text"],
                "originalInstruction": block["text"],
                "ingredientIDs": assigned,
                "durationMinutes": None,
                "active": True,
            })

    canonical = json.dumps(
        {"title": title, "blocks": blocks},
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return {
        "id": stable_id,
        "title": title,
        "category": category,
        "collectionTitle": recipe.title if recipe.kind == "collection" else None,
        "sourceFile": f"{slug}.md",
        "sourceSection": title,
        "introduction": introduction,
        "ingredients": ingredients,
        "steps": steps,
        "tips": tips,
        "healthierOptions": healthier_options,
        "sourceHash": hashlib.sha256(canonical).hexdigest(),
    }


def clean_grocery_name(value: str) -> str:
    """Keep the ingredient identity while removing package/measurement wording."""
    name = " ".join(value.split())
    name = re.sub(r"^(?:\d+(?:[./]\d+)?\s+)?", "", name)
    name = re.sub(r"^(?:small|medium|large|extra[- ]large)\s+", "", name, flags=re.I)
    name = re.sub(r"^(?:cups?|tablespoons?|teaspoons?|ounces?|oz|pounds?|lbs?|grams?|kilograms?|quarts?|pints?|gallons?|cloves?|sticks?|cans?|jars?|packages?|pkgs?|bags?|bottles?|boxes?|bunches?|heads?)\s+(?:of\s+)?", "", name, flags=re.I)
    name = re.sub(r"^(?:can|jar|package|pkg|bag|bottle|box|container)\s+(?:of\s+)?", "", name, flags=re.I)
    name = name.strip(" ,.-")
    return name[:1].upper() + name[1:] if name else name


def build() -> dict:
    metadata = json.loads(METADATA_PATH.read_text(encoding="utf-8")) if METADATA_PATH.exists() else {}
    categories, entries = load_index()
    recipes, seen_files = [], set()
    for slug, category in entries:
        if slug in seen_files:
            raise ValueError(f"duplicate index entry: {slug}")
        seen_files.add(slug)
        source = validate_recipe(ROOT / "recipes" / f"{slug}.md")
        for title, stable_id, blocks in recipe_segments(source):
            recipes.append(mobile_recipe(source, slug, category, title, stable_id, blocks, metadata))
    identities = [r["id"] for r in recipes]
    if len(identities) != len(set(identities)):
        raise ValueError("duplicate stable recipe IDs")
    for recipe in recipes:
        if not recipe["steps"]:
            raise ValueError(f"{recipe['sourceFile']} ({recipe['title']}): no instruction paragraphs were parsed")
        ingredient_ids = {ingredient["id"] for ingredient in recipe["ingredients"]}
        for step in recipe["steps"]:
            unresolved = set(step["ingredientIDs"]) - ingredient_ids
            if unresolved:
                raise ValueError(f"{step['id']}: unknown ingredient IDs: {', '.join(sorted(unresolved))}")
    label_groups = metadata.get("labelGroups")
    labels = metadata.get("labels")
    assignments = metadata.get("recipeLabels")
    if any(value is not None for value in (label_groups, labels, assignments)):
        validate_labels(recipes, label_groups, labels, assignments)
        for recipe in recipes:
            recipe["labelIDs"] = assignments[recipe["id"]]
        taxonomy = {"labelGroups": label_groups, "labels": labels}
    else:
        taxonomy = {}
    if THUMBNAIL_MANIFEST_PATH.is_file():
        manifest = json.loads(THUMBNAIL_MANIFEST_PATH.read_text(encoding="utf-8"))
        from thumbnail_support import fingerprint

        for recipe in recipes:
            entry = manifest.get("recipes", {}).get(recipe["id"], {})
            asset_name = f"{recipe['id']}.jpg"
            if (entry.get("asset") == asset_name
                    and entry.get("promptFingerprint") == fingerprint(recipe)
                    and (THUMBNAIL_DIRECTORY / asset_name).is_file()):
                recipe["thumbnailAsset"] = asset_name
    thumbnail_overrides = metadata.get("reviewedThumbnailOverrides", {})
    if not isinstance(thumbnail_overrides, dict):
        raise ValueError("reviewedThumbnailOverrides must map recipe IDs to asset filenames")
    unknown_thumbnail_ids = set(thumbnail_overrides) - {recipe["id"] for recipe in recipes}
    if unknown_thumbnail_ids:
        raise ValueError(f"reviewed thumbnail overrides have unknown recipe IDs: {', '.join(sorted(unknown_thumbnail_ids))}")
    if thumbnail_overrides:
        from thumbnail_support import valid_asset

        for recipe_id, asset_name in thumbnail_overrides.items():
            if not isinstance(asset_name, str) or Path(asset_name).name != asset_name:
                raise ValueError(f"reviewed thumbnail override must be a filename: {recipe_id}")
            if not valid_asset(THUMBNAIL_DIRECTORY / asset_name):
                raise ValueError(f"reviewed thumbnail override is missing or invalid: {recipe_id} ({asset_name})")
            next(recipe for recipe in recipes if recipe["id"] == recipe_id)["thumbnailAsset"] = asset_name
    menu_copy_by_id = metadata.get("menuCopy", {})
    if not isinstance(menu_copy_by_id, dict):
        raise ValueError("menuCopy must be keyed by stable recipe IDs")
    known_recipe_ids = {recipe["id"] for recipe in recipes}
    unknown_menu_copy = set(menu_copy_by_id) - known_recipe_ids
    if unknown_menu_copy:
        raise ValueError(f"menuCopy has unknown recipe IDs: {', '.join(sorted(unknown_menu_copy))}")
    for recipe_id, menu_copy in menu_copy_by_id.items():
        if not isinstance(menu_copy, dict):
            raise ValueError(f"menuCopy entry must be an object: {recipe_id}")
        description = menu_copy.get("description")
        pairings = menu_copy.get("pairings")
        if description is not None and (not isinstance(description, str) or not description.strip()):
            raise ValueError(f"menu description must be non-empty text: {recipe_id}")
        if pairings is not None and (not isinstance(pairings, list) or any(not isinstance(value, str) or not value.strip() for value in pairings)):
            raise ValueError(f"menu pairings must be a list of non-empty strings: {recipe_id}")
    for recipe in recipes:
        menu_copy = menu_copy_by_id.get(recipe["id"], {})
        if menu_copy.get("description"):
            recipe["menuDescription"] = menu_copy["description"]
        if menu_copy.get("pairings"):
            recipe["menuPairings"] = menu_copy["pairings"]
    return {"schemaVersion": 1, "source": "recipes/index.json", "categoryOrder": [item["title"] for item in categories], **taxonomy, "recipeFileCount": len(seen_files), "recipes": recipes}


def validate_labels(recipes: list[dict], groups: object, labels: object, assignments: object) -> None:
    """Validate the curated, bundled browse taxonomy before emitting it."""
    if not isinstance(groups, list) or not isinstance(labels, list) or not isinstance(assignments, dict):
        raise ValueError("labelGroups, labels, and recipeLabels must be supplied together")
    group_ids = [group.get("id") for group in groups if isinstance(group, dict)]
    if len(group_ids) != len(groups) or len(group_ids) != len(set(group_ids)):
        raise ValueError("label groups must be objects with unique IDs")
    if any(not isinstance(group_id, str) or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", group_id) for group_id in group_ids):
        raise ValueError("label group IDs must be normalized lowercase slugs")
    if len({group.get("order") for group in groups}) != len(groups):
        raise ValueError("label groups must have unique order values")
    group_by_id = {group["id"]: group for group in groups}
    for group in groups:
        if not group.get("displayName") or group.get("menuRole") not in {"protein", "meal_style", "ingredient", "browse_type"}:
            raise ValueError(f"invalid label group metadata: {group.get('id')}")
        step = group.get("wizardStep")
        expected_steps = {"protein": 1, "meal_style": 2, "ingredient": 3}
        if group["menuRole"] == "browse_type":
            if step is not None or group.get("optional") is not True:
                raise ValueError(f"non-dinner group {group['id']} cannot have a wizard step")
        elif step != expected_steps[group["menuRole"]] or group.get("optional") != (step != 1):
            raise ValueError(f"invalid wizard step or optional flag for group {group['id']}")
        if not isinstance(group.get("optional"), bool) or not isinstance(group.get("allowsMultiple"), bool):
            raise ValueError(f"missing optional/multiple metadata for group {group['id']}")
    label_ids = [label.get("id") for label in labels if isinstance(label, dict)]
    if len(label_ids) != len(labels) or len(label_ids) != len(set(label_ids)):
        raise ValueError("labels must be objects with unique IDs")
    if any(not isinstance(label_id, str) or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", label_id) for label_id in label_ids):
        raise ValueError("label IDs must be normalized lowercase slugs")
    aliases_by_group: dict[str, dict[str, str]] = {group_id: {} for group_id in group_ids}
    all_aliases: dict[str, str] = {}
    label_orders: dict[str, set[int]] = {group_id: set() for group_id in group_ids}
    for label in labels:
        label_id = label.get("id")
        group_id = label.get("groupID")
        if group_id not in group_by_id or not label.get("displayName"):
            raise ValueError(f"invalid label metadata: {label_id}")
        if not isinstance(label.get("order"), int):
            raise ValueError(f"missing label order: {label_id}")
        if label["order"] in label_orders[group_id]:
            raise ValueError(f"duplicate label order in group {group_id}")
        label_orders[group_id].add(label["order"])
        aliases = label.get("aliases")
        if not isinstance(aliases, list):
            raise ValueError(f"aliases must be a list: {label_id}")
        normalized_display = " ".join(label["displayName"].casefold().split())
        normalized_aliases = [" ".join(value.casefold().split()) for value in aliases if isinstance(value, str)]
        if len(normalized_aliases) != len(aliases) or len(normalized_aliases) != len(set(normalized_aliases)) or normalized_display in normalized_aliases:
            raise ValueError(f"duplicate or invalid aliases for {label_id}")
        if any(value != raw for value, raw in zip(normalized_aliases, aliases)):
            raise ValueError(f"aliases must be normalized for {label_id}")
        for alias in [normalized_display, *normalized_aliases]:
            if not alias or alias in aliases_by_group[group_id]:
                raise ValueError(f"ambiguous or unnormalized alias '{alias}' in group {group_id}")
            if alias in all_aliases and all_aliases[alias] != label_id:
                raise ValueError(f"ambiguous alias '{alias}' maps to multiple labels")
            all_aliases[alias] = label_id
            aliases_by_group[group_id][alias] = label_id
    recipe_ids = {recipe["id"] for recipe in recipes}
    if set(assignments) != recipe_ids:
        missing = sorted(recipe_ids - set(assignments))
        unknown = sorted(set(assignments) - recipe_ids)
        raise ValueError(f"recipe label assignments do not cover catalog IDs (missing={missing}, unknown={unknown})")
    known_labels = set(label_ids)
    for recipe_id, ids in assignments.items():
        if not isinstance(ids, list) or not ids or len(ids) != len(set(ids)):
            raise ValueError(f"recipe {recipe_id} must have unique, non-empty label assignments")
        unknown = set(ids) - known_labels
        if unknown:
            raise ValueError(f"recipe {recipe_id} has unknown label IDs: {', '.join(sorted(unknown))}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="ios/Cookbook/Resources/recipes.json")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        data = build()
        output = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        target = ROOT / args.output
        if args.check:
            if not target.is_file() or target.read_text(encoding="utf-8") != output:
                print(f"Catalog is stale: run make catalog ({args.output})", file=sys.stderr)
                return 1
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(output, encoding="utf-8")
        print(f"{len(data['recipes'])} recipes from {data['recipeFileCount']} source files")
        return 0
    except (OSError, ValueError) as error:
        print(f"catalog error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
