# Wireless iPhone App Store screenshots

Seven opaque PNG marketing screenshots for the iPhone Dynamic Island large-display slot.

- Output size: 1290 × 2796 pixels
- Source UI: the seven supplied Wireless screenshots, preserved as exact screenshot imagery
- Style reference: Autohop's current iPhone App Store screenshot system
- Composition: small Wireless label, bold benefit headline, concise supporting copy, gradient divider and a floating screenshot over a dark purple, magenta and teal background

## Sequence

1. Live radio. Beautifully focused.
2. Australia’s radio. All in one place.
3. Local stations. Wherever you are.
4. Find the sound you love.
5. Your favourites. Always close.
6. Match radio with your TV.
7. Drift off. We’ll fade out.

## Generation

The reusable abstract background was created using the built-in image-generation tool with this prompt:

> Create only an abstract premium dark portrait App Store background, with no phone, app interface, logos or text. Use a near-black and deep-plum base with translucent flowing ribbons and soft light blooms in electric magenta, violet and subtle teal. Keep the upper centre calm and dark for white copy, with brighter aurora accents along the edges and lower half. Make it modern, sophisticated and high contrast, without watermarks or legible objects.

`build_ios_screenshots.py` performs deterministic typography, screenshot framing, compositing and export. Run it from the repository root with:

```sh
python3 AppStoreScreenshots/build_ios_screenshots.py
```

The source screenshot paths currently point to the supplied files in `~/Downloads`.
