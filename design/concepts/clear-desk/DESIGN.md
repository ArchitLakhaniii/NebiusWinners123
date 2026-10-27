# BrowserSkills, "clear desk" concept

A pixel-level HTML/CSS prototype of the BrowserSkills macOS window at 1440x900. Open `index.html`; keys 1 to 5 switch
states (Browse, Skills, Teach, Assistant, Settings), L toggles light and dark, Esc closes the panel. The same switches are
URL parameters (`?state=teach&theme=light&shot`, where `shot` hides the switcher). Screenshots in `screenshots/` were taken
headlessly with Playwright at 2x.

## What was studied

Dia product renders (diabrowser.com), Arc on macOS (Wikipedia screenshot, The Verge review), Apple HIG Materials (Liquid Glass
regular and clear, standard materials, vibrancy, "no glass in the content layer"), `NSVisualEffectView.Material`,
sloppatterns.com (534 patterns) and pols.dev/slop.md.

Observed. Dia: one row of chrome in a warm off-white, breadcrumb instead of a URL, quiet filled pills (Share, Chat) on the
right, 12 pt window radius, the page owns the window. Arc: 230 pt sidebar that holds the traffic lights and the URL, the page
drawn as a rounded card inset from the sidebar, the sidebar tinted by the Space, no top toolbar at all.

## Ten rules

1. One row of chrome. Navigation lives in the sidebar header; nothing is duplicated in a toolbar.
2. The page is the hero: a rounded, opaque card inset from the sidebar. Everything around it is a quiet tinted surface.
3. Glass is for the navigation layer only (sidebar, side panel, the floating suggestion bar). The content layer is opaque (HIG).
4. Depth comes from tone and a 1 px hairline, never from shadows or glows. The only shadow is the OS window shadow.
5. One accent, used for state (selected, live, verified, recording, picked) and the single primary button per view.
6. SF Pro at three sizes in the chrome (11, 12, 13). Hierarchy comes from weight (400, 500, 600) and vibrancy level, not size.
7. Secondary and tertiary text are vibrancy levels (`secondaryLabelColor`, `tertiaryLabelColor`), not ad hoc greys. Body text clears 4.5:1 in both modes.
8. Labels do the work. Icons appear only where they are the control (back, forward, reload, close, plus, delete, record).
9. Motion is 140 ms ease-out on opacity, colour and transform. Nothing animates size. Progress is a 2 px line, not a spinner.
10. Delight is quiet: a picked field gets a hairline outline and a tag on the page, the repeat suggestion rises 6 px into place,
    hover reveals the close and remove controls, a saved skill shows up already verified. No bounce, no pulse, no confetti.

## Tokens

Colours (contrast measured against the composited surface they sit on).

| Token | Dark | Light | Role |
| --- | --- | --- | --- |
| desk | `#2A2724` | `#D8D4CD` | desktop behind the window (solid) |
| chrome | `rgba(30,29,27,.72)` over desk = `#21201E` | `rgba(247,245,241,.72)` over desk = `#EEECE7` | sidebar and panel glass |
| stage | `#1D1C1A` | `#EFEDE9` | area around the page card |
| page | `#FBFAF8` | `#FBFAF8` | web content (always the site's own colours) |
| text | `#ECE9E4` (13.4:1) | `#1C1B19` (14.6:1) | labelColor |
| text-2 | text at 64% (6.3:1) | text at 62% (4.6:1) | secondaryLabelColor |
| text-3 | text at 42% (3.5:1) | text at 44% (2.7:1) | tertiaryLabelColor, never for essential copy |
| hair | white 9% | black 9% | separatorColor |
| hair-strong | white 16% | black 16% | borders on thumbnails and the agent tab glyph |
| fill, fill-2, fill-3 | white 6 / 10 / 15% | black 4.5 / 8 / 12% | quaternary, tertiary, secondary system fills |
| accent (text, dots, outlines) | `#4FC67F` (7.5:1) | `#15773F` (4.8:1) | the one accent |
| accent-fill (primary button) | `#15773F`, white label 5.6:1 | same | borderedProminent tint |
| accent-soft | accent at 16% | accent at 14% | verified badge, picking hover |
| page secondary | `#6F6B66` (5.1:1) | same | Northwind labels |
| Northwind brand | `#1F3A5F` | same | the demo site's own button and mark |

Type. SF Pro Text (`-apple-system`), `-webkit-font-smoothing: antialiased`.
11 regular (caption2: ids, endpoints, meta), 12 regular and 500 (caption: secondary rows, badges at 600), 13 regular, 500 and 600
(body: everything else). Monospace is SF Mono 11 and 12 for identifiers, step vocabulary, model names and paths only.
The Northwind page uses its own scale (26 display, 17, 15, 13, 12), which is web content and not part of the chrome.

Spacing. 4 pt grid: 2, 4, 6, 8, 10, 12, 14, 16. Sidebar 232 wide, padding 10 and 12 top. Rows 30 tall (tabs) and 28 tall
(controls, buttons, inputs). Page card inset 10 from the stage edges and 0 from the sidebar divider. Panel 344 wide, padding 14.
Northwind page gutter 32, measure 600.

Radii. Controls, inputs, rows 6. Buttons 7. Skill group 8. Page card and suggestion bar 10. Pills 14 (capsule). Window 12.

Materials. Sidebar and panel: `blur(24px) saturate(1.3)` under a 72% tint of the chrome colour, 1 px hairline on the inner
edge. Suggestion bar: `blur(14px) saturate(1.2)` under white 82%, 1 px black 8% ring, one soft shadow `0 8px 24px` black 8%
because it floats over content. Action pills: white 92%, no blur (they sit over the page header where blur adds nothing).
Window: `0 24px 60px` black 45% (dark) or 22% (light) plus a 1 px ring, which stands in for the OS shadow.

Motion. One curve, `cubic-bezier(.2, 0, 0, 1)` at 140 ms, on `opacity`, `background-color`, `color`, `border-color`,
`box-shadow`, `transform` only. Panel open and close are instant (layout changes are never animated). Indeterminate progress
is a 2 px track with a 40% accent segment sliding left to right every 900 ms (skill run, assistant busy, page load line).
`prefers-reduced-motion` turns all of it off.

## Mapping to SwiftUI and AppKit

| Element | Implementation |
| --- | --- |
| Window | `NSWindow` with `.fullSizeContentView`, `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`; the system traffic lights stay, positioned at (18, 18) in the sidebar |
| Sidebar | `NSVisualEffectView(material: .sidebar, blendingMode: .behindWindow, state: .followsWindowActiveState)`; in SwiftUI, `.background(.bar)` on the `TabSidebar` or a `NavigationSplitView` sidebar column, width 232 |
| Side panel | same material as the sidebar, `.sidebar` with `.behindWindow`, 344 wide; replaces the current `Divider` + `SidePanel` pair; a plain `Rectangle().fill(.separator)` 1 pt wide on its leading edge |
| Stage behind the page | `Color(nsColor: .underPageBackgroundColor)` (or `NSVisualEffectView(material: .underPageBackground, blendingMode: .withinWindow)`) |
| Page card | the `WKWebView` container `NSView` with `wantsLayer`, `layer.cornerRadius = 10`, `layer.cornerCurve = .continuous`, `masksToBounds`, `layer.borderWidth = 1`, `layer.borderColor = NSColor.separatorColor` |
| Hairlines | `Divider()` or `Color(.separator)`; strong hairline `Color(.tertiaryLabelColor)` |
| Fills | `NSColor.quaternarySystemFill`, `.tertiarySystemFill`, `.secondarySystemFill` (macOS 14) for fill, fill-2, fill-3 |
| Text levels | `.foregroundStyle(.primary)`, `.secondary`, `.tertiary` |
| Accent | asset catalogue `AccentColor` with Any `#15773F` and Dark `#4FC67F`; primary buttons `.buttonStyle(.borderedProminent)` `.tint(Color("AccentFill"))` (`#15773F` in both appearances), `.controlSize(.large)` for 28 pt |
| Quiet buttons | `.buttonStyle(.bordered)` with `.tint(.secondary)` or a custom `ButtonStyle` using `secondarySystemFill`, radius 7 |
| Icon buttons | `Button` + `Image(systemName:)` in `.buttonStyle(.borderless)`, 24x24 hit area, `.foregroundStyle(.secondary)`; symbols: `chevron.left`, `chevron.right`, `arrow.clockwise`, `xmark`, `plus`, `trash`, `minus` |
| Address | `RoundedRectangle(cornerRadius: 6).fill(.quaternary)`, `Image(systemName: "lock.fill")` 11 pt tertiary, host `.primary`, path `.tertiary`, `Font.system(size: 12)` |
| Tab row | `HStack` 30 pt tall, `RoundedRectangle(cornerRadius: 6)` filled with `secondarySystemFill` when selected and `quaternarySystemFill` on hover (`.onHover`); close button opacity bound to hover; favicon `RoundedRectangle(cornerRadius: 4)` 16x16 |
| Agent tab glyph | 16x16 `RoundedRectangle(cornerRadius: 4).strokeBorder(.tertiary)` with a 6 pt `Circle().fill(.accent)` inside; busy dot 6 pt accent circle at the trailing edge |
| MCP status | `Circle().fill(.accent)` 7 pt, `Text("MCP live").font(.system(size: 12, weight: .semibold))`, endpoint `Font.system(size: 11, design: .monospaced).foregroundStyle(.tertiary)` |
| Teach pill | `Capsule().fill(Color.white.opacity(0.92))` with `.overlay(Capsule().strokeBorder(.black.opacity(0.08)))`, `Image(systemName: "record.circle")` idle and `"circle.fill"` while recording, recording state fills the capsule with AccentFill and white text; placed with `ZStack(alignment: .topTrailing)` over `WebViewHost`, padding 12 |
| Skills pill | same capsule; pressed state `Color(.labelColor)` fill with `windowBackgroundColor` text |
| Repeat suggestion | `ZStack(alignment: .bottom)` over the web view, `RoundedRectangle(cornerRadius: 10).fill(.regularMaterial)`, `.shadow(color: .black.opacity(0.08), radius: 12, y: 4)`, `.transition(.opacity.combined(with: .offset(y: 6)))`, `.animation(.easeOut(duration: 0.14))` |
| Panel tabs | `HStack` of `Button`s in `.buttonStyle(.plain)`; selected `Font.system(size: 13, weight: .semibold)` + `.primary`, others `.medium` + `.tertiary`; replaces the segmented `Picker` |
| Skill group | `VStack` in `RoundedRectangle(cornerRadius: 8).fill(.quaternary)` only when expanded or hovered; header `Button` with title 13 semibold, id `Font.system(size: 11, design: .monospaced).foregroundStyle(.tertiary)`, `lineLimit(1)` |
| Badge | `Capsule().fill(.accent.opacity(0.16))`, `Font.system(size: 11, weight: .semibold)`, `.foregroundStyle(.accent)`; neutral badge uses `secondarySystemFill` and `.secondary` |
| Inputs | `TextField` with `.textFieldStyle(.plain)` inside `RoundedRectangle(cornerRadius: 6)` filled `quaternarySystemFill` and stroked `.separator`; focus stroke `.accent`; 28 pt tall; monospaced for identifiers |
| Run line, busy line, load line | `Capsule()` 2 pt tall in `secondarySystemFill` with a 40% width accent `Capsule()` offset by `.linear(duration: 0.9).repeatForever(autoreverses: false)`; determinate page load uses `ProgressView(value:)` `.progressViewStyle(.linear)` `.tint(.accent)` clipped to 2 pt |
| Checks | `Label(text, systemImage: "checkmark")` with `.labelStyle(.titleAndIcon)`, icon `.accent` 12 pt semibold, text `.secondary` 12 |
| Evidence thumbnail | `Image(nsImage:)` of the run screenshot, 44x28, `RoundedRectangle(cornerRadius: 4)` clip and `.tertiary` stroke; `Link`-style `Button` opens the file |
| Steps disclosure | `DisclosureGroup` with a custom `.disclosureGroupStyle` drawing `chevron.right` rotated 90 degrees when open |
| Step vocabulary | `Text(step.kind.rawValue).font(.system(size: 11, design: .monospaced))` in `RoundedRectangle(cornerRadius: 4).fill(.quaternary)` |
| Picked field on the page | injected page CSS in the isolated world: `box-shadow: inset 0 0 0 1.5px #15773F; border-radius: 6px` and a `::after` tag in SF Mono 11 on AccentFill |
| Chat lines | user: `RoundedRectangle(cornerRadius: 10).fill(secondarySystemFill)` trailing aligned, max 86% width; tool: `Font.system(size: 11, design: .monospaced).foregroundStyle(.tertiary)` with a 2 pt leading `Rectangle().fill(.tertiary)`; busy: 12 pt `.secondary` under the line |
| Composer | `TextField("Ask Nemotron")` 30 pt in the input style above, `Button("Clear")` quiet |
| Settings | `Form` with `LabeledContent` rows, `.formStyle(.grouped)`, `.scrollContentBackground(.hidden)`; labels 12 `.secondary` 104 pt wide, `SecureField` for keys, values monospaced 12; "Saved" confirmation is a 12 pt accent `Text` faded in for 1.2 s |
| Accessibility | all materials fall back to opaque under Reduce Transparency automatically; hover-revealed controls remain reachable by keyboard with a 2 pt accent focus ring (`.focusable()` default ring tinted by AccentColor) |
