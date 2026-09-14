# Handoff: CopyStack app icon + menu bar template

## Overview
Visual identity for **CopyStack**, a macOS menu bar utility that stores a handful of
text snippets and pastes them into the frontmost app via a global shortcut.
Bundle id: `com.ozanalbayrak.CopyStack`.

Two assets: the app icon (Finder, Dock, Login Items, About box) and the monochrome
menu bar template glyph. The Settings window uses stock macOS controls, so these two
assets carry the whole brand.

## About the design files
Everything in this bundle is a **design reference**, authored as SVG/HTML rather than
production source. The PNGs are ready to ship as-is; the SVGs are the rebuild source.
The intended final form is a **layered Icon Composer icon** (`.icon`) in the Xcode
project — rebuild it there from the three layer groups described below, rather than
dropping the flat 1024 PNG into an `.appiconset` and calling it done.

## Fidelity
**High fidelity.** Final geometry, final colors, final gradient stops. Every number
below is authoritative and measured on a 1024 px canvas.

## The object
One front-facing "stepped stack": two translucent sheets step back behind a single
large card. The card's face carries a snippet line and a ⌘ mark. No strokes anywhere
except the ⌘ and the rim light — everything else is a filled shape. No texture, no
long shadow, no inner glow, no text.

Concepts considered and rejected: sheets fanned on a diagonal (collapses below 32 px);
a keycap pressing onto sheets (reads as a keyboard utility, not a snippet store).

## Geometry — app icon, 1024 × 1024 canvas
| Element | Spec |
| --- | --- |
| Squircle body | 824 × 824, centred (x/y 100 → 924). Superellipse `|x/a|^n + |y/a|^n = 1`, n ≈ 5.4, sampled at 288 points. Icon Composer supplies its own mask — feed it the layers, not the body. |
| Ground gradient | Vertical, userSpaceOnUse y 100 → 924. Two stops only: `#7B6BFF` → `#2E1F9E`. |
| Rim light | Squircle at half-extent 402, stroke `#FFFFFF` at 12% opacity, 10 px wide. |
| Back sheet | x 356, y 282, w 312, h 68, r 30 — `#FFFFFF` at 50%. |
| Mid sheet | x 310, y 328, w 404, h 74, r 34 — `#FFFFFF` at 82%. |
| Card | x 262, y 380, w 500, h 348, r 62 — `#F6F6FC`. |
| Card face | x 288, y 406, w 448, h 296, r 40 — `#FFFFFF`. |
| Snippet line | x 340, y 484, w 288, h 36, r 18 — `#CBCDEC`. |
| ⌘ mark | Centre (381, 588). Inner square half-side a = 21, loop radius r = 14, stroke 14 px, round joins, `#FFB020`. Overall extent 79 px. |
| Drop shadow | Two `feDropShadow` passes on the body group: dy 8 / stdDeviation 8 / black 20%, then dy 22 / stdDeviation 20 / black 10%. |

Foreground occupies 282 → 728 vertically (optical centre 505 against canvas centre 512)
and 262 → 762 horizontally, leaving 150 px of ground on each side. Minimum shape
dimension is 36 px and minimum stroke is 14 px at 1024 — nothing is thin enough to
break down when the OS downsamples.

## Layers (for Icon Composer)
The SVG is grouped exactly as the icon should be layered, back to front:
1. `#layer-background` — gradient squircle + rim light.
2. `#layer-mid` — the two translucent sheets.
3. `#layer-foreground` — card, face, snippet line, ⌘.

Export each group separately if Icon Composer needs one file per layer. Keep the
depth order; the specular/shadow treatment Icon Composer adds should be left at its
defaults — the design assumes no extra tint or glass overlay beyond that.

## Geometry — menu bar template glyph, 18 × 18 box
Three shapes, solid `#000000` on transparent. Coordinates in an 18-unit viewBox:
| Shape | Spec |
| --- | --- |
| Back bar | x 5.7, y 1.5, w 6.6, h 1.6, r 0.8 |
| Mid bar | x 4.1, y 3.9, w 9.8, h 1.6, r 0.8 |
| Card | x 2.1, y 6.4, w 13.8, h 10.1, r 2.3, with a knocked-out bar (x 4.6, y 10.2, w 6.4, h 1.9, r 0.95) via `fill-rule="evenodd"` |

Optical size: 13.8 × 15.0 inside the 18 × 18 box. Smallest feature is 1.6 px at @1×.

Implementation notes:
- Ship `copystack-menubar-18.png` and `copystack-menubar-36.png` as
  `CopyStackTemplate.png` / `CopyStackTemplate@2x.png`, or add the SVG to the asset
  catalog as a single-scale vector.
- The asset **must** be marked *Template Image* (`image.isTemplate = true` /
  "Render As: Template Image"), so macOS tints it for light, dark and the active
  highlight. Do not set a colour on the `NSStatusItem` button image.
- `statusItem.button?.image?.isTemplate = true`; keep the image at 18 × 18 pt.

## Design tokens
| Token | Value | Use |
| --- | --- | --- |
| Ground top | `#7B6BFF` | gradient start |
| Ground bottom | `#2E1F9E` | gradient end |
| Accent | `#FFB020` | the ⌘ only — one accent, nothing else |
| Object | `#FFFFFF` | card face, sheets (at 50% / 82%) |
| Object rim | `#F6F6FC` | card edge behind the face |
| Line | `#CBCDEC` | snippet line |

Deliberately clear of Notes yellow, Reminders red, and Finder/Mail blue so the icon
is not mistaken for a system app in a Login Items list.

## Files in this bundle
- `src/copystack-icon.svg` — layered source, with the Apple-style drop shadow.
- `src/copystack-icon-flat.svg` — same, no shadow. Use this one for the app icon
  pipeline; Icon Composer and the OS add their own shadow.
- `src/copystack-menubar.svg` — template glyph (viewBox 18, drawn at 144 for crisp rasters).
- `exports/copystack-icon-1024.png` — with shadow, transparent background.
- `exports/copystack-icon-1024-flat.png` — without shadow.
- `exports/copystack-icon-512.png`, `-256.png`, `-128.png`, `-32.png`, `-16.png`.
- `exports/copystack-menubar-18.png`, `-36.png`.
- `CopyStack Icon.dc.html` — the design page the assets were presented on: the three
  concepts, size proofs at 16/32/128/256, and the menu bar mock in both appearances.
  Reference only; not code to port.

## Known trade-off
The ⌘ disappears below roughly 32 px — intentional, the silhouette is the identity at
16 px. If the 16 px rendering needs the accent to survive, thicken the ⌘ stroke from
14 to 18 px and shorten the snippet line to keep the card face from crowding; that is
the only change the design tolerates at that size.
