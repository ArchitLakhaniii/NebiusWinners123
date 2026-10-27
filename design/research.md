# Arc / Dia research notes (for BrowserSkills design)

## Dia (diabrowser.com product shots)
- Light, warm off-white chrome (~#F3F2EF), window corners ~12px, content area white with its own rounded corners and hairline edge; chrome and content read as two layers, not one box.
- Left sidebar: traffic lights, then a row of 3 square app tiles (Gmail, Calendar, Slack) with favicon on a slightly darker square, then a flat tab list (favicon + title, 13px), active tab = soft filled row. "New Tab" row at the bottom of the list with a plus, dimmed.
- Top bar inside content: sidebar toggle, back/forward/reload (thin 1.5px icons, grey), then breadcrumb style title "Made with Dia / The Tuesday Brief", right side: "Share" and "Chat" as small pill buttons with icon+label on a tinted pill. Nothing else.
- No borders around buttons; separation by tone (pills ~#E9E8E4 on #F3F2EF). Text black/dark grey, secondary ~#8A8A86.
- Brand type: serif display (editorial), UI type: system sans. We keep UI sans only.
- Very few elements per surface; copy is short, sentence case, no icons next to every label.

## Arc (community screenshots)
- Sidebar is a tinted translucent layer (space color) over the desktop; the web page is a floating rounded card (radius ~10) with a soft shadow, inset ~8px from the sidebar/edges; no top bar at all, URL lives in the sidebar as a pill at the top.
- Sidebar sections: favorites as a grid of icon tiles, pinned tabs, then "today" tabs; a "new tab" affordance at the bottom; small, 13px type; rows ~28-30px tall, radius 6-8.
- Command bar (Cmd+T): centered floating glass panel, big text field, results below; this is the "one input for everything" pattern.
- Spaces: swipe between tinted sidebars; the tint is a single hue at low alpha, not a gradient.

## Rules to carry into BrowserSkills
1. Two layers: translucent chrome (sidebar + optional right panel) and the page as a floating rounded card with hairline edge and a soft shadow.
2. No top address bar in the page; URL pill at the top of the sidebar (Arc), with back/forward/reload as small grey glyphs beside or above it.
3. Rows 28-30px, 13px text, radius 8 on rows, 10-12 on cards/panels, 12 on the window.
4. One accent only; status via a 6-7px dot plus a word, never color alone.
5. Pills for secondary actions (icon + label, tinted fill, no border); one filled accent button per surface at most.
6. Sections labeled with 11px uppercase tracked captions, nothing else decorative.
7. Hairlines at 6-10% white (dark) or 6-8% black (light); fills at 5-8%; hover +4%.
8. Motion 120-180ms, opacity/translate only.
9. Copy: short, sentence case, no exclamation marks, no em dashes, no emoji.
10. Fonts: SF Pro in the app; Geist as the stand-in in Pencil.

## Dia sidebar detail (arc.net farewell page mockup)
- Sidebar bg warm grey ~#F1EFEA; header row: traffic lights + profile name "Personal" in 12px semibold, centered-left.
- Favorites: 2 rows x 3 tiles, each tile ~44x30 rounded 8, fill slightly darker (#E6E3DD), favicon 16px centered.
- Pinned tab "Spotify": white row (#FFFFFF) radius 8, 12-13px text, favicon left; active state = white, others transparent.
- Folders are rows with a small 3px vertical colored bar + name + chevron; expanded folder gets a tinted container (lavender #E8E4F6, sand #F2E8D8) at radius 10 containing child rows; one hue per folder, flat.
- Row height ~26-28, left inset 12, favicons 14px, text ~12.5px, secondary grey #6B6B68.
- Right of sidebar: top bar with sidebar toggle, back, forward, reload, then plain domain "spotify.com" in grey; "Chat" button at far right of page top bar.

## Apple HIG, Materials / Liquid Glass (macOS 26)
- Glass is for the functional layer (sidebars, toolbars, floating controls) that sits above content; never put glass in the content layer itself. Page content stays opaque.
- Regular glass blurs and adjusts luminosity for legibility; clear glass only over rich media with a dimming layer. For a browser chrome use regular.
- Use vibrant label colors (label, secondaryLabel, tertiaryLabel) on materials instead of fixed greys; separators use the single vibrant separator color.
- macOS materials: NSVisualEffectView with .sidebar material (behind-window blending) for the sidebar, .popover / .hudWindow for floating panels (within-window). SwiftUI: .background(.regularMaterial) / .ultraThinMaterial; on macOS 26 `.glassEffect()` is available for controls.
- Prefer translucency to opaque colors in windows; pick materials by semantic role, not by the color they produce.

## Implementation mapping (SwiftUI/AppKit) decided
- Window: .windowStyle(.hiddenTitleBar), fullSizeContentView, titlebar transparent, traffic lights kept at the top-left of the sidebar.
- Sidebar: NSVisualEffectView(material: .sidebar, blendingMode: .behindWindow), width 232, no divider; the web view sits in a rounded card (radius 10) with a 1px separator-color stroke and a 24px soft shadow, inset 8-10px from chrome.
- Right panel (skills/teach/assistant): same material with .withinWindow blending, width 328, rounded 10, inset 10px, hidden by default; toggled with a single panel icon.
- Accent: one hue (teal, 14B8A6 dark / 0F9E8E light) used for live dots, the single primary button, and text links only.
