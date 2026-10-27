# Flint

Graphite glass, one clay accent. The browser is a single sheet of macOS sidebar material; the web page floats on it as an opaque, rounded canvas, Arc style. Everything the product adds (tabs, Teach, Skills, Assistant, Settings) lives on the glass, never on the page. Dark first, light as a sibling, not an afterthought.

Open `index.html`. Keys 1 to 5 switch states (Browse, Skills, Teach, Assistant, Settings), L toggles light. `python3 shoot.py` renders `screenshots/` at 2x.

## 10 rules extracted from Arc, Dia and Apple's materials guidance

1. The page is the product. Chrome is one translucent sheet; the page is an opaque card inset 8 px with a 10 px radius and a soft shadow (Arc's canvas). Nothing else gets a shadow.
2. Navigation lives in the sidebar, not above the page (Arc). Back, forward, reload, the address field and Teach share a 232 px column with the tabs, so the page gets the full remaining height.
3. One material, two tints. Sidebar and side panel are the same `sidebar` material; "surfaces" inside it are only 6 to 14 percent white (or black) fills. No stacked cards, no card inside a card.
4. Hairlines, not boxes. Groups are separated by 1 px lines at 8 percent alpha. Borders appear only on controls that take input.
5. One accent (clay), used for selection, the primary button and progress. Green and red are reserved for meaning only: verified and MCP live, recording. Never decorative.
6. Type is the system font at system sizes: 13 body, 12 secondary, 11 captions, mono at 11 for identifiers. Weight carries hierarchy; size steps are few. No tracking, no all caps labels (Dia).
7. Controls are small and dense like AppKit: 26 px buttons, 28 px fields, 30 px list rows, 7 px radii, 8 px for the address pill, pill badges at 18 px.
8. Hide until hovered. Tab close buttons, step remove buttons and secondary actions appear on hover. Empty states say one sentence.
9. Motion is 120 to 180 ms, ease-out, on opacity, color and a 6 px translate. Nothing animates width or height. Progress is a 2 px line with a known fraction; no spinners.
10. Liquid Glass stays in the navigation layer (Apple's rule): translucency for the sidebar, panel and the floating suggestion; never on page content, never on cards.

## Tokens

Contrast ratios are measured against the effective glass color (dark `#1d1e21`, light `#eeedea`).

### Color, dark (default)

| Token | Value | Use | Contrast |
| --- | --- | --- | --- |
| glass | rgba(28,29,32,.76) over wallpaper, blur 40 px, saturate 140% | window sheet | |
| text | #ececec | primary | 14.1:1 |
| text-2 | #ececec at 60% | secondary | 5.9:1 |
| text-3 | #ececec at 38% | tertiary, placeholders, mono meta | 3.2:1 |
| line | white 8% | hairlines | |
| fill / fill-2 / fill-3 | white 6% / 10% / 14% | hover, selected, pressed | |
| accent | #e2855e | accent text, icons, progress | 6.2:1 |
| accent-btn | #c25a30 | primary button fill, picked-result outline | white on it 4.4:1 |
| ok | #63b77c | verified, MCP live, checks | 6.8:1 |
| wait | #d9a441 | validating badge | 7.4:1 |
| rec | #e5484d | recording dot and count | 4.3:1 |
| toast | rgba(28,29,32,.92), blur 24 px | repeat suggestion | |

### Color, light

| Token | Value | Contrast |
| --- | --- | --- |
| glass | rgba(240,239,236,.78), blur 40 px | |
| text | #1d1d1f | 14.4:1 |
| text-2 | #1d1d1f at 62% | 4.5:1 |
| text-3 | #1d1d1f at 48% | 3.0:1 |
| line | black 9% | |
| fill / fill-2 / fill-3 | black 5% / 8% / 12% | |
| accent | #b2491f | 4.6:1 |
| accent-btn | #bd5027 | white on it 4.8:1 |
| ok | #257a41 | 4.6:1 |
| wait | #8a6210 | 4.7:1 |
| rec | #c8343a | 4.5:1 |

Northwind demo portal (page content, not the browser): background #fbfbfa, text #1a2430 (15.7:1), secondary #6b7682 (4.6:1), brand #2a4a62 (white on it 9.3:1).

### Type

System font. SF Pro Text below 20 px, SF Pro Display for the page title. SF Mono for identifiers.

| Role | Size / weight | Where |
| --- | --- | --- |
| Row | 13 / 400 | tabs, steps, assistant text, outputs |
| Emphasis | 13 / 600 | skill names, toast title, recording label |
| Secondary | 12 / 400 | toast subtitle, summaries, segment labels (500) |
| Control | 12.5 / 500 | buttons, address field, form values |
| Caption | 11.5 / 400 | checks, notes, MCP status |
| Caption mono | 11 / 400 | skill ids, run ids, tool calls, durations |
| Meta mono | 10.5 / 400 | endpoint, compiler, evidence URL |
| Badge | 11 / 600 | verified, success, validating |

Line height 1.35 for rows, 1.45 for paragraphs. No letter spacing anywhere except the password dots.

### Spacing

4 px grid. Sidebar padding 10 left, 8 right. Panel padding 14. Canvas inset 8. Row height 30, control height 26 and 28, address 32, composer 36, settings row 36, toast 56. Gaps inside groups 8 and 10, between groups 12 to 16.

### Radii

Window 12, canvas 10, settings group and run block 8 to 10, address 8, controls 7, rows 6, favicons and picked tags 4, badges and composer fully round.

### Material and blur

| Surface | Value |
| --- | --- |
| Window sheet | glass tint over the desktop, backdrop blur 40 px, saturate 140%, inset 1 px hairline |
| Suggestion toast | toast tint, blur 24 px, shadow 0 12 32 at 40% (dark) or 16% (light), 1 px hairline |
| Canvas | opaque #fbfbfa, shadow 0 10 30 at 35% (dark) or 14% (light) |
| Segmented selection | glass-strong (94%) with 0 1 2 shadow at 18% |

### Motion

| Token | Value |
| --- | --- |
| dur | 140 ms |
| ease | cubic-bezier(.2, .7, .2, 1) |
| Hover, selection, focus ring | 140 ms on background, color, box-shadow |
| Toast enter | 160 ms opacity plus 6 px translate up |
| Disclosure chevron | 140 ms rotate |
| Progress line | 2 px, width set to the known fraction, 160 ms when it changes |
| Assistant busy | 2 px line, 40% segment, 1.2 s alternate translate |
| Copy confirm | label swaps to "Copied" for 1.2 s, no toast |

Nothing animates size. `prefers-reduced-motion` turns everything off.

## Element to SwiftUI / AppKit mapping

| Element in the prototype | Implementation |
| --- | --- |
| Window sheet (glass) | `NSVisualEffectView` material `.sidebar`, blending `.behindWindow`, state `.active`; window `titlebarAppearsTransparent`, `.fullSizeContentView`, `isMovableByWindowBackground` |
| Wallpaper showing through | comes free from `.behindWindow`; no code |
| Traffic lights in the sidebar | standard buttons, `titleVisibility = .hidden`, toolbar style `.unifiedCompact`; offset with `NSWindow.standardWindowButton` frames |
| Sidebar column 232 | `HStack` with `.frame(width: 232)`; later `NavigationSplitView` sidebar if the app adopts it |
| Nav icons (back, forward, reload) | `Button` with `.buttonStyle(.borderless)`, SF Symbols `chevron.left`, `chevron.right`, `arrow.clockwise`, 16 pt `.medium` |
| Teach button, recording state | SF Symbols `record.circle` and `record.circle.fill`, `.foregroundStyle(.red)`, count in `.caption.monospacedDigit().weight(.semibold)` |
| Side panel toggle | SF Symbol `sidebar.right`, `.symbolVariant(.fill)` when the panel is open |
| Address pill | `TextField` with `.textFieldStyle(.plain)` inside a `RoundedRectangle(cornerRadius: 8).fill(.quaternary)` plus `.strokeBorder(.separator)`; leading SF Symbol `lock.fill` 12 pt `.tertiary`; shows host only, full URL on focus |
| Tab row | `HStack` 30 pt, `RoundedRectangle(cornerRadius: 6).fill(.quaternary)` when selected, `.fill(.quinary)` on hover via `.onHover`; favicon 16 pt in a 4 pt rounded rect; close `xmark` 12 pt shown on hover |
| New tab row | `Label("New tab", systemImage: "plus")`, `.tertiary` |
| Agent tab | SF Symbol `sparkles`, `.tertiary` idle, `.tint` running; trailing `Text("running").font(.caption).foregroundStyle(.tint)` |
| MCP status | `Circle` 7 pt `.green`, `Text("MCP live").font(.caption.weight(.medium))`, endpoint `.caption2.monospaced()` `.tertiary` |
| Canvas | `WKWebView` host in `.clipShape(RoundedRectangle(cornerRadius: 10))` with `.shadow(color: .black.opacity(0.35), radius: 15, y: 10)`, padding 8 top, right, bottom |
| Load and run progress line | 2 pt `Rectangle` `.tint` at the top of the canvas, width = fraction, `.animation(.easeOut(duration: 0.16))` |
| Repeat suggestion toast | `.overlay(alignment: .bottom)`, `NSVisualEffectView` material `.hudWindow` (dark) or `.popover` (light), `RoundedRectangle(cornerRadius: 12)`, shadow radius 16; SF Symbol `arrow.triangle.2.circlepath` `.tint`; `Button("Save as skill").buttonStyle(.borderedProminent).controlSize(.small)`, `Button("Not now").buttonStyle(.plain)`; `.transition(.opacity.combined(with: .offset(y: 6)))` |
| Picked result outline on page | injected in the `WKContentWorld` picker script: `outline: 1.5px solid #c25a30; border-radius: 4px` plus a mono label chip; same accent hex as the app tint |
| Segmented control (Skills, Teach, Assistant, Settings) | `Picker` with `.pickerStyle(.segmented)` `.controlSize(.small)`; the selected segment is AppKit's own raised knob |
| Section labels ("Steps", "Results", "Connect an agent") | `Text` `.subheadline.weight(.semibold)` `.secondary`; no uppercase |
| Skill list | `LazyVStack` of rows separated by `Divider()`; no `GroupBox`, no card |
| Skill name and id | `.body.weight(.semibold)` and `.caption2.monospaced()` `.tertiary` |
| Badges | `Text` `.caption2.weight(.semibold)` in `Capsule().fill(color.opacity(0.16))`, `.green` verified and success, `.orange` validating |
| Input field in a skill | `LabeledContent` with mono label, `TextField` `.textFieldStyle(.roundedBorder)` `.controlSize(.small)` |
| Run, Watch, delete | `.borderedProminent`, `.bordered`, `Button(role: .destructive)` with `trash` `.borderless` |
| Run record block | `VStack` in `RoundedRectangle(cornerRadius: 8).fill(.quinary)`; outputs as `LabeledContent`; checks with `checkmark` 12 pt `.green` `.bold` |
| Evidence screenshot row | `Button` `.plain` with a 44 by 32 `Image` thumbnail `.clipShape(RoundedRectangle(cornerRadius: 4))`, title `.caption`, URL `.caption2.monospaced()`, trailing `chevron.right` `.tertiary` |
| Steps disclosure | `DisclosureGroup` with a custom label (`chevron.right` rotating 90 degrees, count `.tertiary`, compiler name `.caption2.monospaced()`) |
| Copy MCP config | `Button` `.bordered` with `doc.on.doc`; on tap the label becomes "Copied" `.green` for 1.2 s |
| Recording header | `Circle` 8 pt `.red`, "Recording" `.semibold`, timer `.caption.monospacedDigit()`, origin `.caption` `.tertiary` |
| Steps list | rows 30 pt, index `.caption2.monospaced()` `.tertiary`, verb `.medium`, remove `minus.circle` `.borderless` on hover |
| Picked results | `TextField` mono name, sample `.body`, `Toggle("list").toggleStyle(.checkbox)` `.controlSize(.small)` |
| Pick another result | `Button` `.bordered` with `cursorarrow.rays` |
| Hint field, Save, Discard | `TextField` `.roundedBorder`; `.borderedProminent` and `.plain` |
| Assistant user bubble | `Text` in `RoundedRectangle(cornerRadius: 12)` with a 4 pt bottom-trailing corner via `UnevenRoundedRectangle`, `.fill(.quaternary)`, `frame(maxWidth: .infinity, alignment: .trailing)` |
| Assistant tool line | `HStack` `.caption2.monospaced()`: name `.secondary`, args `.tertiary` truncated `.lineLimit(1)`, duration trailing |
| Assistant answer and citation | `Text` `.body`; citation `HStack` with the verified `Capsule` badge and `.caption` `.tertiary` |
| Busy indicator | 2 pt `Capsule` 120 pt wide with a moving 40 percent segment; replaces `ProgressView` |
| Composer | `Capsule().fill(.quaternary)` 36 pt, `TextField` `.plain`, trailing `Button` 26 pt `Circle().fill(.tint)` with `arrow.up` `.bold` white |
| Settings groups | `Form` with `.formStyle(.grouped)`; each `Section` header `.subheadline.weight(.semibold)`; rows are `LabeledContent` with `TextField` and `SecureField` `.plain` |
| API key valid tag | `Text("valid").font(.caption.weight(.semibold)).foregroundStyle(.green)` as the row's trailing accessory |
| Save and saved time | `.borderedProminent` plus `Text("Saved 14:31").font(.caption).foregroundStyle(.tertiary)` |
| Footnotes | `.caption2` `.tertiary`, `.textSelection(.enabled)` |
| App tint | `Color("Accent")` asset: dark #e2855e, light #b2491f; buttons use the darker fills above through a `ButtonStyle` that reads `colorScheme` |
| Focus rings | system focus ring (accent at 30 percent, 3 pt), do not disable |
| Motion | `.animation(.easeOut(duration: 0.14))` on hover and selection state only; respect `accessibilityReduceMotion` |

## What the prototype shows

- Browse: sidebar, address pill, four tabs plus the agent tab, MCP status, Northwind order lookup, repeat suggestion toast.
- Skills: panel with a run in progress (line at 62 percent), Order status lookup expanded with its input, Run, last run outputs, checks, evidence row and steps; two more skills collapsed; connect an agent.
- Teach: recording header with timer, three steps, two picked results with names and samples, hint, Save and Discard; the page shows the two picked values outlined and labelled; the Teach button in the sidebar turns red with the step count.
- Assistant: a verified skill call, an unscripted page_describe and page_act pass, and a compile in progress.
- Settings: grouped form with the Nebius key, base URL, both model ids, Tavily key and MCP port.
