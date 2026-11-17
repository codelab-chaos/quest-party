#!/usr/bin/env python3
"""Feed card scenes: the artist's template and the game's atlas.

The scene list, the atlas shape and each scene's brief live in
QuestParty/data/scenes.lua; this reads them from there.

    scripts/scenes.py template   art/scenes/template.svg (labelled guide) and
                                 art/scenes/template.png (the same guide, no
                                 text, the atlas' exact size, to paint over)
    scripts/scenes.py build      art/scenes/<id>.png for each scene, any size
                                 (cropped about the middle to the cell's
                                 shape), into QuestParty/media/scenes.tga;
                                 a scene with no art yet gets a placeholder
                                 in its tint

No libraries beyond Python's own: PNG is read and written here, TGA written.
"""
import argparse
import re
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "QuestParty/data/scenes.lua"
ART = ROOT / "art/scenes"
ATLAS = ROOT / "QuestParty/media/scenes.tga"

# Where things sit on a card, in a cell's own pixels (a 512 x 64 cell shows a
# feed row about 360 wide, so 1.42 cell pixels to a row pixel). From
# ui/panel.lua: the icon at the left, the time or count at the right
# (RIGHT_TEXT_WIDTH), the title and details between.
ZONES = {
    "icon": (0, 56),  # keep it plain: the event's icon sits here
    "right": (421, 512),  # the time or count: the place for the scene's focus
}
# How much of a cell a card shows (cropped about the middle): a one-line row
# (about 18 to 1) shows a band, a two-line card (about 6 to 1) loses its sides.
BANDS = {
    "one line": 28,  # rows in the one-line view
    "detailed": 54,  # most cards
}
TEXT_MAX_LIGHT = 0.35  # the text zone's average brightness, at most, for white text to read


# ========= The data ========================================================
def read_scenes(path=DATA):
    text = path.read_text()
    atlas = {}
    for key in ("width", "height", "columns", "cellWidth", "cellHeight"):
        match = re.search(rf"\b{key} = (\d+)", text)
        if not match:
            raise ValueError(f"{path.name}: SceneAtlas has no {key}")
        atlas[key] = int(match.group(1))
    scenes = []
    pattern = re.compile(
        r'\{ id = "(\w+)", name = "([^"]+)", tint = \{ ([\d.]+), ([\d.]+), ([\d.]+) \}, brief = "([^"]*)" \}'
    )
    for match in pattern.finditer(text):
        scenes.append({
            "id": match.group(1),
            "name": match.group(2),
            "tint": tuple(float(match.group(i)) for i in (3, 4, 5)),
            "brief": match.group(6),
        })
    cells = (atlas["width"] // atlas["cellWidth"]) * (atlas["height"] // atlas["cellHeight"])
    if not scenes or len(scenes) > cells:
        raise ValueError(f"{path.name}: {len(scenes)} scenes for {cells} cells")
    return atlas, scenes


def cell_origin(atlas, index):
    """Top left of scene number index (from 0), in atlas pixels."""
    return (index % atlas["columns"]) * atlas["cellWidth"], (index // atlas["columns"]) * atlas["cellHeight"]


# ========= Images: rows of (r, g, b, a) bytes ==============================
class Image:
    def __init__(self, width, height, fill=(0, 0, 0, 0)):
        self.width, self.height = width, height
        self.pixels = [list(fill) * width for _ in range(height)]

    def get(self, x, y):
        row = self.pixels[y]
        return tuple(row[x * 4:x * 4 + 4])

    def set(self, x, y, color):
        self.pixels[y][x * 4:x * 4 + 4] = [max(0, min(255, int(c))) for c in color]

    def blend(self, x, y, color, alpha):
        if 0 <= x < self.width and 0 <= y < self.height:
            under = self.get(x, y)
            self.set(x, y, [under[i] + (color[i] - under[i]) * alpha for i in range(3)] + [max(under[3], 255 * alpha)])

    def rect(self, left, top, right, bottom, color, alpha=1.0):
        for y in range(max(0, top), min(self.height, bottom)):
            for x in range(max(0, left), min(self.width, right)):
                self.blend(x, y, color, alpha)

    def outline(self, left, top, right, bottom, color, alpha=1.0, dash=0):
        for x in range(left, right):
            if not dash or (x // dash) % 2 == 0:
                self.blend(x, top, color, alpha)
                self.blend(x, bottom - 1, color, alpha)
        for y in range(top, bottom):
            if not dash or (y // dash) % 2 == 0:
                self.blend(left, y, color, alpha)
                self.blend(right - 1, y, color, alpha)

    def paste(self, other, left, top):
        for y in range(other.height):
            self.pixels[top + y][left * 4:(left + other.width) * 4] = other.pixels[y]


def read_png(path):
    data = Path(path).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")
    offset, chunks, header = 8, [], None
    while offset < len(data):
        length, kind = struct.unpack(">I4s", data[offset:offset + 8])
        body = data[offset + 8:offset + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            chunks.append(body)
        offset += 12 + length
    width, height, depth, color, _, _, interlace = header
    channels = {2: 3, 6: 4, 0: 1, 4: 2}.get(color)
    if depth != 8 or channels is None or interlace:
        raise ValueError(f"{path}: save it as an 8-bit RGB or RGBA PNG, not interlaced")
    raw = zlib.decompress(b"".join(chunks))
    stride = width * channels
    image = Image(width, height)
    previous = bytearray(stride)
    position = 0
    for y in range(height):
        kind = raw[position]
        line = bytearray(raw[position + 1:position + 1 + stride])
        position += 1 + stride
        for i in range(stride):
            left = line[i - channels] if i >= channels else 0
            up = previous[i]
            corner = previous[i - channels] if i >= channels else 0
            if kind == 1:
                line[i] = (line[i] + left) & 255
            elif kind == 2:
                line[i] = (line[i] + up) & 255
            elif kind == 3:
                line[i] = (line[i] + (left + up) // 2) & 255
            elif kind == 4:
                guess = left + up - corner
                a, b, c = abs(guess - left), abs(guess - up), abs(guess - corner)
                line[i] = (line[i] + (left if a <= b and a <= c else up if b <= c else corner)) & 255
        previous = line
        row = image.pixels[y]
        for x in range(width):
            pixel = line[x * channels:(x + 1) * channels]
            if channels == 1:
                pixel = [pixel[0]] * 3 + [255]
            elif channels == 2:
                pixel = [pixel[0]] * 3 + [pixel[1]]
            elif channels == 3:
                pixel = list(pixel) + [255]
            row[x * 4:x * 4 + 4] = pixel
    return image


def write_png(image, path):
    raw = b"".join(b"\x00" + bytes(row) for row in image.pixels)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", image.width, image.height, 8, 6, 0, 0, 0)
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def write_tga(image, path):
    """32-bit uncompressed TGA, rows from the bottom up, as the game reads it."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, image.width, image.height, 32, 8)
    body = bytearray()
    for row in reversed(image.pixels):
        for x in range(image.width):
            r, g, b, a = row[x * 4:x * 4 + 4]
            body += bytes((b, g, r, a))
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_bytes(header + bytes(body))


def cover(image, width, height):
    """The middle of image, scaled to fill width x height (box filtered)."""
    scale = max(width / image.width, height / image.height)
    shown_width, shown_height = width / scale, height / scale
    left, top = (image.width - shown_width) / 2, (image.height - shown_height) / 2
    result = Image(width, height)
    for y in range(height):
        y0 = int(top + y / scale)
        y1 = max(y0 + 1, int(top + (y + 1) / scale))
        for x in range(width):
            x0 = int(left + x / scale)
            x1 = max(x0 + 1, int(left + (x + 1) / scale))
            total, count = [0, 0, 0, 0], 0
            for sy in range(y0, min(y1, image.height)):
                row = image.pixels[sy]
                for sx in range(x0, min(x1, image.width)):
                    for i in range(4):
                        total[i] += row[sx * 4 + i]
                    count += 1
            result.set(x, y, [t / max(1, count) for t in total])
    return result


def light(image, left, right):
    """Average brightness (0 to 1) of a band of columns."""
    total, count = 0.0, 0
    for row in image.pixels:
        for x in range(left, right):
            r, g, b, _ = row[x * 4:x * 4 + 4]
            total += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
            count += 1
    return total / max(1, count)


# ========= Placeholder and guide ===========================================
def placeholder(atlas, scene):
    """Dark on the left and through the text, the scene's tint rising at the
    right where its focus would be: a fair card until the art is in."""
    width, height = atlas["cellWidth"], atlas["cellHeight"]
    image = Image(width, height)
    r, g, b = scene["tint"]
    for x in range(width):
        rise = max(0.0, (x - width * 0.45) / (width * 0.55)) ** 1.6
        strength = 0.18 + 0.62 * rise
        for y in range(height):
            shade = strength * (0.85 + 0.15 * (1 - abs(y - height / 2) / (height / 2)))
            image.set(x, y, (r * 255 * shade, g * 255 * shade, b * 255 * shade, 255))
    return image


def guide_cell(atlas, scene):
    """A placeholder with the zones and crop bands drawn on it."""
    width, height = atlas["cellWidth"], atlas["cellHeight"]
    image = placeholder(atlas, scene)
    left, right = ZONES["icon"]
    image.rect(left, 0, right, height, (220, 60, 60), 0.30)
    left, right = ZONES["right"]
    image.rect(left, 0, right, height, (240, 200, 60), 0.22)
    for name, band in BANDS.items():
        top = (height - band) // 2
        color = (120, 200, 255) if name == "one line" else (255, 255, 255)
        image.outline(0, top, width, top + band, color, 0.7, dash=4)
    image.outline(0, 0, width, height, (255, 255, 255), 0.9)
    return image


def template_png(atlas, scenes, path):
    image = Image(atlas["width"], atlas["height"], (0, 0, 0, 255))
    for index, scene in enumerate(scenes):
        image.paste(guide_cell(atlas, scene), *cell_origin(atlas, index))
    write_png(image, path)


def template_svg(atlas, scenes, path):
    scale = 1.5  # drawn a little larger than life, so the labels read
    legend = 150
    width, height = atlas["width"] * scale, atlas["height"] * scale + legend
    cw, ch = atlas["cellWidth"] * scale, atlas["cellHeight"] * scale
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width:.0f}" height="{height:.0f}" font-family="Georgia, serif">',
        f'<rect width="100%" height="100%" fill="#0b0b12"/>',
    ]
    for index, scene in enumerate(scenes):
        x, y = (v * scale for v in cell_origin(atlas, index))
        r, g, b = (int(c * 255) for c in scene["tint"])
        parts.append(f'<defs><linearGradient id="g{index}" x1="0" x2="1"><stop offset="0.45" stop-color="rgb({r*0.18:.0f},{g*0.18:.0f},{b*0.18:.0f})"/><stop offset="1" stop-color="rgb({r*0.8:.0f},{g*0.8:.0f},{b*0.8:.0f})"/></linearGradient></defs>')
        parts.append(f'<rect x="{x}" y="{y}" width="{cw}" height="{ch}" fill="url(#g{index})" stroke="#fff" stroke-opacity="0.8"/>')
        left, right = (v * scale for v in ZONES["icon"])
        parts.append(f'<rect x="{x + left}" y="{y}" width="{right - left}" height="{ch}" fill="#dc3c3c" fill-opacity="0.3"/>')
        left, right = (v * scale for v in ZONES["right"])
        parts.append(f'<rect x="{x + left}" y="{y}" width="{right - left}" height="{ch}" fill="#f0c83c" fill-opacity="0.22"/>')
        for name, band in BANDS.items():
            top = y + (atlas["cellHeight"] - band) / 2 * scale
            color = "#78c8ff" if name == "one line" else "#ffffff"
            parts.append(f'<rect x="{x}" y="{top}" width="{cw}" height="{band * scale}" fill="none" stroke="{color}" stroke-dasharray="6 6" stroke-opacity="0.7"/>')
        parts.append(f'<text x="{x + 92}" y="{y + 26}" fill="#ffd100" font-size="17">{index + 1}. {scene["name"]}  <tspan fill="#9a9a9a" font-size="13">({scene["id"]})</tspan></text>')
        parts.append(f'<text x="{x + 92}" y="{y + 48}" fill="#ffffff" font-size="12">{scene["brief"]}</text>')
        parts.append(f'<text x="{x + 92}" y="{y + 70}" fill="#bbbbbb" font-size="11">art/scenes/{scene["id"]}.png</text>')
    top = atlas["height"] * scale + 26
    notes = [
        ("#ffd100", f'Atlas {atlas["width"]} x {atlas["height"]}: {atlas["columns"]} columns of {atlas["cellWidth"]} x {atlas["cellHeight"]} cells (8 to 1, a feed row\'s shape). Paint each scene at {atlas["cellWidth"] * 3} x {atlas["cellHeight"] * 3} or larger.'),
        ("#dc3c3c", "Red: the icon sits here. Keep it plain and dark."),
        ("#ffffff", f"Middle: the title and details, white and gold text. Keep it dark and quiet (brightness under {int(TEXT_MAX_LIGHT * 100)}%)."),
        ("#f0c83c", "Gold: the time or count. Put the scene's focus here, the thing that makes it recognizable."),
        ("#78c8ff", "Dashed: what cards show (cropped about the middle). Blue, one-line rows; white, most cards. Keep the focus inside the blue band."),
    ]
    for offset, (color, line) in enumerate(notes):
        parts.append(f'<text x="16" y="{top + offset * 24}" fill="{color}" font-size="14">{line}</text>')
    parts.append("</svg>")
    Path(path).write_text("\n".join(parts) + "\n")


# ========= Commands ========================================================
def make_template(art=ART):
    atlas, scenes = read_scenes()
    art.mkdir(parents=True, exist_ok=True)
    template_svg(atlas, scenes, art / "template.svg")
    template_png(atlas, scenes, art / "template.png")
    return [art / "template.svg", art / "template.png"]


def build(art=ART, output=ATLAS):
    atlas, scenes = read_scenes()
    image = Image(atlas["width"], atlas["height"], (0, 0, 0, 255))
    report = []
    text_left, text_right = ZONES["icon"][1], ZONES["right"][0]
    for index, scene in enumerate(scenes):
        source = art / f'{scene["id"]}.png'
        if source.is_file():
            cell = cover(read_png(source), atlas["cellWidth"], atlas["cellHeight"])
            brightness = light(cell, text_left, text_right)
            note = "art"
            if brightness > TEXT_MAX_LIGHT:
                note += f", text zone too bright ({brightness:.0%}, keep it under {TEXT_MAX_LIGHT:.0%})"
        else:
            cell = placeholder(atlas, scene)
            note = "placeholder"
        image.paste(cell, *cell_origin(atlas, index))
        report.append(f'{index + 1:2}. {scene["id"]:<10} {note}')
    write_tga(image, output)
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["template", "build"])
    args = parser.parse_args(argv)
    if args.command == "template":
        for path in make_template():
            print(f"scenes: wrote {path.relative_to(ROOT)}")
    else:
        for line in build():
            print(f"scenes: {line}")
        print(f"scenes: wrote {ATLAS.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
