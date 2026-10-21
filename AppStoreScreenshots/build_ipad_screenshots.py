#!/usr/bin/env python3
"""Build Wireless's 13-inch iPad App Store marketing screenshots."""

from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
OUTPUT_ROOT = ROOT / "iPadOS-1.0"
OUTPUT = OUTPUT_ROOT / "13-inch"
BACKGROUND = ROOT / "wireless-marketing-background-v3.png"
APP_ICON = ROOT.parent / "Artwork" / "Wireless-AppIcon-Light.png"
SIZE = (2064, 2752)
FONT = "/System/Library/Fonts/SFNS.ttf"

ASSETS = [
    ("01-australian-radio-all-in-one-app.png", Path("/Users/kevinperry/Downloads/IMG_9895.PNG"), "Australian radio.\nAll in one app."),
    ("02-live-sport-perfectly-in-sync.png", Path("/Users/kevinperry/Downloads/IMG_9893.PNG"), "Live sport.\nPerfectly in sync."),
    ("03-every-city-every-region.png", Path("/Users/kevinperry/Downloads/IMG_9896.PNG"), "Every city.\nEvery region."),
    ("04-live-radio-made-for-australia.png", Path("/Users/kevinperry/Downloads/IMG_9897.PNG"), "Live radio.\nMade for Australia."),
    ("05-your-stations-always-close.png", Path("/Users/kevinperry/Downloads/IMG_9894.PNG"), "Your stations.\nAlways close."),
    ("06-find-your-kind-of-music.png", Path("/Users/kevinperry/Downloads/IMG_9898.PNG"), "Find your kind\nof music."),
    ("07-drift-off-well-fade-out.png", Path("/Users/kevinperry/Downloads/Screenshot 2026-10-18 at 5.20.28 pm.png"), "Drift off.\nWe’ll fade out."),
]


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT, size=size)


def fit_background() -> Image.Image:
    source = Image.open(BACKGROUND).convert("RGB")
    scale = max(SIZE[0] / source.width, SIZE[1] / source.height)
    resized = source.resize((round(source.width * scale), round(source.height * scale)), Image.Resampling.LANCZOS)
    x = (resized.width - SIZE[0]) // 2
    y = (resized.height - SIZE[1]) // 2
    return resized.crop((x, y, x + SIZE[0], y + SIZE[1])).convert("RGBA")


def centred_text(draw: ImageDraw.ImageDraw, text: str, y: int, face: ImageFont.FreeTypeFont, fill: tuple[int, int, int, int], spacing: int) -> None:
    for line in text.split("\n"):
        box = draw.textbbox((0, 0), line, font=face, stroke_width=2)
        draw.text(((SIZE[0] - (box[2] - box[0])) / 2, y), line, font=face, fill=fill, stroke_width=2)
        y += spacing


def framed_screen(path: Path, target_width: int = 1440) -> Image.Image:
    source = Image.open(path).convert("RGB")
    target_height = round(source.height * target_width / source.width)
    screen = source.resize((target_width, target_height), Image.Resampling.LANCZOS)
    bezel = 22
    frame = Image.new("RGBA", (target_width + bezel * 2, target_height + bezel * 2), (5, 5, 7, 255))
    frame.alpha_composite(screen.convert("RGBA"), (bezel, bezel))
    mask = Image.new("L", frame.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, frame.width - 1, frame.height - 1), radius=92, fill=255)
    frame.putalpha(mask)
    return frame


def add_header(canvas: Image.Image, headline: str) -> None:
    draw = ImageDraw.Draw(canvas)
    brand_face = font(42)
    headline_face = font(158)
    brand = "WIRELESS"
    box = draw.textbbox((0, 0), brand, font=brand_face)
    draw.text(((SIZE[0] - (box[2] - box[0])) / 2, 62), brand, font=brand_face, fill=(238, 54, 43, 255), stroke_width=1)
    centred_text(draw, headline, 130, headline_face, (43, 42, 40, 255), 164)

    divider_y = 490
    for x in range(610):
        fraction = x / 609
        colour = (238, round(54 + 50 * fraction), round(43 + 45 * fraction), 255)
        draw.line(((SIZE[0] - 610) // 2 + x, divider_y, (SIZE[0] - 610) // 2 + x, divider_y + 7), fill=colour)


def build(filename: str, screenshot: Path, headline: str) -> None:
    canvas = fit_background()
    add_header(canvas, headline)
    screen = framed_screen(screenshot)
    x = (SIZE[0] - screen.width) // 2
    y = 590

    shadow_alpha = screen.getchannel("A").filter(ImageFilter.GaussianBlur(55))
    shadow = Image.new("RGBA", screen.size, (24, 28, 58, 150))
    shadow.putalpha(shadow_alpha)
    canvas.alpha_composite(shadow, (x + 18, y + 42))
    canvas.alpha_composite(screen, (x, y))
    OUTPUT.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(OUTPUT / filename, "PNG", optimize=True)


def build_cover() -> None:
    canvas = fit_background()
    draw = ImageDraw.Draw(canvas)
    brand_face = font(48)
    headline_face = font(174)
    brand = "WIRELESS"
    box = draw.textbbox((0, 0), brand, font=brand_face)
    draw.text(((SIZE[0] - (box[2] - box[0])) / 2, 78), brand, font=brand_face, fill=(238, 54, 43, 255), stroke_width=1)
    centred_text(draw, "Australia’s radio.\nOne beautiful app.", 190, headline_face, (43, 42, 40, 255), 182)

    icon_size = 900
    icon = Image.open(APP_ICON).convert("RGB").resize((icon_size, icon_size), Image.Resampling.LANCZOS).convert("RGBA")
    mask = Image.new("L", icon.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, icon_size - 1, icon_size - 1), radius=178, fill=255)
    icon.putalpha(mask)
    x = (SIZE[0] - icon_size) // 2
    y = 690
    shadow_mask = mask.filter(ImageFilter.GaussianBlur(62))
    shadow = Image.new("RGBA", icon.size, (113, 45, 35, 160))
    shadow.putalpha(shadow_mask)
    canvas.alpha_composite(shadow, (x + 15, y + 42))
    canvas.alpha_composite(icon, (x, y))

    promise_face = font(72)
    promise = "RADIO  •  MUSIC  •  LIVE SPORT"
    box = draw.textbbox((0, 0), promise, font=promise_face)
    draw.text(((SIZE[0] - (box[2] - box[0])) / 2, 1770), promise, font=promise_face, fill=(43, 42, 40, 255), stroke_width=1)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(OUTPUT / "00-wireless-australias-radio.png", "PNG", optimize=True)


def main() -> None:
    build_cover()
    for asset in ASSETS:
        build(*asset)

    names = ["00-wireless-australias-radio.png"] + [asset[0] for asset in ASSETS]
    previews = [Image.open(OUTPUT / name).resize((258, 344), Image.Resampling.LANCZOS) for name in names]
    sheet = Image.new("RGB", (258 * 4, 344 * 2), (18, 15, 24))
    for index, preview in enumerate(previews):
        sheet.paste(preview, ((index % 4) * 258, (index // 4) * 344))
    sheet.save(OUTPUT_ROOT / "wireless-ipad-app-store-contact-sheet.jpg", "JPEG", quality=94)

    archive = OUTPUT_ROOT / "Wireless-iPad-13-inch-App-Store-Screenshots-1.0.zip"
    with ZipFile(archive, "w", ZIP_DEFLATED) as bundle:
        for name in names:
            bundle.write(OUTPUT / name, arcname=name)
    print(f"Built {len(names)} screenshots in {OUTPUT}")


if __name__ == "__main__":
    main()
