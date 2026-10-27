# Clear desk, revised

Pencil source: `clear-desk.pen` (10 frames: Browse, Skills, Teach, Assistant, Settings, each in dark and light). Screenshots at 2x live in `screenshots/`.

## Ten rules taken from Arc, Dia and macOS materials

1. The page is the product. Everything else is one translucent material with as little chrome as a sidebar and a strip can be.
2. One material, not many boxes. Sidebar, strips and the side panel sit directly on the window material. Controls are tinted fills on that material, never a card inside a card.
3. The page is a card. The web view is an inset, rounded, opaque sheet with a hairline shadow, so the browser reads as a desk and the site as paper on it.
4. One accent, used for state and action only: primary buttons, recording, picked fields, the active agent tab. Nothing decorative is colored.
5. Status is words. No dots, no badges in four colors. "MCP serving 3 skills", "v2 verified", "fixture, not verified".
6. Type carries hierarchy. Three greys and two weights do what color and icons would otherwise do. Icons only where the real product has them (favicons, chevrons, the record glyph).
7. Hairlines, not dividers. 1px at 10 percent alpha, and only where a list truly changes meaning (pinned vs today, skill vs skill).
8. Every control is labeled. Teach, New tab, Clear, Stop are words with shortcuts beside them, not icon buttons with tooltips.
9. The demo site has its own identity. Northwind uses a serif wordmark and a different sans so the browser chrome and the page never blur together.
10. Fast and quiet. 120 to 180 ms crossfades and fills; nothing animates size; progress is a thin line, not a spinner.

## Tokens

Fonts in Pencil are stand-ins because only Google fonts are available there. In the app, the browser chrome is SF Pro (system) and code is SF Mono.

| Role | Pencil | SwiftUI |
| --- | --- | --- |
| Chrome UI | Schibsted Grotesk | `.system(size:)` SF Pro Text |
| Code, tool names, ids | IBM Plex Mono | `.system(.caption, design: .monospaced)` |
| Northwind wordmark, status headline | Instrument Serif | web content, not ours |
| Northwind body | Instrument Sans | web content, not ours |

Type scale (px): 11 hints and keys, 12 secondary labels, 13 body and rows, 14 titles, 17 section, 22 page heading, 48 page status headline.

Colors, dark / light. Contrast measured against the composed window material (dark #232328, light #e2e0de over a mid wallpaper).

| Token | Dark | Light | Contrast dark / light |
| --- | --- | --- | --- |
| window | #1c1b1f at 78% | #f3f0eb at 84% | material |
| text | #f3f2ef | #1b1a18 | 14.0 / 13.2 |
| text-2 | #a9a8a4 | #5f5c56 | 6.6 / 5.2 |
| text-3 | #8d8c88 | #6a675f | 4.6 / 4.4 (11px hints only) |
| control | white 8% | black 6% | fill |
| control-2 | white 13% | black 11% | selected segment |
| hairline | white 10% | black 9% | 1px |
| accent (text) | #e8784e | #a93d17 | 5.4 / 4.7 |
| accent-fill (buttons) | #c4532a | #c4532a | white on it 4.55 |
| page | #fbfaf8 | same | opaque sheet |
| page-text / page-text-2 | #1a1a1c / #6b6b70 | same | 16.7 / 5.1 on page |
| page-ink (Northwind) | #1f3a5f | same | 11.0 on page |

Spacing: 2, 4, 6, 8, 10, 12, 16, 22, 28, 40. Sidebar 232, panel 348, window inset 28 on the desktop, page inset 10.

Radii: window 12, page 10, address pill 9, segmented control 8 outer 6 inner, rows and buttons 7, favicons 4, chips 5.

Material: window fill above plus backdrop blur 48, outer shadow 0 24 60 at 40% and 0 1 2 at 33%, 1px hairline stroke inside. Page card: shadow 0 1 3 at 30%.

Motion: 120 ms for hover and selection fills, 150 ms for panel content crossfade, 180 ms for the panel sliding in from the trailing edge. Easing ease-out on enter, ease-in on exit. Never animate width or height; the page card resizes without animation when the panel opens.

## Element to AppKit and SwiftUI mapping

| Element | Implementation |
| --- | --- |
| Window material | `NSVisualEffectView`, material `.sidebar` for the sidebar column and `.underWindowBackground` for the panel column, blending `.behindWindow`, `.titlebarAppearsTransparent`, full size content view |
| Traffic lights and nav | standard window buttons; `chevron.left`, `chevron.right` 16pt `.secondary` |
| Address pill | `RoundedRectangle(9)` fill `Color.primary.opacity(0.08)`, host in `.body.weight(.medium)`, path in `.tertiary` |
| Tab row | `HStack` 30pt tall, favicon 16pt in `RoundedRectangle(4)`, selected fill `Color.primary.opacity(0.08)` in `RoundedRectangle(7)`, close `xmark` 13pt on hover |
| Pinned and Today sections | `Divider()` hairline, `Text("Today").font(.caption2.weight(.medium)).foregroundStyle(.tertiary)` with trailing `Clear` |
| Agent tab | favicon `sparkles` tinted accent, trailing state text `.caption2` |
| Teach and New tab | rows with `record.circle` and `plus`, shortcut `KeyboardShortcut` text in `.caption2.tertiary`; recording state swaps to `record.circle.fill` tinted accent and label "Recording, n steps" |
| MCP status | two `Text` lines, `.caption2.weight(.medium).secondary` and `.caption2.monospaced().tertiary`, no indicator shape |
| Repeat suggestion | `HStack` 36pt above the web view, `arrow.triangle.2.circlepath` tinted accent, plain `Not now`, `Save as skill` `.buttonStyle(.borderedProminent).tint(accent)` |
| Page card | `WKWebView` inside `RoundedRectangle(10)` clip with shadow 0 1 3 |
| Panel tabs | `Picker` `.pickerStyle(.segmented)` 28pt |
| Skill row | disclosure chevron, title `.callout.weight(.medium)`, tool name `.caption.monospaced().secondary`, version text `.caption2.weight(.medium)` |
| Inputs | `TextField` `.textFieldStyle(.plain)` inside `RoundedRectangle(7)` fill primary 8% |
| Run, Save skill, Save | `.borderedProminent` tinted accent-fill, 28pt |
| Watch, Copy MCP config, Pick another result | `.bordered` 28pt |
| Run evidence | `checkmark` 13pt, outputs as `Grid` with mono keys, checks in `.caption2.tertiary`, `Link("Evidence screenshot")` tinted accent |
| Teach step list | `Grid` rows: index and kind in `.caption.monospaced()`, target `.body`, `minus.circle` on hover |
| Picked results on page | injected outline 1.5px accent, chip label in mono white on accent-fill |
| Assistant | user `Text` in `RoundedRectangle(10)` fill primary 8%, tool lines `arrow.turn.down.right` and `arrow.turn.down.left` with `.caption.monospaced()`, progress `ProgressView(value:)` `.progressViewStyle(.linear)` 2pt tinted accent |
| Settings | `Form` `.formStyle(.grouped)` with `Section` headers in `.caption.secondary`, `SecureField` for keys, trailing `Saved 2 minutes ago` `.caption.tertiary` |
