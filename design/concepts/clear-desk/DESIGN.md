# BrowserSkills, "clear desk" concept

A pixel-level HTML/CSS prototype of the BrowserSkills macOS window at 1440x900. Open `index.html`; keys 1 to 5 switch
states (Browse, Skills, Teach, Assistant, Settings), L toggles light and dark, Esc closes the panel. The same switches are
URL parameters (`?state=teach&theme=light&shot`, where `shot` hides the switcher). Screenshots in `screenshots/` were taken
headlessly with Playwright at 2x.

## What was studied

Real product screenshots, not marketing copy: Dia (window renders from diabrowser.com: warm tinted chrome, favicons in rounded
tiles, breadcrumb instead of a URL, a 44 pt capsule ask bar with a filled circular send button, page corners softened),
Arc (sidebar carries the traffic lights and the URL, tinted glass sidebar, page as an inset card, no toolbar), Raycast (one glass
sheet, 8 to 10 pt row radii, 13 pt medium labels, sections set only by spacing), Things 3 (friendly weights, roomy 34 pt rows,
colour only in glyphs), Linear (near-monochrome, hierarchy from weight), Apple HIG Materials and `NSVisualEffectView.Material`,
sloppatterns.com (534 patterns) and pols.dev/slop.md.

What makes those feel finished: one material for the whole chrome, not a border per panel; capsules and 9 to 12 pt radii that
match the window radius; a single dark or light "ink" for primary actions instead of a brand colour; status written as words;
13 to 14 pt medium labels on 32 to 34 pt rows; secondary text at 60% rather than a different grey.

## Ten rules

1. One sheet of glass. The whole window is one blurred, tinted material over the wallpaper; nothing inside it has a border.
2. The page is the only opaque thing: a 12 pt card with a soft shadow, inset from the glass.
3. Glass is for the navigation layer only (window chrome, floating capsule, action pills). Web content stays opaque (HIG).
4. Depth from the material and one shadow under the page card; no hairline boxes, no inner cards.
5. One ink capsule per view; every other action is plain text that darkens on hover. The accent (ember) appears only on
   picked fields and progress lines; recording is an ink pill with a count.
6. One humanist sans (Mona Sans) at 14 pt medium for rows, 16 pt semibold for titles, 13 pt at 60% for secondary. Weight and opacity carry hierarchy; no SF Pro so the chrome does not read as a system template.
7. Status is text ("v2, verified", "Succeeded", "fixture, not verified"), not badges or dots.
8. Capsules for actions, 9 to 12 pt radii for surfaces, matching the 14 pt window radius. No one-radius-for-everything.
9. Motion is 140 ms ease-out on opacity, colour and transform. Nothing animates size. Progress is a 2 pt line.
10. Quiet delight: the suggestion capsule rises 8 pt into place, picked fields get an ember outline with a tag on the page,
    close and remove controls appear on hover, the send button is a filled circle.

## Tokens

| Token | Dark | Light | Role |
| --- | --- | --- | --- |
| wallpaper | `wallpaper.jpg` (Wolfgang Lutz, Unsplash licence) | same | desktop behind the window |
| tint | `rgba(24,24,28,.58)` | `rgba(250,249,246,.64)` | the one glass sheet, `blur(60px) saturate(1.8)` |
| text | white 92% (11.9:1 on the composited glass) | `#1C1C1E` 94% (12.7:1) | labelColor |
| text-2 | white 60% (6.1:1) | black 60% (5.6:1) | secondaryLabelColor |
| text-3 | white 40% (3.6:1, non-essential only) | black 42% (3.4:1) | tertiaryLabelColor |
| fill, fill-2, fill-3 | white 7 / 12 / 18% | black 5 / 8.5 / 13% | quaternary, tertiary, secondary system fills |
| rule | white 10% | black 9% | separator, used once (run summary) |
| ink, on-ink | `#F5F5F4`, `#1A1A1C` (15.9:1) | `#1C1C1E`, `#FFFFFF` (16.4:1) | primary buttons, pressed pills |
| accent | `#F08A5C` (4.0:1 on glass, 3:1 is enough for a dot or line) | `#C4532A` (4.5:1 on the page) | recording, picked outline, progress |
| page | `#FBFAF8` | same | web content |
| bar | `rgba(30,30,34,.72)` white text | `rgba(30,30,34,.78)` | the suggestion capsule, dark in both modes |

Composited glass measured against the wallpaper average (135,147,173): dark `#40444F`, light `#D1D6E0`.

Type. Mona Sans (GitHub, SIL OFL, in `fonts/`), weights 400/500/600/700, body tracking -0.005em, titles -0.015em. 11 (ids,
shortcuts), 12 to 13 (secondary), 14 (rows, buttons, body), 15 (panel tabs, chat), 16 (skill titles). In the app, bundle the
TTF and register it with `CTFontManagerRegisterFontsForURL`; `Font.custom("Mona Sans", size:)` everywhere `Font.system` is listed below. SF Mono 11.5 to 12.5 for identifiers, step vocabulary and paths. The Northwind page uses its
own scale (28 display, 18, 15, 14, 12), which is web content.

Spacing. Sidebar 244 wide, padding 14. Rows 34 (tabs, address, inputs), buttons and pills 32, composer 44. Page card inset 12.
Panel 372 wide, padding 16. Northwind gutter 36, measure 620.

Radii. Window 14. Page card 12. Skill group 12. Inputs and address 10. Rows and icon buttons 9 and 7. Favicons 6. Code 6.
Capsules (buttons, pills, suggestion, composer) fully round.

Materials. Window: the glass is the wallpaper blurred (Gaussian 28 px, saturation 1.3; shipped as `wallpaper-blur.jpg` so the
prototype renders identically in headless Chromium, which skipped `backdrop-filter` on the full-window sheet) under the tint; `0.5px` inner white ring and a 30/80 shadow
standing in for the OS window shadow. Page card shadow `0 1px 2px` + `0 16px 48px` black 35% (dark) or 14% (light).
Action pills: white 78% with `blur(24px) saturate(1.6)` and a 0.5 px ring. Suggestion capsule: `--bar` with the same blur.

Motion. One curve `cubic-bezier(.2,0,0,1)` at 140 ms on opacity, colour, box-shadow and transform only. Panel open and
close are instant. Indeterminate progress is a 2 pt track with a 40% accent segment every 900 ms. `prefers-reduced-motion`
turns everything off.

## Mapping to SwiftUI and AppKit

| Element | Implementation |
| --- | --- |
| Window | `NSWindow` with `.fullSizeContentView`, `titlebarAppearsTransparent`, `titleVisibility = .hidden`, `isOpaque = false`, `backgroundColor = .clear`; traffic lights left where the system puts them (sidebar top) |
| The glass sheet | one `NSVisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)` as the window content view, tinted by a `CALayer` fill of `--tint`; SwiftUI `.background(.ultraThinMaterial)` on the root `HStack` is the lighter alternative |
| Sidebar, panel | plain `VStack`s on the sheet; no `Divider`, no material of their own; sidebar `.frame(width: 244)`, panel `.frame(width: 372)` |
| Page card | `WKWebView` container `NSView` with `wantsLayer`, `cornerRadius = 12`, `cornerCurve = .continuous`, `masksToBounds`; shadow on a parent view: `.shadow(color: .black.opacity(0.35), radius: 24, y: 16)` + `.shadow(color: .black.opacity(0.25), radius: 1, y: 1)` |
| Fills | `NSColor.quaternarySystemFill`, `.tertiarySystemFill`, `.secondarySystemFill` |
| Text | `.foregroundStyle(.primary)`, `.secondary`, `.tertiary` |
| Ink buttons | custom `ButtonStyle`: `Capsule().fill(Color(.labelColor))`, label `Color(.windowBackgroundColor)`, 32 pt, `Font.system(size: 13, weight: .semibold)` |
| Ghost buttons | `Capsule().fill(.quaternary)`, 32 pt, 13 pt medium, hover `.tertiary` |
| Icon buttons | `Button` + `Image(systemName:)` `.buttonStyle(.borderless)` 26x26, `RoundedRectangle(cornerRadius: 7)` hover fill; symbols `chevron.left`, `chevron.right`, `arrow.clockwise`, `xmark`, `plus`, `trash`, `minus`, `arrow.up` |
| Address | `RoundedRectangle(cornerRadius: 10).fill(.quaternary)` 34 pt, host 13 pt medium `.primary`, path `.tertiary` |
| Tab row | 34 pt, `RoundedRectangle(cornerRadius: 9)`; selected `secondarySystemFill`, hover `quaternarySystemFill`; label 13 pt medium `.secondary`, `.primary` when selected; favicon `RoundedRectangle(cornerRadius: 6)` 20x20 with the site colour and a 10 pt bold initial, or the real favicon image |
| Agent tab | same row; glyph is a 20 pt tile of `tertiarySystemFill` with an 8 pt `RoundedRectangle(cornerRadius: 2)` in `.secondary`; trailing host text 11 pt `.tertiary` |
| MCP status | two `Text`s: "MCP" 12 pt semibold `.primary` + sentence 12 pt `.secondary`; endpoint 11 pt monospaced `.tertiary`. No dot |
| Action pills | `Capsule().fill(Color.white.opacity(0.78)).background(.thinMaterial)` with a 0.5 pt black 10% ring, 32 pt, 13 pt medium; pressed and recording states `Capsule().fill(Color(.labelColor))` with inverted text; recording dot `Circle().fill(accent)` 8 pt; `ZStack(alignment: .topTrailing)` over `WebViewHost`, padding 14/16 |
| Suggestion capsule | `ZStack(alignment: .bottom)`, `Capsule().fill(Color(red: 0.12, green: 0.12, blue: 0.13).opacity(0.72)).background(.ultraThinMaterial)`, 52 pt, inner 0.5 pt white 12% ring, `.shadow(radius: 16, y: 12)`; `.transition(.opacity.combined(with: .offset(y: 8)))`, `.animation(.easeOut(duration: 0.14))` |
| Panel tabs | `HStack` of plain `Button`s, 14 pt; selected `.semibold` `.primary`, others `.medium` `.tertiary`; `xmark` icon button trailing |
| Skill group | `VStack` in `RoundedRectangle(cornerRadius: 12).fill(.quaternary)` when expanded or hovered; title 14 pt semibold, subtitle 12 pt `.secondary` written as "host · v2, verified" |
| Inputs | `TextField` `.textFieldStyle(.plain)` in `RoundedRectangle(cornerRadius: 10).fill(.quaternary)`, 34 pt, no stroke; focus ring `strokeBorder(accent, lineWidth: 2)`; identifiers monospaced 12.5 |
| Run summary | `Rectangle().fill(.separator)` 1 pt above; "Succeeded" 13 pt semibold + "2.4 s, run 8f3a21c0" 12 pt `.secondary`; outputs as a two-column `Grid` with monospaced keys; checks `Label(_, systemImage: "checkmark")` 12 pt `.secondary` |
| Evidence | `Image(nsImage:)` 44x28 in `RoundedRectangle(cornerRadius: 5)` with a 0.5 pt ring, 13 pt label, opens the file |
| Steps | `DisclosureGroup("4 steps")` with a custom chevron style; step kinds in `RoundedRectangle(cornerRadius: 6).fill(.tertiary)` monospaced 11.5 |
| Picked field on the page | injected CSS in the isolated world: `box-shadow: inset 0 0 0 1.5px #C4532A; border-radius: 8px` and a `::after` tag, SF Mono 11 on `#C4532A` |
| Chat | user `Capsule`-like `RoundedRectangle(cornerRadius: 18).fill(.tertiary)` trailing, 14 pt; assistant 14 pt `.primary`; tool lines monospaced 12 `.tertiary` with a 2 pt leading `Rectangle().fill(.secondary.opacity(0.3))`; busy line 2 pt track above 13 pt `.secondary` |
| Composer | `Capsule().fill(.quaternary)` 44 pt, `TextField("Ask Nemotron")` 14 pt, trailing `Circle().fill(Color(.labelColor))` 32 pt with `arrow.up` |
| Settings | `Form` + `LabeledContent`, `.formStyle(.grouped)`, `.scrollContentBackground(.hidden)`; labels 13 pt `.secondary` 92 pt wide; `SecureField` for keys; monospaced 12.5 values; "Saved" 13 pt `.secondary` faded in for 1.2 s |
| Accessibility | Reduce Transparency makes the sheet opaque automatically; hover-only controls stay keyboard reachable with a 2 pt accent focus ring |
