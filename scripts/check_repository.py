#!/usr/bin/env python3
"""Quick checks that need no Swift compiler. Run by the GitHub workflows before building.

What it checks (and what it does NOT):
- required files and folders exist
- every Swift file has balanced braces, brackets and parentheses
- the effect catalogue lists exactly the names in the required list used by the tests
- project.yml mentions the pieces the build needs
It does NOT prove the code compiles. Only the build does.
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
problems = []


def fail(message):
    problems.append(message)


def strip_swift(source):
    """Remove comments and string contents so braces inside them are not counted."""
    out, i, n = [], 0, len(source)
    while i < n:
        if source.startswith("//", i):
            while i < n and source[i] != "\n":
                i += 1
        elif source.startswith("/*", i):
            j = source.find("*/", i + 2)
            i = n if j < 0 else j + 2
        elif source.startswith('#"', i):
            j = source.find('"#', i + 2)
            i = n if j < 0 else j + 2
        elif source[i] == '"':
            i += 1
            while i < n and source[i] != '"':
                i += 2 if source[i] == "\\" else 1
            i += 1
        else:
            out.append(source[i])
            i += 1
    return "".join(out)


required = [
    "project.yml", "LICENSE", "README.md", "MotionCore/Package.swift",
    ".github/workflows/core-tests.yml", ".github/workflows/ios-build.yml",
    "docs/BUILD-AND-INSTALL.md", "docs/ARCHITECTURE.md", "docs/DECISIONS.md", "docs/ROADMAP.md",
    "docs/FEATURE-STATUS.md", "docs/EFFECTS-CATALOG.md", "docs/GRAPH-EDITOR.md",
    "docs/RENDERING-AND-EXPORT.md", "docs/PLUGIN-COMPATIBILITY.md", "docs/MEDIA-AND-EFFECTS.md",
]
for path in required:
    if not os.path.exists(os.path.join(ROOT, path)):
        fail(f"missing file: {path}")

swift_files = glob.glob(os.path.join(ROOT, "**", "*.swift"), recursive=True)
for path in swift_files:
    text = strip_swift(open(path, encoding="utf-8").read())
    for opener, closer in ("{}", "()", "[]"):
        if text.count(opener) != text.count(closer):
            fail(f"unbalanced {opener}{closer} in {os.path.relpath(path, ROOT)}")

catalog = os.path.join(ROOT, "MotionCore/Sources/MotionCore/Effects/EffectCatalogData.swift")
required_names = os.path.join(ROOT, "MotionCore/Tests/MotionCoreTests/RequiredEffectNames.swift")
if os.path.exists(catalog) and os.path.exists(required_names):
    in_catalog = re.findall(r'^\s*\("(.+)", \.\w+\),\s*$', open(catalog, encoding="utf-8").read(), re.M)
    in_required = re.findall(r'^\s*"(.+)",\s*$', open(required_names, encoding="utf-8").read(), re.M)
    missing_names = sorted(set(in_required) - set(in_catalog))
    if missing_names:
        fail(f"effects required but not in the catalogue: {missing_names}")
    extras = sorted(set(in_catalog) - set(in_required))
    if extras != ["Black & White", "Chromatic Aberration", "Drop Shadow", "Film Grain", "Liquid Glass", "Luma Fade", "Motion Tile", "Optical Flow Slow Motion", "Pixel Sort", "RGB Blur", "Radial Blur", "Scanlines", "Sepia Tone", "Solarize", "Tint", "VHS"]:
        fail(f"unexpected extra effects in the catalogue: {extras}")
    if len(set(in_catalog)) != len(in_catalog):
        fail("duplicate effect names in the catalogue")
    print(f"effect catalogue: {len(in_catalog)} names")

yml = open(os.path.join(ROOT, "project.yml"), encoding="utf-8").read()
for needle in ("MotionStudio:", "MotionCore", "UILaunchScreen", "iOS: \"17.0\"", "TARGETED_DEVICE_FAMILY"):
    if needle not in yml:
        fail(f"project.yml does not mention {needle}")

print(f"swift files checked: {len(swift_files)}")
if problems:
    print("PROBLEMS:")
    for p in problems:
        print(" -", p)
    sys.exit(1)
print("repository checks passed (this is NOT a compile check)")
