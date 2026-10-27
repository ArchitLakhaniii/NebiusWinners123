import json, sys, html
d = json.load(open(sys.argv[1]))
def css_color(c):
    if not c or c == "#00000000": return "transparent"
    if len(c) == 9: 
        r,g,b,a = int(c[1:3],16),int(c[3:5],16),int(c[5:7],16),int(c[7:9],16)/255
        return f"rgba({r},{g},{b},{a:.3f})"
    return c
def dim(v):
    if v is None: return None
    if v == "fill_container": return "FILL"
    return f"{v}px"
def pad(p):
    if p is None: return "0"
    if isinstance(p,(int,float)): return f"{p}px"
    return " ".join(f"{x}px" for x in p)
def render(n, parent_layout=None, abs_root=False):
    t = n["type"]; st = []
    w, h = dim(n.get("width")), dim(n.get("height"))
    if "x" in n and abs_root: st.append(f"position:absolute;left:{n['x']}px;top:{n['y']}px")
    if w == "FILL": st.append("flex:1 1 0;min-width:0" if parent_layout == "horizontal" else "align-self:stretch;width:auto")
    elif w: st.append(f"width:{w};flex:0 0 auto")
    if h == "FILL": st.append("flex:1 1 0;min-height:0" if parent_layout == "vertical" else "align-self:stretch")
    elif h: st.append(f"height:{h}")
    if n.get("cornerRadius") is not None: st.append(f"border-radius:{n['cornerRadius']}px")
    if n.get("fill") and t != "text" and t != "icon": st.append(f"background:{css_color(n['fill'])}")
    if n.get("stroke") and n.get("strokeWidth"): st.append(f"box-shadow:inset 0 0 0 {n['strokeWidth']}px {css_color(n['stroke'])}")
    if n.get("clip"): st.append("overflow:hidden")
    eff = n.get("effect")
    if eff and eff.get("type") == "background_blur": st.append(f"backdrop-filter:blur({eff['radius']}px)")
    if t == "text":
        st.append(f"font-family:'{n.get('fontFamily','Geist')}',Inter,system-ui;font-size:{n['fontSize']}px;font-weight:{n.get('fontWeight','400')};color:{css_color(n['fill'])};line-height:1.3;white-space:nowrap")
        if n.get("letterSpacing"): st.append(f"letter-spacing:{n['letterSpacing']}px")
        if w and w != "FILL": st.append("white-space:normal;overflow-wrap:anywhere")
        return f'<div style="{";".join(st)}">{html.escape(n["content"])}</div>'
    if t == "icon":
        st.append(f"color:{css_color(n['fill'])};display:flex;flex:0 0 auto")
        return f'<div style="{";".join(st)}"><i data-lucide="{n["icon"]}" style="width:{n["width"]}px;height:{n["height"]}px"></i></div>'
    if t == "ellipse":
        st.append("border-radius:50%;flex:0 0 auto"); return f'<div style="{";".join(st)}"></div>'
    lay = n.get("layout")
    if lay:
        st.append(f"display:flex;flex-direction:{'row' if lay=='horizontal' else 'column'};gap:{n.get('gap',0)}px;padding:{pad(n.get('padding'))}")
        ai = n.get("alignItems", "flex-start" if lay=="vertical" else "center"); st.append(f"align-items:{ai}")
        if n.get("justifyContent"): st.append(f"justify-content:{n['justifyContent']}")
    else:
        st.append("position:relative;display:block;padding:" + pad(n.get("padding")))
    kids = "".join(render(c, lay, abs_root=(lay is None)) for c in n.get("children", []))
    return f'<div style="{";".join(st)}" title="{html.escape(n["name"])}">{kids}</div>'
out = ['<html><head><meta charset="utf-8"><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&family=Geist+Mono&display=swap"><style>body{margin:0;background:#2A2D33;}*{box-sizing:border-box}</style></head><body>']
for s in d["children"]:
    s = dict(s); x, y = s.pop("x", 0), s.pop("y", 0)
    out.append(f'<div style="position:absolute;left:{x+40}px;top:{y+40}px">{render(s)}</div>')
out.append('<script src="https://unpkg.com/lucide@latest"></script><script>lucide.createIcons({attrs:{"stroke-width":1.75}});</script></body></html>')
open(sys.argv[2], "w").write("\n".join(out)); print("wrote", sys.argv[2])
