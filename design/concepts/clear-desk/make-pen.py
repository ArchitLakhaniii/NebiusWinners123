import json, uuid, itertools
_c = itertools.count(1)
def nid(): return 'n%05d' % next(_c)
def node(t, name, **k):
    d = {'type': t, 'id': nid(), 'name': name}; d.update(k); return d
def frame(name, children=None, **k):
    d = node('frame', name, **k)
    if children is not None: d['children'] = children
    return d
def text(name, content, size, weight, fill, **k):
    ff=k.pop('fontFamily','Mona Sans')
    return node('text', name, content=content, fontFamily=ff, fontSize=size, fontWeight=weight, fill=fill, **k)

T = {
 'dark': dict(glass='#3a3f4c', glass2='#2f333d', text='#f0f0f2', text2='#a7aab2', text3='#7a7e88', fill='#4a4f5c', fill2='#555a68', ink='#f5f5f4', onink='#1a1a1c', rule='#4e535f'),
 'light': dict(glass='#dfe2e8', glass2='#d3d7df', text='#1c1c1e', text2='#5c5f66', text3='#8b8e95', fill='#cfd3db', fill2='#c3c7d0', ink='#1c1c1e', onink='#ffffff', rule='#c8ccd4'),
}
NAVY='#1f3a5f'; EMBER='#c4532a'; PAGE='#fbfaf8'; PAGE_T='#1c1c1e'; PAGE_T2='#6f6b66'; PAGE_T3='#a09c95'

def pill(label, c, ink=False, w=None):
    return frame('Pill '+label, [text(label, label, 14, 'medium' if not ink else 'semibold', '#ffffff' if ink else '#1c1c1e')],
        height=34, padding=[0,16,0,16], cornerRadius=17, fill='#1c1c1e' if ink else '#ffffff', alignItems='center', justifyContent='center',
        **({} if ink else {'stroke':'#d9d9d9','strokeWidth':0.5}))

def button(label, c, kind):
    if kind=='ink':
        return frame('Button '+label, [text(label,label,14,'semibold',c['onink'])], height=34, padding=[0,16,0,16], cornerRadius=17, fill=c['ink'], alignItems='center', justifyContent='center')
    return frame('Action '+label, [text(label,label,14,'medium',c['text2'])], height=34, alignItems='center')

def tab(c, letter, color, label, selected=False, meta=None):
    kids=[frame('Favicon', [text('L', letter, 10, 'bold', '#ffffff')], width=20, height=20, cornerRadius=6, fill=color, alignItems='center', justifyContent='center'),
          text('Label', label, 14, 'medium', c['text'] if selected else c['text2'], width='fill_container', textGrowth='fixed-width')]
    if meta: kids.append(text('Meta', meta, 11, 'normal', c['text3']))
    return frame('Tab '+label, kids, width='fill_container', height=36, padding=[0,6,0,8], gap=10, cornerRadius=9, alignItems='center', fill=c['fill'] if selected else None)

def sidebar(c, state):
    lights=frame('Traffic lights',[frame('Close',width=12,height=12,cornerRadius=6,fill='#ff5f57'),frame('Min',width=12,height=12,cornerRadius=6,fill='#febc2e'),frame('Zoom',width=12,height=12,cornerRadius=6,fill='#28c840')],gap=8,alignItems='center')
    nav=frame('Nav',[text('Back','‹',18,'medium',c['text2']),text('Fwd','›',18,'medium',c['text3']),text('Reload','↻',15,'medium',c['text2'])],gap=14,alignItems='center')
    top=frame('Sidebar top',[lights,frame('sp',width='fill_container',height=1),nav],width='fill_container',height=24,alignItems='center')
    addr=frame('Address',[text('Host','northwind.example',14,'medium',c['text']),text('Path','/orders',14,'normal',c['text3'])],width='fill_container',height=36,padding=[0,13,0,13],cornerRadius=11,fill=c['fill'],alignItems='center')
    tabs=frame('Tabs',[tab(c,'N',NAVY,'Order status',True),tab(c,'N',NAVY,'Shipments, week 44'),tab(c,'T','#2f6b4f','Token Factory usage'),tab(c,'G','#3b3b40','Compiler prompt notes'),
        frame('Rule',width='fill_container',height=1,fill=c['rule']),tab(c,'',c['fill2'],'Agent tab',False,'127.0.0.1')],width='fill_container',layout='vertical',gap=3)
    foot=frame('Sidebar foot',[frame('New tab',[text('+','+',17,'medium',c['text2']),text('New tab','New tab',14,'medium',c['text2'],width='fill_container',textGrowth='fixed-width'),text('kbd','⌘T',11,'normal',c['text3'])],width='fill_container',height=36,padding=[0,8,0,8],gap=10,alignItems='center'),
        frame('MCP',[text('MCP line','MCP  3 skills, 14 calls today',12,'medium',c['text2']),text('Endpoint','127.0.0.1:4317/mcp',11,'normal',c['text3'],fontFamily='SF Mono')],width='fill_container',layout='vertical',gap=2,padding=[0,8,0,8])],width='fill_container',layout='vertical',gap=14)
    return frame('Sidebar',[top,frame('g1',height=18,width=1),addr,frame('g2',height=20,width=1),tabs,frame('sp',width=1,height='fill_container'),foot],width=244,height='fill_container',layout='vertical',padding=[14,12,12,14])

def northwind(state):
    teach = state=='teach'
    header=frame('Site header',[text('Mark','Northwind',19,'bold',NAVY,letterSpacing=-0.4),frame('g',width=8,height=1),text('Orders','Orders',14,'medium',PAGE_T),text('Flights','Flights',14,'medium','#8a867f'),text('Inventory','Inventory',14,'medium','#8a867f')],width='fill_container',height=64,padding=[0,48,0,48],gap=26,alignItems='center')
    field=frame('Lookup',[frame('Input',[text('Value','B-77',17,'medium',PAGE_T)],width=378,height=48,padding=[0,16,0,16],cornerRadius=12,fill='#ffffff',stroke='#ddd9d2',strokeWidth=1,alignItems='center'),
        frame('Look up',[text('Look up','Look up',15,'semibold','#ffffff')],height=48,padding=[0,20,0,20],cornerRadius=12,fill=NAVY,alignItems='center',justifyContent='center')],gap=8,alignItems='center')
    def pickwrap(name, inner, tag):
        if not teach: return inner
        return frame('Picked '+name,[inner, frame('Tag',[text('tag',tag,12,'medium','#ffffff',fontFamily='SF Mono')],height=22,padding=[0,8,0,8],cornerRadius=7,fill=EMBER,alignItems='center')],gap=12,alignItems='center',stroke=EMBER,strokeWidth=1.5,cornerRadius=10,padding=[2,6,2,6])
    h1=pickwrap('status', text('Status','In transit',48,'bold',PAGE_T,letterSpacing=-1.4), 'status')
    def seg(label, kind):
        col = NAVY if kind in ('done','now') else '#e8e5df'
        tc = PAGE_T if kind=='now' else (PAGE_T2 if kind=='done' else PAGE_T3)
        return frame('Seg '+label,[frame('Bar',width='fill_container',height=4,cornerRadius=2,fill=col),text('L',label,13,'semibold' if kind=='now' else 'medium',tc)],width='fill_container',layout='vertical',gap=12)
    track=frame('Track',[seg('Ordered','done'),seg('Packed','done'),seg('In transit','now'),seg('Delivered','todo')],width=560,gap=6)
    def fact(k,v,tag=None):
        f=frame('Fact '+k,[text('k',k,13,'normal',PAGE_T2),text('v',v,17,'semibold',PAGE_T,letterSpacing=-0.2)],layout='vertical',gap=4)
        return pickwrap(k,f,tag) if tag else f
    facts=frame('Facts',[fact('Carrier','Northwind Freight'),fact('Estimated delivery','Fri 30 Oct','eta'),fact('Total','$212.00')],gap=48,alignItems='start')
    body=frame('Site body',[text('Label','Order number',13,'medium',PAGE_T2),frame('g',height=8,width=1),field,frame('g',height=56,width=1),text('Eyebrow','Order B-77',14,'medium',PAGE_T2),frame('g',height=6,width=1),h1,frame('g',height=28,width=1),track,frame('g',height=36,width=1),facts,frame('g',height=72,width=1),text('Foot','Demo data changes every minute.',12,'normal',PAGE_T3)],width='fill_container',layout='vertical',padding=[40,48,48,48])
    return frame('Northwind page',[header,body],width='fill_container',height='fill_container',layout='vertical')

def page(c, state):
    pills=[pill('Recording  4',c,True) if state=='teach' else pill('Teach',c), pill('Skills',c, ink=(state!='browse'))]
    actions=frame('Page actions',pills,x=1120 if state=='browse' else 1120-372,y=14,gap=8)  # positioned later
    kids=[northwind(state)]
    card=frame('Page card',kids,width='fill_container',height='fill_container',cornerRadius=12,fill=PAGE,clip=True,layout='vertical')
    stage=frame('Stage',[card],width='fill_container',height='fill_container',padding=[12,12,12,0],layout='vertical')
    return stage

def suggest(c):
    return frame('Suggestion',[text('t','You did this twice on northwind.example.  Save it as a skill?',13,'medium','#ffffff'),frame('g',width=8,height=1),text('Not now','Not now',14,'medium','#b8b8bc'),frame('Save',[text('s','Save as skill',14,'semibold','#1a1a1c')],height=36,padding=[0,16,0,16],cornerRadius=18,fill='#f5f5f4',alignItems='center')],height=52,padding=[0,8,0,20],gap=16,cornerRadius=26,fill='#2a2a2fcc',alignItems='center')

def panel(c, state):
    tabs=frame('Panel tabs',[text(n,n,15,'semibold' if n.lower()==state else 'medium',c['text'] if n.lower()==state else c['text3']) for n in ['Skills','Teach','Assistant','Settings']]+[frame('sp',width='fill_container',height=1),text('x','×',18,'medium',c['text2'])],width='fill_container',height=56,padding=[0,16,0,16],gap=20,alignItems='center')
    h3=lambda s: text('h3',s,13,'semibold',c['text2'])
    inp=lambda v,mono=True,w='fill_container': frame('Input '+v,[text('v',v,13,'normal',c['text'],**({'fontFamily':'SF Mono'} if mono else {}))],width=w,height=34,padding=[0,12,0,12],cornerRadius=10,fill=c['fill'],alignItems='center')
    sub=lambda s: text('sub',s,12,'normal',c['text2'])
    if state=='skills':
        exp=frame('Skill expanded',[text('t','Order status lookup',16,'semibold',c['text'],letterSpacing=-0.2),sub('northwind.example  ·  v2, verified'),frame('g',height=8,width=1),text('l','order',12,'normal',c['text2']),inp('C-311'),frame('g',height=4,width=1),
            frame('Actions',[button('Run',c,'ink'),button('Watch in agent tab',c,'text')],gap=18,alignItems='center'),frame('g',height=2,width=1),frame('Rule',width='fill_container',height=1,fill=c['rule']),frame('g',height=2,width=1),
            text('sum','Succeeded in 2.4 s.  status In transit,  eta Fri 30 Oct.',14,'normal',c['text'],width='fill_container',textGrowth='fixed-width',lineHeight=1.5),text('more','›  4 steps, 2 checks, evidence',13,'normal',c['text2'])],width='fill_container',layout='vertical',gap=6,padding=[12,14,16,14],cornerRadius=12,fill=c['fill'])
        rows=[frame('Skill '+t,[text('t',t,16,'semibold',c['text'],letterSpacing=-0.2),sub(s)],width='fill_container',layout='vertical',gap=3,padding=[12,14,12,14]) for t,s in [('Flight status','northwind.example  ·  v1, verified'),('Inventory count','northwind.example  ·  fixture, not verified')]]
        connect=frame('Connect',[text('p','Any MCP client can call these skills and work any open page.',14,'normal',c['text2'],width='fill_container',textGrowth='fixed-width',lineHeight=1.45),frame('Actions',[button('Copy MCP config',c,'text'),button('Reveal token file',c,'text')],gap=18)],width='fill_container',layout='vertical',gap=4,padding=[16,14,0,14])
        content=[exp]+rows+[connect]
    elif state=='teach':
        step=lambda i,k,v: frame('Step',[text('n',str(i),11,'normal',c['text3']),frame('Code',[text('k',k,11.5,'normal',c['text'],fontFamily='SF Mono')],height=22,padding=[0,6,0,6],cornerRadius=6,fill=c['fill2'],alignItems='center'),text('v',v,13,'normal',c['text'])],height=32,gap=10,alignItems='center')
        pick=lambda k,v: frame('Pick',[inp(k,True,120),text('v',v,13,'normal',c['text2'],width='fill_container',textGrowth='fixed-width'),text('l','☐ list',12,'normal',c['text2'])],width='fill_container',gap=10,alignItems='center')
        content=[sub('Recording from northwind.example/orders'),frame('g',height=12,width=1),h3('Steps'),step(1,'navigate','/orders'),step(2,'fill','Order number  B-77'),step(3,'click','Look up'),step(4,'waitFor','#order-result'),frame('g',height=12,width=1),h3('Results'),pick('status','In transit'),pick('eta','Fri 30 Oct'),button('Pick another result on the page',c,'text'),frame('g',height=8,width=1),text('l','What does this do',12,'normal',c['text2']),inp('Look up order status',False),frame('g',height=6,width=1),frame('Actions',[button('Save skill',c,'ink'),button('Discard',c,'text')],gap=18,alignItems='center'),frame('g',height=6,width=1),text('n','Nemotron compiles the recording, the agent tab replays it, and the skill is kept only if the replay passes its checks.',12,'normal',c['text2'],width='fill_container',textGrowth='fixed-width',lineHeight=1.45)]
    elif state=='assistant':
        user=lambda s: frame('User',[text('u',s,15,'normal',c['text'])],padding=[8,14,8,14],cornerRadius=18,fill=c['fill2'])
        tool=lambda s: frame('Tool',[frame('bar',width=2,height='fill_container',fill=c['fill2']),text('t',s,12,'normal',c['text3'],fontFamily='SF Mono')],gap=10,alignItems='center')
        content=[frame('Chat',[frame('r',[frame('sp',width='fill_container',height=1),user('What is the status of order C-311?')],width='fill_container'),tool('skill_order_status {"order": "C-311"}'),text('a','Order C-311 is in transit with Northwind Freight, estimated delivery Fri 30 Oct. Verified by run 8f3a21c0 in 2.4 s.',15,'normal',c['text'],width='fill_container',textGrowth='fixed-width',lineHeight=1.45),frame('r2',[frame('sp',width='fill_container',height=1),user('And how many units of SKU 4410 are left?')],width='fill_container'),tool('page_describe 127.0.0.1:4318/inventory'),tool('page_act fill #sku "4410", click Look up'),frame('Busy',[frame('track',[frame('seg',width=100,height=2,fill=EMBER,x=96,y=0)],width='fill_container',height=2,fill=c['fill2'],layout='none'),text('b','Reading the inventory page',13,'normal',c['text2'])],width='fill_container',layout='vertical',gap=8)],width='fill_container',height='fill_container',layout='vertical',gap=12),
            frame('Composer',[text('ph','Ask Nemotron',14,'normal',c['text3'],width='fill_container',textGrowth='fixed-width'),frame('Send',[text('↑','↑',16,'bold',c['onink'])],width=32,height=32,cornerRadius=16,fill=c['ink'],alignItems='center',justifyContent='center')],width='fill_container',height=44,padding=[0,6,0,18],cornerRadius=22,fill=c['fill'],alignItems='center')]
    else:
        row=lambda k,v: frame('Row '+k,[text('k',k,13,'normal',c['text2'],width=92,textGrowth='fixed-width'),inp(v)],width='fill_container',gap=12,alignItems='center')
        content=[h3('Nemotron on Nebius Token Factory'),row('API key','••••••••••••••••'),row('Base URL','https://api.tokenfactory.nebius.com/v1/'),row('Compiler','nvidia/nemotron-3-super-120b-a12b'),row('Assistant','nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B'),frame('g',height=12,width=1),h3('Optional'),row('Tavily key','Enables web_search'),row('MCP port','4317'),frame('g',height=12,width=1),frame('Actions',[button('Save',c,'ink')],gap=18),frame('g',height=6,width=1),text('n','Stored in ~/Library/Application Support/BrowserSkills/settings.json with mode 0600. NEBIUS_API_KEY in the environment overrides it.',12,'normal',c['text2'],width='fill_container',textGrowth='fixed-width',lineHeight=1.45)]
    pane=frame('Pane',content,width='fill_container',height='fill_container',layout='vertical',gap=6,padding=[4,20,20,20])
    return frame('Panel',[tabs,pane],width=372,height='fill_container',layout='vertical')

def window(theme, state, x, y):
    c=T[theme]
    kids=[sidebar(c,state),page(c,state)]
    if state!='browse': kids.append(panel(c,state))
    win=frame('Window',kids,width=1400,height=860,cornerRadius=14,fill=c['glass'],clip=True,layout='horizontal')
    overlay=[]
    px = 1400-12-16 - (372 if state!='browse' else 0)
    pills=frame('Page actions',[pill('Recording  4',c,True) if state=='teach' else pill('Teach',c), pill('Skills',c, ink=(state!='browse'))],gap=8,layout='horizontal')
    overlay.append(pills)
    if state=='browse': overlay.append(suggest(c))
    desk=frame(f'{state.title()} · {theme}',[win]+overlay,x=x,y=y,width=1440,height=900,fill='#5a6378' if theme=='dark' else '#aeb6c6',layout='none')
    win['x']=20; win['y']=20
    pills['x']=20+px-200; pills['y']=20+12+14
    if state=='browse':
        overlay[-1]['x']=20+244+ (1400-244-12)//2 - 330; overlay[-1]['y']=20+860-12-20-52
    return desk

children=[]
for ti,theme in enumerate(['dark','light']):
    for si,state in enumerate(['browse','skills','teach','assistant','settings']):
        children.append(window(theme,state, si*1540, ti*1000))
doc={'version':'2.14','children':children,'variables':{k:{'type':'color','value':v} for k,v in {'navy':NAVY,'ember':EMBER,'page':PAGE}.items()},'fileToken':str(uuid.uuid4())}
# strip None fills
def clean(n):
    for k in [k for k,v in n.items() if v is None]: del n[k]
    for ch in n.get('children',[]): clean(ch)
for ch in children: clean(ch)
out='/home/ubuntu/repos/NebiusWinners123/design/concepts/clear-desk/clear-desk.pen'
json.dump(doc,open(out,'w'),indent=1)
print(out, len(json.dumps(doc))//1024,'KB')
