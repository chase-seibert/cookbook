#!/usr/bin/env python3

import os
import argparse
import re
from collections import OrderedDict


def extract_tag_value(latex_string, latex_tag):
    match = re.search(r"\\" + latex_tag + r"\{(.*?)\}", latex_string)
    return match.group(1) if match else None


def has_tag(latex_string, latex_tag):
    match = re.search(r"\\" + latex_tag + r"\ ?{", latex_string)
    return True if match else False


def slugify(text):
    text = text.lower()
    return re.sub(r'[\W_]+', '-', text)


def parse_index_file(index_file):
    if not os.path.exists(index_file):
        print(f"Error: File '{index_file}' does not exist.")
        return
    result, recipes = OrderedDict(), []
    with open(index_file, 'r', encoding='utf-8') as file:
        for line in file.readlines():
            chapter = extract_tag_value(line, "chapter")
            if chapter:
                recipes = []
            input = extract_tag_value(line, "input")
            if input:
                recipes.append(input)
            if chapter:
                result[chapter] = recipes
    return result


def generate_index_html(data):
    output = ''
    for chapter, recipes in data.items():
        output += '<h1>%s</h1>\n' % chapter
        for recipe in recipes:
            # the second value is a placeholder, won't know actual title until 
            # we read every recipe (at the end)
            output += '   <a href="#%s">%s-title</a><br>\n' % (
                slugify(recipe), slugify(recipe))
    return output


def generate_recipe_html(recipe_slug, recipe_lines):
    recipe_title = None
    output = ""
    indent = ''
    breaks = False
    for line in recipe_lines:
        section = extract_tag_value(line, "section")
        subsection = extract_tag_value(line, "subsection")
        if section:
            recipe_title = section
            output += "<h2 id='%s'>%s</h2>" % (slugify(recipe_slug), section)
        elif subsection:
            output += "<h3>%s</h3>" % (subsection)
        elif has_tag(line, "begin"):
            continue
        elif has_tag(line, "pre"):
            indent = ''
            breaks = False
            continue
        elif has_tag(line, "tip"):
            indent = ''
            breaks = False
            continue
        elif has_tag(line, "ingredients") or has_tag(line, "ingredientsLeft"):
            indent = '   '
            breaks = True
            continue
        elif has_tag(line, "end"):
            continue
        elif line.strip() == "}":
            indent = ''
            breaks = False
            continue
        elif line.strip() == "":
            output += "<br><br>"
        else:
            line = line.replace("\\\\", "")
            line = line.replace(" & ", " ")
            line = line.replace("\\degree{}", "°")
            line = line.replace("\\degree", "°")
            line = line.replace("\\sfrac{1}{2}", "½")
            line = line.replace("\\sfrac{1}{4}", "¼")
            line = line.replace("\\sfrac{1}{8}", "⅛")
            line = line.replace("\\sfrac{3}{4}", "¾")
            line = line.replace("\\sfrac{1}{3}", "⅓")
            if indent:
                line = '&nbsp;' * len(indent) + line
            if breaks:
                line += "<br>"
            output += line
    output = re.sub(r'\n{2,}', '\n', output)  # collapse multiple newlines
    output = re.sub(r'\s{2,}', ' ', output)  # collapse multiple spaces
    output = re.sub(r'(<br>){2,}', '<br><br>', output)
    output = output.replace("</h2><br><br>", "</h2>")
    output = output.replace("<br><br><h2", "<h2")
    output = output.replace("</h3><br><br>", "</h3>")
    return recipe_title, output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert LaTeX files HTML")
    parser.add_argument("--index2", action="store", help="File containing the index *.tex file")
    args = parser.parse_args()
    data = parse_index_file(args.index2)
    if not data:
        print("Could not parse index file")
        exit(1)
    index_html = generate_index_html(data)
    recipes_html = ''
    for chapter, recipes in data.items():
        for recipe in recipes:
            recipe_file = "%s.tex" % recipe
            if not os.path.exists(recipe_file):
                print(f"Error: File '{recipe_file}' does not exist.")
                exit(1)
            with open(recipe_file, 'r', encoding='utf-8') as file:
                recipe_lines = file.readlines()
                recipe_title, recipe_html = generate_recipe_html(
                    recipe, recipe_lines)
                # we put down a placeholder for this to replace now 
                # that we know the real title of the recipe
                index_html = index_html.replace(
                    "%s-title" % slugify(recipe), recipe_title)
                recipes_html += recipe_html
                recipes_html += "\n\n"
    print(index_html)
    print(recipes_html)
