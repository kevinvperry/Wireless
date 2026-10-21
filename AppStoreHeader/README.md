# Wireless App Store product-page header

Submission-ready static Header and Search Results assets designed to Apple's current creative-asset guidance.

- Dimensions: 3840 × 1646 pixels
- Aspect ratio: 21:9
- Format: opaque PNG
- Focal point: centred within the composition to tolerate responsive cropping
- Concept: one clear idea — the Wireless light icon broadcasting across a warm ivory field
- Text: none, avoiding duplication of the adjacent App Store product metadata and localisation requirements

## Search Results asset

- File: `Wireless-App-Store-Search-Results-3840x2560.png`
- Dimensions: 3840 × 2560 pixels
- Aspect ratio: 3:2
- Format: opaque PNG
- Composition: recomposed for the taller Search Results frame rather than stretching the Header
- Message: one large, localisable phrase — “LIVE AUSTRALIAN RADIO”

The genuine `Artwork/Wireless-AppIcon-Light.png` is composited deterministically over a generated background. Run:

```sh
python3 AppStoreHeader/build_header.py
```

## Background-generation prompt

Built-in image generation was used with this final prompt:

> Create a premium ultra-wide brand backdrop matching the Wireless primary light app icon. Use a warm ivory and soft cream field with elegant concentric broadcast-wave arcs radiating symmetrically from the exact centre, using Wireless signal red, soft coral and restrained charcoal accents. Keep one calm, unobstructed central focal zone for the genuine app icon, and keep important visual energy in the central 70 percent. Use polished contemporary Apple App Store editorial styling. Background only: no icon, app interface, text, letters, logos, device, people, flags, maps, landmarks, magenta, purple, blue, green, border, transparency or watermark.
