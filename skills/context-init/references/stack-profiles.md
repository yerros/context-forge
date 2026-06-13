# Stack Profiles

The six templates are written with web-app examples, but the methodology applies to any
stack. After detecting the project type, adapt which files matter and what each
emphasizes. Detect the type from dependencies and structure, then apply the matching
profile. When unsure, ask the user which profile fits.

For every profile: `project-overview.md`, `architecture.md`, `code-standards.md`,
`ai-workflow-rules.md`, and `progress-tracker.md` always apply. What varies most is
`ui-context.md` and what the stack-specific sections of `architecture.md` /
`code-standards.md` should contain.

## Detection signals

- `package.json` with `next`/`react`/`vue`/`svelte` → **Web frontend / full-stack**
- `package.json` with `express`/`fastify`/`nest`, or `requirements.txt`/`pyproject.toml`
  with `fastapi`/`django`/`flask`, or `go.mod`, or `pom.xml`/`build.gradle` → **Backend / API**
- `pubspec.yaml` (Flutter), `*.xcodeproj`/`Package.swift` (iOS), `build.gradle` with
  `com.android` (Android), or `react-native` in deps → **Mobile**
- `setup.py`/`pyproject.toml` for a library, a `bin`/`cmd` entrypoint, `Cargo.toml` with
  `[[bin]]` → **CLI / Library**
- `requirements.txt`/`pyproject.toml` with `pandas`/`numpy`/`torch`/`scikit-learn`,
  notebooks (`*.ipynb`), or a `dags/`/`pipelines/` folder → **Data / ML**

## Profiles

### Web frontend / full-stack (default)
Use the templates as written. `ui-context.md` is fully relevant — colors, typography,
component library, layout patterns. `architecture.md` covers framework, UI, auth, DB.

### Backend / API
- **Drop or trim `ui-context.md`** — replace it with an **`api-context.md`** style file
  (or repurpose ui-context) covering: API style (REST/GraphQL/gRPC), versioning,
  resource naming, error/response envelope shape, status-code conventions, pagination,
  auth scheme (JWT/session/API key), rate limiting.
- `architecture.md`: emphasize service boundaries, data model, migrations, background
  jobs/queues, idempotency, and transaction boundaries. Invariants like "every mutation
  endpoint enforces auth and ownership" and "request handlers don't run long jobs".
- `code-standards.md`: validation at boundaries, error handling, logging, DTO/schema
  conventions, language idioms (Python typing, Go error handling, etc.).

### Mobile
- `ui-context.md` stays, adapted to the platform: design tokens, navigation pattern
  (stack/tab), platform components (Material/Cupertino/SwiftUI), responsive/safe-area,
  theming, accessibility.
- `architecture.md`: state management, local persistence vs remote sync, offline
  behavior, API client, platform permissions. Invariants like "network calls never run
  on the main thread".
- `code-standards.md`: widget/component structure, navigation conventions, async/state
  patterns.

### CLI / Library
- **Drop `ui-context.md`.** Replace with an **interface contract** focus inside
  `architecture.md`: public API surface, command/flag structure, input/output formats,
  exit codes, semver/backward-compatibility policy.
- `code-standards.md`: public-vs-internal API rules, docstrings/docs, error messages,
  no breaking changes without a major bump.
- Success criteria in `project-overview.md` should be example invocations and expected
  output.

### Data / ML
- **Drop `ui-context.md`** unless there's a dashboard.
- `architecture.md`: data sources, pipeline/DAG stages, storage (raw/processed/features),
  model registry, reproducibility (seeds, versioned data), compute. Invariants like
  "no training reads from production write paths" and "every run is reproducible from a
  pinned config".
- `code-standards.md`: notebook-to-module discipline, config management, experiment
  tracking, data validation.

## Applying a profile

1. Detect the type and tell the user which profile you're applying (and why).
2. Scaffold the core files. For profiles that drop `ui-context.md`, either omit it or
   repurpose it for the profile's interface concerns — and update `CLAUDE.md`/`AGENTS.md`
   so its file list matches what actually exists.
3. Fill each file with stack-appropriate content and invariants, using real evidence for
   brownfield projects.
