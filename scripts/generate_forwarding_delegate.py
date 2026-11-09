#!/usr/bin/env python3
# Copyright 2026 The Oa Authors
# Use of this source code is governed by the license in the LICENSE file.
"""Writes core/browser/forwarding_web_contents_delegate.{h,cc}.

The class forwards every virtual method of content::WebContentsDelegate to an inner delegate, or to the content
default when there is none. It is generated because the interface has over a hundred methods and changes with every
Chromium release. Rerun this after bumping chromium/VERSION and commit the result:

    python3 scripts/generate_forwarding_delegate.py

It reads $CHROMIUM_SRC/content/public/browser/web_contents_delegate.h (default ~/chromium/src) and evaluates its
#if blocks for macOS.
"""

import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CHROMIUM_SRC = pathlib.Path(os.environ.get("CHROMIUM_SRC", ROOT / ".local" / "chromium" / "src"))
HEADER = CHROMIUM_SRC / "content/public/browser/web_contents_delegate.h"
OUT_H = ROOT / "core/browser/forwarding_web_contents_delegate.h"
OUT_MM = ROOT / "core/browser/forwarding_web_contents_delegate.cc"

# The build flags the header's #if blocks test, as they are on macOS.
FLAGS = {"IS_ANDROID": False, "IS_IOS": False, "IS_APPLE": True, "IS_MAC": True}


def evaluate(condition):
    expression = re.sub(r"BUILDFLAG\((\w+)\)", lambda m: str(FLAGS[m.group(1)]), condition)
    expression = expression.replace("||", " or ").replace("&&", " and ").replace("!", " not ")
    return eval(expression, {}, {})  # noqa: S307: only BUILDFLAGs above reach this


def class_body(text):
    """The lines of the class's public section, with comments removed and #if blocks resolved."""
    start = text.index("class CONTENT_EXPORT WebContentsDelegate {")
    end = text.index(" protected:", start)
    lines = []
    stack = []
    for line in text[start:end].splitlines()[1:]:
        stripped = line.strip()
        if stripped.startswith("#if"):
            stack.append(evaluate(stripped[3:].strip()))
            continue
        if stripped.startswith("#else"):
            stack[-1] = not stack[-1]
            continue
        if stripped.startswith("#endif"):
            stack.pop()
            continue
        if not all(stack):
            continue
        lines.append(re.sub(r"//.*", "", line))
    return "\n".join(lines)


def declarations(body):
    """Each `virtual ...;` or `virtual ... { ... }` statement, as one line."""
    result = []
    index = 0
    while True:
        index = body.find("virtual ", index)
        if index < 0:
            return result
        depth = 0
        cursor = index
        while True:
            char = body[cursor]
            if char in "({":
                depth += 1
            elif char in ")}":
                depth -= 1
                if depth == 0 and char == "}":
                    break
            elif char == ";" and depth == 0:
                break
            cursor += 1
        statement = " ".join(body[index:cursor + 1].split())
        result.append(statement)
        index = cursor + 1


def split_top_level(text):
    parts, depth, current = [], 0, ""
    for char in text:
        if char in "<({[":
            depth += 1
        elif char in ">)}]":
            depth -= 1
        if char == "," and depth == 0:
            parts.append(current.strip())
            current = ""
        else:
            current += char
    if current.strip():
        parts.append(current.strip())
    return parts


def parse(statement):
    """Returns (return type, name, [(type, name)], is_const) for one declaration."""
    statement = re.sub(r"^virtual ", "", statement)
    # Drop an inline body or `= 0`.
    head = statement
    if head.endswith("}"):
        depth = 0
        for position in range(len(head) - 1, -1, -1):
            if head[position] == "}":
                depth += 1
            elif head[position] == "{":
                depth -= 1
                if depth == 0:
                    head = head[:position].strip()
                    break
    head = head.rstrip(";").strip()
    head = re.sub(r"\s*=\s*0$", "", head)
    is_const = head.endswith(" const")
    if is_const:
        head = head[: -len(" const")].strip()
    # The parameter list is the last balanced (...) group.
    depth = 0
    for position in range(len(head) - 1, -1, -1):
        if head[position] == ")":
            depth += 1
        elif head[position] == "(":
            depth -= 1
            if depth == 0:
                open_paren = position
                break
    params_text = head[open_paren + 1 : -1]
    before = head[:open_paren].strip()
    name = re.search(r"(\w+)$", before).group(1)
    return_type = before[: -len(name)].strip()
    params = []
    for number, param in enumerate(split_top_level(params_text)):
        param = re.sub(r"\s*=.*$", "", param).strip()
        match = re.match(r"^(.*[\s*&>])(\w+)$", param)
        if match and match.group(1).strip() and not param.endswith((">", "*", "&")) and match.group(1).strip() not in (
            "const", "unsigned", "signed"
        ):
            params.append((match.group(1).strip(), match.group(2)))
        else:
            params.append((param, f"arg{number}"))
    return return_type, name, params, is_const


# Types the header names unqualified that aren't in namespace content.
GLOBAL_TYPES = {"GURL", "SkBitmap", "SkColor", "WindowOpenDisposition"}


def qualify(type_text):
    """Adds `content::` to the types the header names from inside namespace content."""
    type_text = re.sub(
        r"(?<![\w:])([A-Z]\w*)",
        lambda m: m.group(1) if m.group(1) in GLOBAL_TYPES else f"content::{m.group(1)}",
        type_text,
    )
    # content::mojom, which the header calls mojom.
    return re.sub(r"(?<![\w:])mojom::", "content::mojom::", type_text)


def argument(param_type, param_name):
    # Values that may be move-only (smart pointers, callbacks, containers) are moved. References, pointers and
    # scalars pass as they are.
    by_value = not param_type.endswith(("&", "*"))
    if by_value and ("<" in param_type or "Callback" in param_type or param_type.endswith("Ptr")):
        return f"std::move({param_name})"
    return param_name


def main():
    if not HEADER.exists():
        sys.exit(f"{HEADER} not found; set CHROMIUM_SRC")
    methods = []
    for statement in declarations(class_body(HEADER.read_text())):
        return_type, name, params, is_const = parse(statement)
        methods.append((qualify(return_type), name, [(qualify(t), n) for t, n in params], is_const))
    version = (ROOT / "chromium/VERSION").read_text().strip()
    notice = (
        "// Copyright 2026 The Oa Authors\n"
        "// Use of this source code is governed by the license in the LICENSE file.\n\n"
        "// Generated by scripts/generate_forwarding_delegate.py from\n"
        f"// content/public/browser/web_contents_delegate.h at Chromium {version}.\n"
        "// Don't edit by hand; rerun the script after a Chromium update.\n"
    )
    declarations_text = []
    definitions_text = []
    for return_type, name, params, is_const in methods:
        signature_params = ", ".join(f"{t} {n}" for t, n in params)
        const = " const" if is_const else ""
        declarations_text.append(f"  {return_type} {name}({signature_params}){const} override;")
        arguments = ", ".join(argument(t, n) for t, n in params)
        returns = "" if return_type == "void" else "return "
        definitions_text.append(
            f"{return_type} ForwardingWebContentsDelegate::{name}({signature_params}){const} {{\n"
            f"  if (inner_) {{\n"
            f"    {returns}inner_->{name}({arguments});\n"
            + ("    return;\n" if return_type == "void" else "")
            + "  }\n"
            f"  {returns}content::WebContentsDelegate::{name}({arguments});\n"
            "}\n"
        )
    header = (
        notice
        + "\n#ifndef OA_BROWSER_FORWARDING_WEB_CONTENTS_DELEGATE_H_\n"
        "#define OA_BROWSER_FORWARDING_WEB_CONTENTS_DELEGATE_H_\n\n"
        "#include \"base/memory/raw_ptr.h\"\n"
        "#include \"content/public/browser/web_contents_delegate.h\"\n\n"
        "namespace oa {\n\n"
        "// A WebContentsDelegate that passes every call to `inner`, or to content's\n"
        "// default when `inner` is null. Subclasses override what they decide\n"
        "// themselves and call the base for the rest.\n"
        "class ForwardingWebContentsDelegate : public content::WebContentsDelegate {\n"
        " public:\n"
        "  ForwardingWebContentsDelegate();\n"
        "  ForwardingWebContentsDelegate(const ForwardingWebContentsDelegate&) = delete;\n"
        "  ForwardingWebContentsDelegate& operator=(\n"
        "      const ForwardingWebContentsDelegate&) = delete;\n"
        "  ~ForwardingWebContentsDelegate() override;\n\n"
        "  content::WebContentsDelegate* inner() const { return inner_; }\n"
        "  void set_inner(content::WebContentsDelegate* inner) { inner_ = inner; }\n\n"
        "  // content::WebContentsDelegate:\n"
        + "\n".join(declarations_text)
        + "\n\n private:\n"
        "  raw_ptr<content::WebContentsDelegate> inner_ = nullptr;\n"
        "};\n\n"
        "}  // namespace oa\n\n"
        "#endif  // OA_BROWSER_FORWARDING_WEB_CONTENTS_DELEGATE_H_\n"
    )
    source = (
        notice
        + "\n#include \"oa/browser/forwarding_web_contents_delegate.h\"\n\n"
        "#include <utility>\n\n"
        "// The parameter and return types of every method.\n"
        "#include \"content/public/browser/audio_stream_broker.h\"\n"
        "#include \"content/public/browser/color_chooser.h\"\n"
        "#include \"content/public/browser/eye_dropper.h\"\n"
        "#include \"content/public/browser/file_select_listener.h\"\n"
        "#include \"content/public/browser/javascript_dialog_manager.h\"\n"
        "#include \"content/public/browser/keyboard_event_processing_result.h\"\n"
        "#include \"content/public/browser/media_stream_request.h\"\n"
        "#include \"content/public/browser/render_frame_host.h\"\n"
        "#include \"content/public/browser/render_widget_host.h\"\n"
        "#include \"content/public/browser/web_contents.h\"\n\n"
        "namespace oa {\n\n"
        "ForwardingWebContentsDelegate::ForwardingWebContentsDelegate() = default;\n\n"
        "ForwardingWebContentsDelegate::~ForwardingWebContentsDelegate() = default;\n\n"
        + "\n".join(definitions_text)
        + "\n}  // namespace oa\n"
    )
    OUT_H.write_text(header)
    OUT_MM.write_text(source)
    # Chromium's own formatter and style, from the checkout.
    clang_format = CHROMIUM_SRC / "buildtools/mac_arm64-format/clang-format"
    subprocess.run([str(clang_format), "-i", "--style=file:" + str(CHROMIUM_SRC / ".clang-format"), str(OUT_H),
                    str(OUT_MM)], check=True)
    print(f"{len(methods)} methods -> {OUT_H.relative_to(ROOT)}, {OUT_MM.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
