#!/usr/bin/env python3
"""Build Wireless's 6.9-inch iPhone App Store marketing screenshots."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "iOS-4.0" / "6.9-inch"
BACKGROUND = ROOT / "wireless-marketing-background-v3.png"
APP_ICON = ROOT.parent / "Artwork" / "Wireless-AppIcon-Light.png"
SIZE = (1290, 2796)

FONT_REGULAR = "/System/Library/Fonts/SFNS.ttf"
FONT_BOLD = "/System/Library/Fonts/SFNS.ttf"


ASSETS = [
    (
        "01-australian-radio-all-in-one-app.png",
        Path("/Users/kevinperry/Downloads/IMG_9895.PNG"),
        "Australian radio.\nAll in one app.",
        "ABC, commercial, community and regional stations from across the country.",
    ),
    (
        "02-live-sport-perfectly-in-sync.png",
        Path("/Users/kevinperry/Downloads/IMG_9893.PNG"),
        "Live sport.\nPerfectly in sync.",
        "Match radio commentary with the action on your TV.",
    ),
    (
        "03-every-city-every-region.png",
        Path("/Users/kevinperry/Downloads/IMG_9896.PNG"),
        "Every city.\nEvery region.",
        "Explore national, metropolitan and regional Australian radio.",
    ),
    (
        "04-live-radio-made-for-australia.png",
        Path("/Users/kevinperry/Downloads/IMG_9897.PNG"),
        "Live radio.\nMade for Australia.",
        "See stations, song details and controls in one focused player.",
    ),
    (
        "05-your-stations-always-close.png",
        Path("/Users/kevinperry/Downloads/IMG_9894.PNG"),
        "Your stations.\nAlways close.",
        "Save, reorder and switch between favourites in seconds.",
    ),
    (
        "06-find-your-kind-of-music.png",
        Path("/Users/kevinperry/Downloads/IMG_9898.PNG"),
        "Find your kind\nof music.",
        "Browse live Australian stations by genre and mood.",
    ),
    (
        "07-drift-off-well-fade-out.png",
        Path("/Users/kevinperry/Downloads/Screenshot 2026-10-18 at 5.20.28 pm.png"),
        "Drift off.\nWe’ll fade out.",
        "Set your listening hours once. Wireless handles every night.",
    ),
]


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REGULAR, size=size)


def fit_background() -> Image.Image:
    source = Image.open(BACKGROUND).convert("RGB")
    scale = max(SIZE[0] / source.width, SIZE[1] / source.height)
    resized = source.resize((round(source.width * scale), round(source.height * scale)), Image.Resampling.LANCZOS)
    x = (resized.width - SIZE[0]) // 2
    y = (resized.height - SIZE[1]) // 2
    return resized.crop((x, y, x + SIZE[0], y + SIZE[1]))


def wrap(draw: ImageDraw.ImageDraw, text: str, face: ImageFont.FreeTypeFont, max_width: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if draw.textbbox((0, 0), candidate, font=face)[2] <= max_width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def rounded_screenshot(path: Path, target_width: int = 1050) -> Image.Image:
    screenshot = Image.open(path).convert("RGB")
    height = round(screenshot.height * target_width / screenshot.width)
    screenshot = screenshot.resize((target_width, height), Image.Resampling.LANCZOS)

    bezel = 18
    framed = Image.new("RGBA", (target_width + bezel * 2, height + bezel * 2), (5, 5, 7, 255))
    framed.alpha_composite(screenshot.convert("RGBA"), (bezel, bezel))
    mask = Image.new("L", framed.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, framed.width - 1, framed.height - 1), radius=78, fill=255)
    framed.putalpha(mask)
    return framed


def build(filename: str, screenshot: Path, headline: str, subtitle: str) -> None:
    canvas = fit_background().convert("RGBA")
    overlay = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    brand_face = font(32, bold=True)
    headline_face = font(132, bold=True)

    brand = "WIRELESS"
    brand_box = draw.textbbox((0, 0), brand, font=brand_face)
    draw.text(((SIZE[0] - (brand_box[2] - brand_box[0])) / 2, 58), brand, font=brand_face, fill=(238, 54, 43, 255), stroke_width=1)

    y = 118
    for line in headline.split("\n"):
        box = draw.textbbox((0, 0), line, font=headline_face)
        draw.text(((SIZE[0] - (box[2] - box[0])) / 2, y), line, font=headline_face, fill=(43, 42, 40, 255), stroke_width=2)
        y += 138

    divider_y = 430
    divider = Image.new("RGBA", (420, 6), (0, 0, 0, 0))
    divider_draw = ImageDraw.Draw(divider)
    for x in range(divider.width):
        fraction = x / max(1, divider.width - 1)
        colour = (
            238,
            round(54 * (1 - fraction) + 104 * fraction),
            round(43 * (1 - fraction) + 88 * fraction),
            255,
        )
        divider_draw.line((x, 0, x, divider.height), fill=colour)
    overlay.alpha_composite(divider, ((SIZE[0] - divider.width) // 2, divider_y))
    canvas = Image.alpha_composite(canvas, overlay)

    phone = rounded_screenshot(screenshot)
    shadow = Image.new("RGBA", phone.size, (0, 0, 0, 0))
    shadow.putalpha(phone.getchannel("A").filter(ImageFilter.GaussianBlur(42)))
    shadow_colour = Image.new("RGBA", phone.size, (20, 24, 55, 135))
    shadow_colour.putalpha(shadow.getchannel("A"))

    x = (SIZE[0] - phone.width) // 2
    y = 525
    canvas.alpha_composite(shadow_colour, (x + 12, y + 34))
    canvas.alpha_composite(phone, (x, y))

    OUTPUT.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(OUTPUT / filename, "PNG", optimize=True)


def build_cover() -> None:
    canvas = fit_background().convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    brand_face = font(42, bold=True)
    headline_face = font(140, bold=True)

    brand = "WIRELESS"
    box = draw.textbbox((0, 0), brand, font=brand_face)
    draw.text(((SIZE[0] - (box[2] - box[0])) / 2, 82), brand, font=brand_face, fill=(238, 54, 43, 255), stroke_width=1)

    y = 180
    for line in ("Australia’s radio.", "One beautiful app."):
        box = draw.textbbox((0, 0), line, font=headline_face)
        draw.text(((SIZE[0] - (box[2] - box[0])) / 2, y), line, font=headline_face, fill=(43, 42, 40, 255), stroke_width=2)
        y += 150

    icon_size = 760
    icon = Image.open(APP_ICON).convert("RGB").resize((icon_size, icon_size), Image.Resampling.LANCZOS)
    mask = Image.new("L", (icon_size, icon_size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, icon_size - 1, icon_size - 1), radius=145, fill=255)
    icon = icon.convert("RGBA")
    icon.putalpha(mask)
    shadow = Image.new("RGBA", (icon_size + 140, icon_size + 140), (0, 0, 0, 0))
    shadow_mask = Image.new("L", shadow.size, 0)
    ImageDraw.Draw(shadow_mask).rounded_rectangle((70, 70, 70 + icon_size, 70 + icon_size), radius=145, fill=155)
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(55))
    shadow_colour = Image.new("RGBA", shadow.size, (113, 45, 35, 0))
    shadow_colour.putalpha(shadow_mask)

    x = (SIZE[0] - icon_size) // 2
    y = 620
    canvas.alpha_composite(shadow_colour, (x - 70, y - 45))
    canvas.alpha_composite(icon, (x, y))

    promise_face = font(58, bold=True)
    promise = "RADIO  •  MUSIC  •  LIVE SPORT"
    box = draw.textbbox((0, 0), promise, font=promise_face)
    draw.text(((SIZE[0] - (box[2] - box[0])) / 2, 1515), promise, font=promise_face, fill=(43, 42, 40, 255), stroke_width=1)

    OUTPUT.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(OUTPUT / "00-wireless-australias-radio.png", "PNG", optimize=True)


def main() -> None:
    if not BACKGROUND.exists():
        raise SystemExit(f"Missing background: {BACKGROUND}")
    build_cover()
    for asset in ASSETS:
        build(*asset)
    output_names = ["00-wireless-australias-radio.png"] + [asset[0] for asset in ASSETS]
    previews = [Image.open(OUTPUT / name).resize((258, 559), Image.Resampling.LANCZOS) for name in output_names]
    contact_sheet = Image.new("RGB", (258 * 4, 559 * 2), (18, 15, 24))
    for index, preview in enumerate(previews):
        contact_sheet.paste(preview, ((index % 4) * 258, (index // 4) * 559))
    contact_sheet.save(OUTPUT.parent / "wireless-app-store-contact-sheet.jpg", "JPEG", quality=92)
    print(f"Built {len(output_names)} screenshots in {OUTPUT}")


if __name__ == "__main__":
    main()
