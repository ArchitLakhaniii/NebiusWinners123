import json, itertools
_n = itertools.count(1)
def nid(): return f"bs{next(_n)}"
FONT = "Geist"; MONO = "Geist Mono"
# dark theme
D = dict(BG="#15171B", SB="#FFFFFF08", HI="#FFFFFF0F", HI2="#FFFFFF1A", LINE="#FFFFFF14", T1="#ECEEF1", T2="#9BA3AE", T3="#6B7380",
         ACC="#14B8A6", ACC_DIM="#14B8A61F", RED="#F0564A", PANEL="#1C1F25", ONACC="#07201C")
L = dict(BG="#E9E7E2", SB="#FFFFFF66", HI="#0000000A", HI2="#00000012", LINE="#00000014", T1="#1A1C20", T2="#6B6F76", T3="#9A9EA5",
         ACC="#0F9E8E", ACC_DIM="#0F9E8E1A", RED="#D9463B", PANEL="#F7F6F3", ONACC="#FFFFFF")
C = D
PAGE = "#FAFAF9"; P1 = "#16181D"; P2 = "#5F6672"; P3 = "#9AA1AB"; PLINE = "#E6E7EA"; PFILL = "#F1F2F4"

def node(t, name, **k):
    d = {"type": t, "id": nid(), "name": name}; d.update(k); return d
def text(name, s, size=13, color=None, weight="400", **k):
    return node("text", name, content=s, fontFamily=k.pop("font", FONT), fontSize=size, fontWeight=weight, fill=color or C["T1"], **k)
def icon(name, ic, size=15, color=None): return node("icon", name, icon=ic, library="lucide", width=size, height=size, fill=color or C["T2"])
def frame(name, children, **k):
    d = node("frame", name, children=children); d.update(k); return d
def row(name, children, gap=8, **k):
    k.setdefault("alignItems", "center"); return frame(name, children, layout="horizontal", gap=gap, **k)
def col(name, children, gap=8, **k): return frame(name, children, layout="vertical", gap=gap, **k)
def spacer(w=None, h=None):
    d = node("frame", "Spacer")
    if w is None and h is None: d["width"] = "fill_container"; d["height"] = 1
    if w is not None: d["width"] = w; d["height"] = 1
    if h is not None: d["height"] = h; d["width"] = 1
    return d
def fill_spacer(): d = node("frame", "Spacer"); d["width"] = "fill_container"; d["height"] = 1; return d
def vfill(): d = node("frame", "Spacer"); d["height"] = "fill_container"; d["width"] = 1; return d
def dot(name, color, size=7): return node("ellipse", name, width=size, height=size, fill=color)
def hair(w="fill_container"): return node("frame", "Hairline", width=w, height=1, fill=C["LINE"])
def caption(s): return text("Caption " + s, s, 11, C["T3"], "600", letterSpacing=0.7)

def pill(label, primary=False, ic=None, danger=False, small=False):
    fg = C["ONACC"] if primary else (C["RED"] if danger else C["T1"])
    kids = []
    if ic: kids.append(icon(label + " icon", ic, 12 if small else 13, fg))
    kids.append(text(label, label, 11.5 if small else 12.5, fg, "500"))
    return row("Pill " + label, kids, gap=6, padding=[5, 9] if small else [7, 12], cornerRadius=8,
               fill=C["ACC"] if primary else C["HI2"])

def tab_row(title, ic="globe", active=False, muted=False):
    c = C["T1"] if active else (C["T3"] if muted else C["T2"])
    kids = [icon("Favicon", ic, 14, c), text("Title", title, 12.5, c, "500" if active else "400")]
    if active: kids += [fill_spacer(), icon("Close", "x", 12, C["T3"])]
    return row("Tab " + title, kids, gap=9, padding=[6, 10], cornerRadius=8, width="fill_container", height=30,
               fill=C["HI2"] if active else "#00000000")

def fav_tile(ic):
    return frame("Favorite " + ic, [icon("Icon", ic, 16, C["T1"])], layout="horizontal", alignItems="center", justifyContent="center",
                 width="fill_container", height=34, cornerRadius=8, fill=C["HI"])

def sidebar(recording=False, light=False):
    lights = row("Window controls", [dot("Close", "#FF5F57", 12), dot("Min", "#FEBC2E", 12), dot("Zoom", "#28C840", 12), fill_spacer(),
                                     icon("Panel toggle", "panel-right", 15, C["T3"])], gap=8, padding=[16, 14, 8, 16], width="fill_container")
    nav = row("Nav", [icon("Back", "chevron-left", 16, C["T1"]), icon("Forward", "chevron-right", 16, C["T3"]), icon("Reload", "rotate-cw", 13, C["T2"]),
                      fill_spacer(), icon("New tab", "plus", 15, C["T2"])], gap=12, padding=[0, 14, 4, 14], width="fill_container")
    address = row("Address", [icon("Lock", "lock", 11, C["T2"]), text("URL", "northwind.local/orders", 12.5, C["T1"], "500")],
                  gap=8, padding=[8, 12], cornerRadius=9, width="fill_container", height=32, fill=C["HI"])
    if recording:
        teach = row("Recording", [dot("Rec", C["RED"], 8), text("Rec label", "Recording", 12.5, C["T1"], "500"), fill_spacer(), text("Steps", "3 steps", 11.5, C["T2"])],
                    gap=8, padding=[7, 12], cornerRadius=9, width="fill_container", height=32, fill=C["RED"] + "1A")
    else:
        teach = row("Teach", [icon("Teach icon", "circle-dot", 13, C["T2"]), text("Teach label", "Teach a skill", 12.5, C["T2"], "500"), fill_spacer(), text("Shortcut", "⇧⌘R", 11, C["T3"])],
                    gap=8, padding=[7, 12], cornerRadius=9, width="fill_container", height=32)
    favs = col("Favorites", [row("Fav row 1", [fav_tile("mail"), fav_tile("calendar"), fav_tile("git-branch")], gap=6, width="fill_container"),
                             row("Fav row 2", [fav_tile("file-text"), fav_tile("hash"), fav_tile("book-open")], gap=6, width="fill_container")], gap=6, width="fill_container")
    tabs = col("Today", [caption("TODAY"),
                         tab_row("Order status", "package", active=True), tab_row("Nebius Token Factory", "cpu"), tab_row("Nook on GitHub", "git-branch"), tab_row("Flight status", "plane", muted=True)],
               gap=3, width="fill_container")
    agent = col("Agent", [caption("AGENT"),
                          row("Agent tab", [dot("Live", C["ACC"], 7), text("Agent title", "northwind.local", 12.5, C["T2"]), fill_spacer(), text("Watch", "Watch", 11.5, C["ACC"], "500")],
                              gap=9, padding=[6, 10], cornerRadius=8, width="fill_container", height=30)], gap=3, width="fill_container")
    mcp = row("MCP", [dot("MCP dot", C["ACC"], 7), text("MCP label", "MCP  127.0.0.1:4317", 11.5, C["T2"]), fill_spacer(), text("Calls", "12 calls", 11.5, C["T3"])],
              gap=8, padding=[8, 12], cornerRadius=8, width="fill_container", height=30)
    body = col("Sidebar body", [address, teach, spacer(h=2), favs, spacer(h=6), tabs, spacer(h=2), agent, vfill(), hair(), mcp],
               gap=8, padding=[6, 10, 10, 10], width="fill_container", height="fill_container")
    return frame("Sidebar", [lights, nav, body], layout="vertical", width=232, height="fill_container", fill=C["SB"],
                 effect={"type": "background_blur", "radius": 40})

# Northwind portal page (light content inside the card)
def pfield(label, value, w=300, focus=False):
    return col("Field " + label, [text("Label", label, 12, P2, "500"),
        row("Input", [text("Value", value, 14, P1)], padding=[9, 12], cornerRadius=8, width=w, height=38, fill="#FFFFFF",
            stroke=C["ACC"] if focus else "#D9DBDF", strokeWidth=1.5 if focus else 1)], gap=6)
def kv(k, v, strong=False, highlight=False):
    return row("KV " + k, [text("K", k, 13, P2, width=140), text("V", v, 13, C["ACC"] if highlight else P1, "600" if strong else "400")], gap=16, width="fill_container", height=24)
def stage(label, done, last=False):
    kids = [dot("Stage dot", C["ACC"] if done else "#D9DBDF", 10), text("Stage", label, 12, P1 if done else P3, "500" if done else "400")]
    return col("Stage " + label, kids, gap=8, alignItems="center", width=120)
def page(light=False, highlight=False):
    topbar = row("Portal nav", [text("Brand", "Northwind", 15, P1, "700"), spacer(w=20),
                                text("Nav1", "Orders", 13, P1, "500"), text("Nav2", "Flights", 13, P2), text("Nav3", "Inventory", 13, P2), fill_spacer(),
                                row("Account", [dot("Avatar", "#CBD0D8", 22), text("User", "Priya N.", 13, P2)], gap=8)],
                 gap=22, padding=[16, 40], width="fill_container", height=56, fill="#FFFFFF", stroke=PLINE, strokeWidth=1)
    head = col("Head", [text("H1", "Order status", 26, P1, "600", letterSpacing=-0.4),
                        text("Sub", "Enter an order number to see where it is right now.", 14, P2)], gap=6)
    form = row("Lookup", [pfield("Order number", "A-1042", 300), col("Btn wrap", [spacer(h=22), row("Look up", [text("Look up", "Look up", 13.5, "#FFFFFF", "600")], padding=[10, 18], cornerRadius=8, height=38, fill=P1)], gap=0)], gap=12, alignItems="flex-end")
    stages = row("Timeline", [stage("Placed", True), stage("Packed", True), stage("Shipped", True), stage("Delivered", True, True)], gap=0, alignItems="flex-start")
    result = col("Result card", [
        row("Result head", [text("Order", "Order A-1042", 16, P1, "600"), fill_spacer(),
                            row("Status badge", [dot("S", C["ACC"], 7), text("Status", "Delivered", 12.5, "#0B6B61", "600")], gap=7, padding=[4, 10], cornerRadius=999, fill="#DCF5F1")], width="fill_container"),
        hair_p(), stages, hair_p(),
        kv("Carrier", "Pacific Freight"), kv("ETA", "Mon, Oct 27, by 9 pm", highlight=highlight), kv("Last scan", "Oakland, CA  5:12 pm"), kv("Items", "3 items, 2.1 kg"),
    ], gap=14, padding=[20, 24], cornerRadius=12, width=680, fill="#FFFFFF", stroke=PLINE, strokeWidth=1)
    body = col("Portal body", [head, spacer(h=6), form, spacer(h=10), result], gap=16, padding=[40, 40], width="fill_container")
    return frame("Page", [topbar, body], layout="vertical", width="fill_container", height="fill_container", cornerRadius=10, clip=True,
                 fill=PAGE, stroke=C["LINE"], strokeWidth=1)
def hair_p(): return node("frame", "Hairline", width="fill_container", height=1, fill=PLINE)

def toast():
    return row("Repeat toast", [
        frame("Toast icon", [icon("Repeat", "repeat", 15, C["ACC"])], layout="horizontal", alignItems="center", justifyContent="center", width=32, height=32, cornerRadius=8, fill=C["ACC_DIM"]),
        col("Toast text", [text("Toast title", "You did this twice on northwind.local", 13, C["T1"], "600"),
                           text("Toast sub", "Look up an order number and read its status and ETA.", 12, C["T2"])], gap=3),
        spacer(w=10), pill("Save as skill", primary=True), text("Not now", "Not now", 12.5, C["T2"], "500")],
        gap=12, padding=[12, 14, 12, 12], cornerRadius=12, fill=C["PANEL"] + "F0", stroke=C["LINE"], strokeWidth=1,
        effect={"type": "background_blur", "radius": 30})

def panel_tabs(active):
    kids = []
    for name in ["Skills", "Assistant", "Settings"]:
        on = name == active
        kids.append(col("Tab " + name, [text("Tab", name, 13, C["T1"] if on else C["T3"], "600" if on else "500"),
                                        node("frame", "Underline", width="fill_container", height=2, cornerRadius=1, fill=C["T1"] if on else "#00000000")], gap=6))
    return row("Panel tabs", kids + [fill_spacer(), icon("Close panel", "x", 14, C["T3"])], gap=18, padding=[18, 16, 0, 16], width="fill_container")

def skill_row(title, tool, status, color, meta):
    return row("Skill " + title, [col("Skill text", [text("Title", title, 13, C["T1"], "500"), text("Tool", tool, 11.5, C["T3"], font=MONO)], gap=3), fill_spacer(),
                                  row("Status", [dot("S", color, 7), text("Status", status, 11.5, C["T2"])], gap=6), text("Meta", meta, 11.5, C["T3"])],
               gap=12, padding=[10, 12], cornerRadius=9, width="fill_container")
def skill_open():
    head = row("Head", [col("Skill text", [text("Title", "Order status", 14, C["T1"], "600"), text("Tool", "skill_order_status", 11.5, C["T3"], font=MONO)], gap=3), fill_spacer(),
                        row("Status", [dot("S", C["ACC"], 7), text("Status", "Verified", 11.5, C["T2"])], gap=6)], gap=12, width="fill_container")
    inp = row("Input", [text("Label", "order_number", 12, C["T2"], font=MONO), fill_spacer(), text("Value", "A-1042", 12.5, C["T1"])],
              padding=[8, 12], cornerRadius=8, width="fill_container", height=34, fill=C["HI"], stroke=C["LINE"], strokeWidth=1)
    acts = row("Actions", [pill("Run", True, "play"), pill("Watch", False, "eye"), fill_spacer(), text("Time", "1.8 s", 11.5, C["T3"]), text("Shots", "Screenshot", 11.5, C["ACC"], "500")], gap=8, width="fill_container")
    outs = col("Outputs", [caption("LAST RESULT"),
                           row("O1", [text("K", "status", 12, C["T2"], font=MONO, width=110), text("V", "Delivered", 12.5, C["T1"], "500")], gap=12),
                           row("O2", [text("K", "eta", 12, C["T2"], font=MONO, width=110), text("V", "Mon, Oct 27, by 9 pm", 12.5, C["T1"], "500")], gap=12),
                           row("O3", [text("K", "carrier", 12, C["T2"], font=MONO, width=110), text("V", "Pacific Freight", 12.5, C["T1"], "500")], gap=12)], gap=8, width="fill_container")
    return col("Skill open", [head, inp, acts, hair(), outs], gap=12, padding=[14, 12], cornerRadius=10, width="fill_container", fill=C["HI"], stroke=C["LINE"], strokeWidth=1)
def skills_panel():
    lst = col("Skill list", [skill_open(), skill_row("Flight status", "skill_flight_status", "Verified", C["ACC"], "4 runs"),
                             skill_row("Inventory search", "skill_inventory_search", "Verified", C["ACC"], "2 runs"),
                             skill_row("Expense export", "skill_expense_export", "Needs login", "#E0A33A", "")], gap=4, padding=[8, 8], width="fill_container")
    foot = col("Connect", [hair(), row("Connect row", [col("Connect text", [text("T", "Connect an agent", 12.5, C["T1"], "500"), text("S", "Hermes, Claude Code, Cursor", 11.5, C["T3"])], gap=2), fill_spacer(), pill("Copy config", False, "copy", small=True)], gap=8, width="fill_container", padding=[12, 16, 16, 16])], gap=0, width="fill_container")
    return col("Skills panel", [panel_tabs("Skills"), row("Count", [text("N", "4 skills", 12, C["T2"]), fill_spacer(), pill("Teach", False, "plus", small=True)], padding=[10, 16, 2, 16], width="fill_container"), lst, vfill(), foot], gap=4, width="fill_container", height="fill_container")

def step(n, label, detail):
    return row("Step " + str(n), [frame("Num", [text("N", str(n), 11, C["T2"], "600")], layout="horizontal", alignItems="center", justifyContent="center", width=22, height=22, cornerRadius=6, fill=C["HI2"]),
                                  col("Step text", [text("L", label, 12.5, C["T1"], "500"), text("D", detail, 11.5, C["T3"], font=MONO)], gap=2)], gap=10, padding=[6, 12], width="fill_container")
def teach_panel():
    head = row("Teach head", [row("Rec", [dot("Rec", C["RED"], 8), text("Recording", "Recording", 13, C["T1"], "600")], gap=8), fill_spacer(), text("Hint", "Use the site like you normally do", 11.5, C["T3"])], padding=[18, 16, 6, 16], width="fill_container")
    steps = col("Steps", [caption("STEPS"), step(1, "Open northwind.local/orders", "navigate"), step(2, "Type A-1042 into Order number", "fill  #order"), step(3, "Click Look up", "click  button.primary")], gap=4, padding=[8, 4], width="fill_container")
    res = col("Results", [caption("RESULTS"),
                          row("R1", [dot("R", C["ACC"], 7), text("K", "status", 12.5, C["T1"], "500", font=MONO), fill_spacer(), text("V", "Delivered", 12, C["T2"])], gap=10, padding=[6, 12], width="fill_container"),
                          row("R2", [dot("R", C["ACC"], 7), text("K", "eta", 12.5, C["T1"], "500", font=MONO), fill_spacer(), text("V", "Mon, Oct 27, by 9 pm", 12, C["T2"])], gap=10, padding=[6, 12], width="fill_container"),
                          row("Pick", [pill("Pick a result on the page", False, "crosshair")], padding=[4, 12])], gap=4, padding=[8, 4], width="fill_container")
    name = col("Name", [caption("NAME"), row("Name field", [text("V", "Order status", 13, C["T1"])], padding=[8, 12], cornerRadius=8, width="fill_container", height=34, fill=C["HI"], stroke=C["LINE"], strokeWidth=1)], gap=6, padding=[8, 16], width="fill_container")
    foot = col("Foot", [hair(), row("Buttons", [pill("Save skill", True), text("Discard", "Discard", 12.5, C["T2"], "500"), fill_spacer(), text("Note", "Replayed once before it is saved", 11.5, C["T3"])], gap=14, padding=[12, 16, 16, 16], width="fill_container")], gap=0, width="fill_container")
    return col("Teach panel", [head, steps, res, name, vfill(), foot], gap=4, width="fill_container", height="fill_container")

def bubble(s, me=False):
    if me:
        return row("Me", [fill_spacer(), frame("Bubble", [text("T", s, 13, C["T1"], width=220)], padding=[9, 12], cornerRadius=12, fill=C["HI2"])], gap=0, width="fill_container", padding=[0, 16])
    return frame("Assistant text", [text("T", s, 13, C["T1"], width=280)], padding=[0, 16])
def toolline(s): return row("Tool", [icon("Tool icon", "terminal", 12, C["T3"]), text("T", s, 11.5, C["T3"], font=MONO)], gap=8, padding=[2, 16])
def assistant_panel():
    msgs = col("Messages", [bubble("Where is order A-1042?", True), toolline("skill_order_status  order_number=A-1042"),
                            bubble("Delivered. Pacific Freight dropped it in Oakland at 5:12 pm, so it should be with you by 9 pm tonight."),
                            bubble("And B-2210?", True), toolline("skill_order_status  order_number=B-2210"), toolline("page_read  northwind.local/orders"),
                            bubble("Still in transit. Last scan was Reno, NV this morning; ETA is Wednesday.")], gap=12, padding=[12, 0], width="fill_container")
    model = row("Model", [dot("M", C["ACC"], 6), text("Model", "Nemotron Nano on Nebius", 11.5, C["T3"]), fill_spacer(), text("Lat", "0.9 s", 11.5, C["T3"])], gap=8, padding=[0, 16, 6, 16], width="fill_container")
    inp = row("Composer", [text("Ph", "Ask about this page or run a skill", 13, C["T3"]), fill_spacer(), frame("Send", [icon("Up", "arrow-up", 14, C["ONACC"])], layout="horizontal", alignItems="center", justifyContent="center", width=26, height=26, cornerRadius=13, fill=C["ACC"])],
              gap=8, padding=[7, 7, 7, 14], cornerRadius=12, width="fill_container", height=42, fill=C["HI"], stroke=C["LINE"], strokeWidth=1)
    return col("Assistant panel", [panel_tabs("Assistant"), msgs, vfill(), model, frame("Composer wrap", [inp], padding=[0, 12, 12, 12], width="fill_container")], gap=4, width="fill_container", height="fill_container")

def setting(label, value, mono=False, sub=None):
    kids = [text("L", label, 12.5, C["T1"], "500")]
    if sub: kids.append(text("S", sub, 11.5, C["T3"]))
    return row("Setting " + label, [col("Lbl", kids, gap=2), fill_spacer(), row("Val", [text("V", value, 12.5, C["T2"], font=MONO if mono else FONT)], padding=[6, 10], cornerRadius=7, fill=C["HI"], stroke=C["LINE"], strokeWidth=1)],
               gap=12, padding=[8, 16], width="fill_container")
def settings_panel():
    prov = col("Provider", [caption("MODELS"), setting("Nebius API key", "sk-nb  ••••  7f2a", True, "Stored in the keychain"), setting("Compiler", "nemotron-3-super-120b", True), setting("Assistant", "nemotron-3-nano-30b", True)], gap=2, padding=[8, 0], width="fill_container")
    mcp = col("MCP", [caption("MCP"), setting("Endpoint", "127.0.0.1:4317/mcp", True, "Loopback only, bearer token"), row("Tok", [pill("Copy token", False, "key", small=True), pill("Copy Hermes config", False, "copy", small=True)], gap=8, padding=[6, 16])], gap=2, padding=[8, 0], width="fill_container")
    priv = col("Privacy", [caption("PRIVACY"), row("P1", [text("T", "Passwords and one-time codes are never recorded.", 12, C["T2"], width=280)], padding=[6, 16]),
                           row("P2", [text("T", "Skills run in a hidden tab with your normal logins.", 12, C["T2"], width=280)], padding=[2, 16])], gap=2, padding=[8, 0], width="fill_container")
    return col("Settings panel", [panel_tabs("Settings"), prov, mcp, priv], gap=10, width="fill_container", height="fill_container")

def screen(name, x, y=0, panel=None, recording=False, show_toast=False, light=False, highlight=False):
    global C
    C = L if light else D
    kids = [sidebar(recording, light)]
    pg = page(light, highlight)
    main_kids = [frame("Page wrap", [pg], layout="vertical", alignItems="stretch", padding=[10, 10, 10, 0], width="fill_container", height="fill_container")]
    if panel is not None:
        main_kids.append(frame("Panel", [panel()], width=328, height="fill_container", cornerRadius=10, clip=True, fill=C["SB"], stroke=C["LINE"], strokeWidth=1, effect={"type": "background_blur", "radius": 40}))
        main_kids = [main_kids[0], frame("Panel wrap", [main_kids[1]], layout="vertical", alignItems="stretch", padding=[10, 10, 10, 0], height="fill_container")]
    kids.append(row("Main", main_kids, gap=0, width="fill_container", height="fill_container", alignItems="stretch"))
    root_children = [row("Window", kids, gap=0, width=1440, height=900, alignItems="stretch")]
    if show_toast:
        t = toast(); t["x"] = 232 + 20; t["y"] = 820
        root_children.append(t)
    root = frame(name, root_children, x=x, y=y, width=1440, height=900, cornerRadius=12, clip=True, fill=C["BG"])
    return root

doc = {"version": "2.14", "variables": {}, "fileToken": "7a3c0e1e-5b7e-4b36-9b8e-browserskills0", "children": [
    screen("1 Browse, repeat suggestion", 0, show_toast=True),
    screen("2 Skills", 1540, panel=skills_panel, highlight=True),
    screen("3 Teach", 3080, panel=teach_panel, recording=True),
    screen("4 Assistant", 4620, panel=assistant_panel),
    screen("5 Settings", 6160, panel=settings_panel),
    screen("6 Browse, light", 0, 1000, show_toast=True, light=True),
]}
json.dump(doc, open("browserskills.pen", "w"), indent=1)
print("ok", len(json.dumps(doc)))
