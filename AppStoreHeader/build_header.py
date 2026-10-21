#!/usr/bin/env python3
"""Build the Wireless App Store product-page header."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
BACKGROUND = ROOT / "wireless-header-background.png"
APP_ICON = ROOT.parent / "Artwork" / "Wireless-AppIcon-Light.png"
OUTPUT = ROOT / "Wireless-App-Store-Header-3840x1646.png"
PREVIEW = ROOT / "Wireless-App-Store-Header-preview.jpg"
SEARCH_OUTPUT = ROOT / "Wireless-App-Store-Search-Results-3840x2560.png"
SEARCH_PREVIEW = ROOT / "Wireless-App-Store-Search-Results-preview.jpg"
SIZE = (3840, 1646)
SEARCH_SIZE = (3840, 2560)
FONT = "/System/Library/Fonts/SFNS.ttf"


def cover(source: Image.Image, size: tuple[int, int]) -> Image.Image:
    scale = max(size[0] / source.width, size[1] / source.height)
    resized = source.resize(
        (round(source.width * scale), round(source.height * scale)),
        Image.Resampling.LANCZOS,
    )
    left = (resized.width - size[0]) // 2
    top = (resized.height - size[1]) // 2
    return resized.crop((left, top, left + size[0], top + size[1]))


def add_icon(canvas: Image.Image, icon_size: int, centre_y: int) -> None:
    radius = round(icon_size * 0.228)
    icon = Image.open(APP_ICON).convert("RGB").resize(
        (icon_size, icon_size), Image.Resampling.LANCZOS
    ).convert("RGBA")
    icon_mask = Image.new("L", icon.size, 0)
    ImageDraw.Draw(icon_mask).rounded_rectangle(
        (0, 0, icon_size - 1, icon_size - 1), radius=radius, fill=255
    )
    icon.putalpha(icon_mask)

    shadow_size = icon_size + 260
    shadow_mask = Image.new("L", (shadow_size, shadow_size), 0)
    ImageDraw.Draw(shadow_mask).rounded_rectangle(
        (130, 130, 130 + icon_size, 130 + icon_size),
        radius=radius,
        fill=170,
    )
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(90))
    shadow = Image.new("RGBA", shadow_mask.size, (93, 39, 30, 0))
    shadow.putalpha(shadow_mask)

    x = (canvas.width - icon_size) // 2
    y = centre_y - icon_size // 2
    canvas.alpha_composite(shadow, (x - 130, y - 105))
    canvas.alpha_composite(icon, (x, y))


def build_header() -> None:
    canvas = cover(Image.open(BACKGROUND).convert("RGB"), SIZE).convert("RGBA")
    # Keep the only focal element centred so it survives App Store crops.
    add_icon(canvas, icon_size=900, centre_y=SIZE[1] // 2)

    canvas.convert("RGB").save(OUTPUT, "PNG", optimize=True)
    canvas.convert("RGB").resize((1920, 823), Image.Resampling.LANCZOS).save(
        PREVIEW, "JPEG", quality=92
    )
    print(OUTPUT)


def build_search_results() -> None:
    canvas = cover(Image.open(BACKGROUND).convert("RGB"), SEARCH_SIZE).convert("RGBA")
    add_icon(canvas, icon_size=1160, centre_y=1030)

    # One short, highly legible phrase makes the app's purpose obvious in Search.
    draw = ImageDraw.Draw(canvas)
    face = ImageFont.truetype(FONT, size=190)
    text = "LIVE AUSTRALIAN RADIO"
    box = draw.textbbox((0, 0), text, font=face, stroke_width=2)
    width = box[2] - box[0]
    draw.text(
        ((SEARCH_SIZE[0] - width) / 2, 1780),
        text,
        font=face,
        fill=(43, 42, 40, 255),
        stroke_width=2,
    )

    canvas.convert("RGB").save(SEARCH_OUTPUT, "PNG", optimize=True)
    canvas.convert("RGB").resize((960, 640), Image.Resampling.LANCZOS).save(
        SEARCH_PREVIEW, "JPEG", quality=92
    )
    print(SEARCH_OUTPUT)


def main() -> None:
    build_header()
    build_search_results()


if __name__ == "__main__":
    main()
