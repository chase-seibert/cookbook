#!/usr/bin/env python3
"""Parser and renderers for the versioned cookbook recipe Markdown format."""
from __future__ import annotations

from dataclasses import dataclass
from html import escape as html_escape
import json
import re
from pathlib import Path
from typing import Any

FORMAT = "cookbook-recipe/v1"
LAYOUTS = {"default", "compact"}
FRACTIONS_TO_TEX = {
    "⅛": r"\sfrac{1}{8}", "⅜": r"\sfrac{3}{8}", "⅝": r"\sfrac{5}{8}",
    "⅞": r"\sfrac{7}{8}", "⅓": r"\sfrac{1}{3}", "⅔": r"\sfrac{2}{3}",
    "¼": r"\sfrac{1}{4}", "½": r"\sfrac{1}{2}", "¾": r"\sfrac{3}{4}",
}
FRACTIONS_TO_UNICODE = {value: key for key, value in FRACTIONS_TO_TEX.items()}
LABELS = {
    "Introduction": "intro", "Tip": "tip", "Healthier option": "healthier",
}
TEX_MACROS = {"intro": "pre", "tip": "tip", "healthier": "healthierOption"}


@dataclass
class Recipe:
    path: Path
    metadata: dict[str, str]
    title: str
    blocks: list[dict[str, Any]]

    @property
    def recipe_id(self) -> str:
        return self.metadata["id"]

    @property
    def kind(self) -> str:
        return self.metadata.get("kind", "recipe")

    @property
    def layout(self) -> str:
        return self.metadata.get("layout", "default")


def _unescape_markdown(text: str) -> str:
    return re.sub(r"\\([\\`*_{}\[\]<>|])", r"\1", text)


def _split_table_row(line: str) -> list[str]:
    text = line.strip()
    if not text.startswith("|") or not text.endswith("|"):
        raise ValueError("table row must begin and end with |")
    cells = re.split(r"(?<!\\)\|", text[1:-1])
    return [_unescape_markdown(cell.strip()) for cell in cells]


def parse_recipe(path: str | Path) -> Recipe:
    path = Path(path)
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        raise ValueError(f"{path}:1: missing YAML front matter")
    metadata: dict[str, str] = {}
    index = 1
    while index < len(lines) and lines[index] != "---":
        line = lines[index]
        match = re.fullmatch(r"([a-z][a-z0-9_-]*):\s*(.*?)\s*", line)
        if not match:
            raise ValueError(f"{path}:{index + 1}: expected a simple key: value front-matter field")
        key, value = match.groups()
        if key in metadata:
            raise ValueError(f"{path}:{index + 1}: duplicate front-matter key {key!r}")
        metadata[key] = value
        index += 1
    if index >= len(lines):
        raise ValueError(f"{path}: missing closing front-matter delimiter")
    for key in ("format", "id"):
        if not metadata.get(key):
            raise ValueError(f"{path}: front matter requires {key!r}")
    if metadata["format"] != FORMAT:
        raise ValueError(f"{path}: unsupported format {metadata['format']!r}; expected {FORMAT!r}")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", metadata["id"]):
        raise ValueError(f"{path}: id must contain only letters, digits, underscores, or hyphens")
    if metadata.get("kind", "recipe") not in {"recipe", "collection"}:
        raise ValueError(f"{path}: kind must be 'recipe' or 'collection'")
    if metadata.get("layout", "default") not in LAYOUTS:
        raise ValueError(f"{path}: layout must be one of {', '.join(sorted(LAYOUTS))}")
    allowed = {"format", "id", "kind", "layout"}
    unknown = set(metadata) - allowed
    if unknown:
        raise ValueError(f"{path}: unsupported front-matter field(s): {', '.join(sorted(unknown))}")

    index += 1
    blocks: list[dict[str, Any]] = []
    title: str | None = None
    while index < len(lines):
        line = lines[index]
        if not line.strip():
            index += 1
            continue
        if title is None and not line.startswith("# "):
            raise ValueError(f"{path}:{index + 1}: H1 title must precede recipe content")
        if line.startswith("# "):
            if title is not None:
                raise ValueError(f"{path}:{index + 1}: more than one H1 title")
            title = _unescape_markdown(line[2:].strip())
            if not title:
                raise ValueError(f"{path}:{index + 1}: title must not be empty")
            index += 1
            continue
        if line.startswith("###") or line.startswith("####"):
            raise ValueError(f"{path}:{index + 1}: only H1 and H2 headings are supported")
        if line.startswith("## "):
            heading = _unescape_markdown(line[3:].strip())
            if not heading:
                raise ValueError(f"{path}:{index + 1}: subsection heading must not be empty")
            blocks.append({"type": "subsection", "text": heading})
            index += 1
            continue
        if line == '<div class="page-break"></div>':
            blocks.append({"type": "pagebreak"})
            index += 1
            continue
        if line.startswith("> "):
            match = re.fullmatch(r"> \*\*(Introduction|Tip|Healthier option):\*\*\s*(.*)", line)
            if not match:
                raise ValueError(f"{path}:{index + 1}: blockquote must begin with a supported label")
            label, initial = match.groups()
            pieces = [_unescape_markdown(initial)]
            index += 1
            while index < len(lines) and lines[index].startswith("> "):
                pieces.append(_unescape_markdown(lines[index][2:]))
                index += 1
            block_type = LABELS[label]
            blocks.append({"type": block_type, "text": " ".join(p.strip() for p in pieces).strip()})
            continue
        if line.startswith("|"):
            if index + 1 >= len(lines) or not re.fullmatch(r"\|\s*:?-{3,}:?\s*\|\s*:?-{3,}:?\s*\|", lines[index + 1]):
                raise ValueError(f"{path}:{index + 1}: table requires a two-column separator row")
            headers = _split_table_row(line)
            if headers == ["Quantity", "Ingredient"]:
                table_type = "ingredients"
            elif headers == ["Time", "Task"]:
                table_type = "schedule"
            else:
                raise ValueError(f"{path}:{index + 1}: unsupported table headers {headers!r}")
            index += 2
            rows: list[list[str]] = []
            while index < len(lines) and lines[index].startswith("|"):
                cells = _split_table_row(lines[index])
                if len(cells) != 2:
                    raise ValueError(f"{path}:{index + 1}: table rows must have exactly two cells")
                if not any(cells):
                    raise ValueError(f"{path}:{index + 1}: table row must not be empty")
                rows.append(cells)
                index += 1
            if not rows:
                raise ValueError(f"{path}:{index + 1}: {table_type} table must have at least one row")
            blocks.append({"type": table_type, "rows": rows})
            continue
        if re.match(r"\d+\.\s+", line):
            raise ValueError(f"{path}:{index + 1}: use a bare paragraph for each instruction step")
        # In this experimental format, every otherwise-unrecognized body
        # paragraph is an instruction step. Physical line wraps within a
        # paragraph are joined until a blank line or the next structured block.
        pieces = [line.strip()]
        index += 1
        while index < len(lines) and lines[index].strip():
            following = lines[index]
            if (
                following.startswith(("# ", "## ", "> ", "|"))
                or following == '<div class="page-break"></div>'
            ):
                break
            pieces.append(following.strip())
            index += 1
        step = _unescape_markdown(" ".join(pieces)).strip()
        if not step:
            raise ValueError(f"{path}:{index}: instruction step must not be empty")
        blocks.append({"type": "step", "text": step})
    if title is None:
        raise ValueError(f"{path}: exactly one H1 title is required")
    return Recipe(path=path, metadata=metadata, title=title, blocks=blocks)


def validate_recipe(path: str | Path) -> Recipe:
    recipe = parse_recipe(path)
    # A collection must explicitly carry collection kind; a recipe still needs content.
    if not recipe.blocks:
        raise ValueError(f"{path}: recipe body must contain at least one section, note, table, or step")
    for number, block in enumerate(recipe.blocks, start=1):
        if block["type"] in {"intro", "tip", "healthier"} and not block["text"]:
            raise ValueError(f"{path}: content block {number} has an empty note")
    return recipe


def _latex_escape(text: str) -> str:
    text = _unescape_markdown(text)
    replacements = {
        "\\": r"\textbackslash{}", "&": r"\&", "%": r"\%", "$": r"\$",
        "#": r"\#", "_": r"\_", "{": r"\{", "}": r"\}",
        "~": r"\textasciitilde{}", "^": r"\textasciicircum{}",
    }
    text = "".join(replacements.get(ch, ch) for ch in text)
    for char, macro in FRACTIONS_TO_TEX.items():
        text = text.replace(char, macro)
    return text.replace("°", r"\degree{}")


def render_latex(recipe: Recipe) -> str:
    out = [rf"\section{{{_latex_escape(recipe.title)}}}", r"\begin{recipe}", ""]
    blocks = recipe.blocks
    prefix: list[dict[str, Any]] = []
    if recipe.layout == "compact":
        first_subsection = next((i for i, block in enumerate(blocks) if block["type"] == "subsection"), len(blocks))
        prefix, blocks = blocks[:first_subsection], blocks[first_subsection:]
        for block in prefix:
            kind = block["type"]
            if kind in TEX_MACROS:
                out.extend([rf"\{TEX_MACROS[kind]}{{", "    " + _latex_escape(block["text"]), "}", ""])
            elif kind == "step":
                out.extend([_latex_escape(block["text"]), ""])
            elif kind == "ingredients":
                out.append(r"\ingredients{")
                out.extend("    " + _latex_escape(q) + " & " + _latex_escape(name) + r" \\" for q, name in block["rows"])
                out.extend(["}", ""])
            elif kind == "schedule":
                out.append(r"\ingredientsLeft{")
                out.extend("     & " + _latex_escape(" ".join((time, task)).strip()) + r" \\" for time, task in block["rows"])
                out.extend(["}", ""])
            elif kind == "pagebreak":
                out.extend([r"\newpage", ""])
            else:
                raise ValueError(f"compact layout cannot place leading block {kind!r} before its layout group")
        out.extend([
            r"\begingroup",
            r"\titleformat{\subsection}[block]{\normalfont\small\bfseries}{}{0pt}{}",
            r"\titlespacing*{\subsection}{0pt}{.35em}{.1em}",
            r"\renewcommand{\arraystretch}{.82}",
            r"\setlength{\tabcolsep}{2pt}",
            r"\setlength{\parskip}{.25em}",
            r"\renewcommand\ingredients[1]{",
            r"    \sffamily\bfseries",
            r"    \begin{tabularx}{\linewidth}{ R{3em} X }",
            r"        #1",
            r"    \end{tabularx}",
            r"    \vspace{.2em}\mdseries",
            r"}",
            r"\footnotesize",
            "",
        ])
    for block in blocks:
        kind = block["type"]
        if kind == "subsection":
            out.extend([rf"\subsection{{{_latex_escape(block['text'])}}}", ""])
        elif kind == "pagebreak":
            out.extend([r"\newpage", ""])
        elif kind in TEX_MACROS:
            macro = TEX_MACROS[kind]
            out.extend([rf"\{macro}{{", "    " + _latex_escape(block["text"]), "}", ""])
        elif kind in {"ingredients", "schedule"}:
            macro = "ingredients" if kind == "ingredients" else "ingredientsLeft"
            out.append(rf"\{macro}{{")
            for first, second in block["rows"]:
                if kind == "schedule":
                    first, second = "", " ".join((first, second)).strip()
                out.append("    " + _latex_escape(first) + " & " + _latex_escape(second) + r" \\")
            out.extend(["}", ""])
        elif kind == "step":
            out.extend([_latex_escape(block["text"]), ""])
        else:
            raise ValueError(f"unsupported content block {kind!r}")
    if recipe.layout == "compact":
        out.extend([r"\endgroup", ""])
    out.extend([r"\end{recipe}", ""])
    return "\n".join(out)


def render_html(recipe: Recipe) -> str:
    out = [f'<article class="recipe recipe--{html_escape(recipe.layout)}">',
           f'<h2 id="{html_escape(recipe.recipe_id)}">{html_escape(recipe.title)}</h2>']
    index = 0
    while index < len(recipe.blocks):
        block = recipe.blocks[index]
        kind = block["type"]
        if kind == "subsection":
            out.append(f'<h3>{html_escape(block["text"])}</h3>')
        elif kind == "pagebreak":
            out.append('<div class="page-break"></div>')
        elif kind in LABELS.values():
            label = {"intro": "Introduction", "tip": "Tip", "healthier": "Healthier option"}[kind]
            out.append(f'<blockquote><strong>{label}:</strong> {html_escape(block["text"])}</blockquote>')
        elif kind == "ingredients":
            out.append('<table class="ingredients"><thead><tr><th>Quantity</th><th>Ingredient</th></tr></thead><tbody>')
            out.extend(f'<tr><td>{html_escape(q)}</td><td>{html_escape(name)}</td></tr>' for q, name in block["rows"])
            out.append('</tbody></table>')
        elif kind == "schedule":
            out.append('<table class="schedule"><thead><tr><th>Time</th><th>Task</th></tr></thead><tbody>')
            out.extend(f'<tr><td>{html_escape(time)}</td><td>{html_escape(task)}</td></tr>' for time, task in block["rows"])
            out.append('</tbody></table>')
        elif kind == "step":
            steps = []
            while index < len(recipe.blocks) and recipe.blocks[index]["type"] == "step":
                steps.append(recipe.blocks[index]["text"])
                index += 1
            out.append('<ol class="steps">')
            out.extend(f'<li>{html_escape(step)}</li>' for step in steps)
            out.append('</ol>')
            continue
        else:
            raise ValueError(f"unsupported content block {kind!r}")
        index += 1
    out.append('</article>')
    return "\n".join(out) + "\n"


def content_json(recipe: Recipe) -> str:
    return json.dumps(recipe.blocks, ensure_ascii=False, separators=(",", ":"))
