# BrowserSkills architecture

Status: proposed design. See AGENT_BUILD_SPEC.md for the complete implementation contract. None of the integrations below are asserted to be tested by this document.

BrowserSkills turns an explicit browser demonstration into a versioned, verified procedure exposed through MCP. It caches the procedure and fetches fresh results when invoked.

## Component architecture

```mermaid
flowchart TD
    subgraph Local["Local execution device"]
        UI["Dashboard and assistant"] --> A["Nemotron agent loop"]
        A --> M["MCP adapter"]
        H["Hermes external client"] --> M
        M --> B["Backend and policy gate"]
        UI --> B
        B <--> DB["SQLite registry and run history"]
        B <--> X["Paired Chrome extension"]
        X --> P["Allowed website"]
        B --> C["Trace compiler"]
    end
    A <--> N["Nemotron on Nebius"]
    C <--> N
```

The backend owns workflow versions, permissions and run state. Both the integrated assistant and Hermes invoke the same MCP tools. The extension executes only a constrained action vocabulary. Website authentication stays in the browser profile.

## Learning and validation

```mermaid
flowchart TD
    R["Record explicit demonstration"] --> I["Mark inputs and select outputs"]
    I --> C["Redact and compile with Nemotron"]
    C --> S{"Schema and policy valid"}
    S -->|No| E["Return compile error"]
    S -->|Yes| D["Store candidate version"]
    D --> T["Replay with another input"]
    T --> V{"Output checks pass"}
    V -->|No| F["Keep candidate and show failure"]
    V -->|Yes| P["Promote version and expose MCP tool"]
```

One demonstration supports its observed path. Promotion does not establish support for unobserved branches. The output identity must match the new input, not just be nonempty.

## MCP execution sequence

```mermaid
sequenceDiagram
    participant A as Agent
    participant M as MCP adapter
    participant B as Backend
    participant X as Extension
    participant P as Website
    A->>M: Call discovered tool with arguments
    M->>B: Create deduplicated run
    B->>B: Validate inputs, origin and profile
    B->>B: Lock tab and pin workflow version
    loop Each stored procedure step
        B->>X: Authenticated command with command ID
        X->>P: Resolve unique target and act
        P-->>X: Current page state
        X-->>B: Result or structured error
    end
    B->>B: Verify output identity and required fields
    alt Checks pass
        B-->>M: Verified output and run evidence
        M-->>A: Success with actual output
    else Error or failed check
        B-->>M: Failed status and actionable reason
        M-->>A: Tool error with run ID
    end
```

The protocol is not an exactly-once guarantee for arbitrary websites. If a command outcome is uncertain after disconnect, stop and inspect state. Do not blindly replay a click.

## Run lifecycle

```mermaid
stateDiagram-v2
    [*] --> Queued
    Queued --> Running: Tab acquired
    Queued --> Cancelled: User cancels
    Running --> Verifying: Steps finish
    Running --> NeedsLogin: Session expired
    Running --> NeedsReview: Outcome uncertain
    Running --> Failed: Step error
    Running --> Cancelled: Safe cancellation boundary
    Running --> Interrupted: Backend restarts
    Verifying --> Success: All checks pass
    Verifying --> Failed: Check fails
    Verifying --> Interrupted: Backend restarts
    Success --> [*]
    Failed --> [*]
    NeedsLogin --> [*]
    NeedsReview --> [*]
    Cancelled --> [*]
    Interrupted --> [*]
```

Success is assigned only after verification. An interrupted run requires a new explicit run after state inspection. Status names must be mapped consistently to the API enum implemented by the backend.

## Data and privacy boundaries

| Data | Stored or processed where | Rule |
| --- | --- | --- |
| Website session cookies | Chrome profile | Never export to the model |
| Provider API key | Local backend configuration | Never include in frontend bundles or logs |
| Pairing token | Local backend and extension storage | Authenticate the bridge; never put in a URL |
| Recorded trace | Local temporary storage | Exclude secret inputs and expire raw examples |
| Redacted relevant context | Nebius inference | Explicit cloud boundary; not fully on-device |
| Workflow versions and results | Local SQLite | Keep verification and version evidence |

OpenShell and a compatible NemoClaw blueprint are optional deployment integrations until smoke tested. The real browser remains outside the agent sandbox, so the backend must enforce site and action permissions independently. A sandbox alone does not secure an unrestricted browser bridge.

## Deployment defaults

| Process | Development endpoint | Dependency |
| --- | --- | --- |
| Dashboard | 127.0.0.1:4316 | Proxies authenticated backend requests |
| Backend and extension bridge | 127.0.0.1:4317 | Owns SQLite and paired extension |
| Demo portal | 127.0.0.1:4318 | Seeded local data |
| MCP adapter | stdio child process | Authenticated backend connection |
| Nemotron inference | Configured Nebius endpoint | Selected NVIDIA model and API key |

Production local startup serves built dashboard assets from the backend. Browser tasks require the execution device and browser to remain online. No cloud deployment is implied.

