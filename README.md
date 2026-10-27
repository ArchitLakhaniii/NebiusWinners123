# BrowserSkills

A lightweight, AI-native macOS browser that **caches the workflows you repeat**, replays them on demand,
and **turns any webpage into MCP tools**, so agents use the web the way you already do, with your logins,
through one verified tool layer.

Built for the Nebius x NVIDIA Global AI Hackathon (Personal AI track). Nemotron on Nebius Token Factory
compiles demonstrations into workflows and drives the built-in assistant. Browser core adapted from
[Nook](https://github.com/nook-browser/Nook) (GPL-3.0).

## What it does

1. **Notices repeats.** Browse normally. When you do the same procedure on a site twice (same fields and
   buttons, different values), BrowserSkills offers to save it as a skill. Or press **Teach** (⇧⌘R) and do it once.
2. **Compiles with Nemotron.** You click the result fields on the page. `nvidia/nemotron-3-super-120b-a12b`
   turns the recording into a constrained workflow: typed inputs, a fixed step vocabulary
   (`navigate / fill / select / click / press / waitFor`), outputs and checks. No generated code ever runs.
3. **Verifies before trusting.** The workflow is validated against what was actually recorded (same origin,
   only observed selectors, no secret fields), then replayed in the browser's agent tab. It is promoted to a
   runnable, versioned skill only if the replay's outputs pass their checks.
4. **Exposes everything over MCP.** The app serves MCP on `http://127.0.0.1:4317/mcp` (bearer token):
   - `skill_<name>`: one tool per verified skill, typed from its inputs, returning outputs + run evidence;
   - `browser_open`, `page_describe`, `page_act`, `page_read`: make **any** page usable by an agent before
     it has a skill (forms, fields and actions become refs to act on);
   - `skills_list`, `run_get`, and `web_search` (Tavily, optional).
5. **Assistant.** A side panel where `nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B` calls the same tools.

## Run it

Requires macOS 15+ on Apple Silicon, Xcode 16+ (Swift 6), and Node 18+.

```bash
scripts/build.sh            # builds build/BrowserSkills.app
scripts/demo.sh             # starts the demo portal on :4318 and opens the app
export NEBIUS_API_KEY=...   # or paste it in Settings; without it the compiler runs in labeled fixture mode
scripts/doctor.sh           # checks toolchain, portal, MCP server and the Nebius key
scripts/reset.sh            # clears skills/runs (keeps settings and MCP token)
cd app && swift test        # unit tests
```

### Demo (2 minutes)

1. In the app, open **Order status** on the demo portal, look up `A-1042`, then look up `B-77`.
   A banner says *"You've done this 2× on 127.0.0.1"* → **Save as skill** → click the *Status* and *ETA*
   values → **Save skill**. Watch the agent tab replay and verify it.
2. Connect an agent: **Skills → Copy MCP config**, paste into Claude Code / Cursor, or use the stdio bridge:
   ```bash
   claude mcp add --transport http browserskills http://127.0.0.1:4317/mcp \
     --header "Authorization: Bearer $(cat ~/Library/Application\ Support/BrowserSkills/mcp-token)"
   # stdio clients (Hermes): node mcp-stdio/browserskills-mcp.mjs  (see mcp-stdio/hermes.example.yaml)
   ```
3. Ask the agent "what's the status of order C-311?" → it calls `skill_...` and gets verified outputs.
   Ask it about a page with no skill → it uses `page_describe` / `page_act`.

## Layout

```
app/                     SwiftPM macOS app (SwiftUI + WKWebView)
  Browser/               tabs, isolated-world page scripts (recorder, picker, page tools, executor steps)
  Skills/                workflow schema + validation, recorder + repeat detection, SQLite store, executor
  AI/                    Nemotron provider (OpenAI-compatible), compiler, assistant
  MCP/                   Streamable HTTP MCP server + shared tool registry
  UI/                    sidebar, address bar, Skills / Teach / Assistant / Settings panels
demo-portal/             zero-dependency Node site with three lookups whose data changes every minute
mcp-stdio/               stdio bridge for MCP clients without HTTP transport
scripts/                 build, demo, doctor, reset
```

## Safety model

- Page scripts run in an isolated `WKContentWorld`; pages cannot call them or forge recorded actions.
- Password/OTP/card fields are never recorded, never become inputs, and are flagged as secret to agents.
- Workflows can only navigate within their recorded origin and only touch selectors seen while recording.
- Agents drive a separate agent tab, never your open tabs. The agent tab shares your website data store, so
  cookies stay in the browser and are never returned to callers.
- MCP binds to 127.0.0.1 only, requires a bearer token (0600 file), and rejects non-loopback `Origin`s.
- Runs are serialized, deduplicated for 10s, pinned to a version, and keep a step log and evidence screenshot.

## License

GPL-3.0 (see `LICENSE` and `NOTICE`). Portions adapted from Nook, © the Nook contributors, GPL-3.0.
Built with AI assistance (Devin).
