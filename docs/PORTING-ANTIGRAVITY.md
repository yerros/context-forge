# Porting context-forge ke Antigravity CLI

> **Status: TERIMPLEMENTASI (v0.45.0, 2026-08-17).** Jalankan
> `./scripts/build-antigravity.sh` lalu
> `agy plugin install dist/antigravity/context-forge`. Adapter:
> `hooks/antigravity/agy-hook.sh`; tests: `tests/antigravity.bats` (17 test,
> semuanya hijau bersama 128 test lama). Rincian keputusan implementasi ada di
> CHANGELOG 0.45.0; dokumen ini adalah desain + pemetaan referensinya.

Target: kualitas setara dengan versi Claude Code, memakai satu sumber (repo ini) plus layer adapter yang men-generate bundle Antigravity.

Referensi resmi: [Plugins & Skills (CLI)](https://antigravity.google/docs/cli/plugins), [Hooks](https://antigravity.google/docs/hooks), [Skills](https://antigravity.google/docs/skills), [Subagents](https://antigravity.google/docs/subagents).

## 1. Model ekstensibilitas Antigravity

Antigravity punya konsep yang hampir 1:1 dengan Claude Code: plugin (bundle `plugin.json` + `skills/` + `agents/` + `hooks.json` + `mcp_config.json` + `rules/`), skills berformat folder + `SKILL.md` (standar terbuka agentskills.io — sama dengan Claude Code), subagent markdown dengan YAML frontmatter, dan hooks berbasis shell command. Plugin di-install ke `~/.gemini/antigravity-cli/plugins/<nama>/` via `agy plugin install /path`.

Perbedaannya ada di detail schema dan kontrak I/O — di situlah kualitas bisa turun kalau hanya copy-paste.

## 2. Pemetaan komponen

| Komponen context-forge | Antigravity | Status |
|---|---|---|
| `.claude-plugin/plugin.json` | `plugin.json` di root plugin | Ubah: schema ketat, hanya `name` + `description` (`additionalProperties: false`). Buang `version`, `author`, `homepage`, `keywords`. |
| `skills/*/SKILL.md` (+ scripts, references, templates) | `skills/` dalam plugin, format identik | Hampir kompatibel. Frontmatter resmi hanya `name` + `description`; `metadata.version` kemungkinan diabaikan — uji. Di CLI, skill otomatis jadi slash command (`/forge-build`). |
| `agents/*.md` | `agents/` dalam plugin | Ubah frontmatter (lihat §3.2). |
| `hooks/hooks.json` | `hooks.json` dalam plugin | Rombak besar: struktur, event, matcher tool, dan kontrak I/O berbeda (lihat §3.3). |
| `.claude-plugin/marketplace.json` | — | Tidak ada padanan; distribusi via `agy plugin install`. |
| `statusline/statusline.sh` | Status Line CLI (`/statusline`) | Protokol berbeda — port terpisah, cek [docs/cli/statusline](https://antigravity.google/docs/cli/statusline). |
| CLAUDE.md / AGENTS.md di proyek user | AGENTS.md + `.agents/rules/` | forge sudah mendukung AGENTS.md; jadikan itu default di Antigravity. Invarian keras bisa juga di-mirror ke `rules/`. |

## 3. Perubahan wajib

### 3.1 plugin.json

```json
{
  "$schema": "https://antigravity.google/schemas/v1/plugin.json",
  "name": "context-forge",
  "description": "Spec-driven build methodology with tiered context loading..."
}
```

### 3.2 Agents

Frontmatter Claude Code → Antigravity:

- `tools: Read, Grep, Glob, Bash` (string) → daftar YAML dengan nama tool Antigravity:
  `Read`→`view_file`, `Grep`→`grep_search`, `Glob`→`find_by_name`, `Bash`→`run_command`, `Write`→`write_to_file`, `Edit`→`replace_file_content`/`multi_replace_file_content`, `WebFetch`→`read_url_content`, `WebSearch`→`search_web`, `Task`→`invoke_subagent`.
- `model: sonnet|haiku` → `model: pro|flash|inherit`. Pemetaan: haiku→flash, sonnet→inherit (atau pro untuk reviewer/architect).
- Tambahkan `subagent: true`, `mainAgent: false`, dan `commandExecutionPolicy: sandbox` untuk agent read-only.
- ⚠️ Nama tool salah ketik membuat subagent **hang** (known issue) — validasi otomatis di adapter.

Body markdown (system prompt) bisa dipakai apa adanya.

### 3.3 Hooks — bagian paling kritis

**Struktur file.** Claude Code: `{"hooks": {Event: [...]}}`. Antigravity: map nama-hook → konfigurasi event:

```json
{
  "forge-context": { "PreInvocation": [ { "command": "..." } ] },
  "forge-guard":   { "PreToolUse": [ { "matcher": "write_to_file|replace_file_content|multi_replace_file_content", "hooks": [ { "command": "...", "timeout": 10 } ] } ] }
}
```

**Pemetaan event.**

| Claude Code | Antigravity | Catatan |
|---|---|---|
| SessionStart (inject digest) | `PreInvocation` | Gate `invocationNum == 0`; output harus JSON `{"injectSteps":[{"ephemeralMessage":"<digest>"}]}` — bukan stdout mentah. |
| PreToolUse (guard.sh) | `PreToolUse` | Blokir bukan lewat exit code 2, tapi stdout JSON `{"decision":"deny","reason":"..."}`. Decision lain: `allow`, `ask`, `force_ask`. |
| PostToolUse | `PostToolUse` | Output `{}`; input punya `error` jika tool gagal. |
| UserPromptSubmit / UserPromptExpansion | ~`PreInvocation` | Tidak ada event prompt-level; jalankan tiap invocation, dedup sendiri. |
| Stop | `Stop` | Ada `fullyIdle` + bisa `{"decision":"continue"}` untuk melawan premature stop. |
| SubagentStop | — | Tidak ada; dekati via PostToolUse matcher `invoke_subagent`/`manage_subagents`, atau Stop di sisi subagent. |
| SessionEnd | ~`Stop` (`fullyIdle: true`) | Perkiraan terdekat. |

**Kontrak stdin.** Field camelCase: `toolCall.name`, `toolCall.args` (arg tool juga beda: `TargetFile`, `CommandLine`, `Cwd`), `conversationId`, `workspacePaths`, `transcriptPath`, `modelName`. Semua script hook (`guard.sh`, `track.sh`, `now-status.sh`, `hook-logger.sh`, `skill-status.sh`, `agent-status.sh`) perlu branch parser: deteksi payload Antigravity vs Claude Code, lalu normalisasi field.

**Matcher tool.** `^(Write|Edit|MultiEdit|NotebookEdit)$` → `write_to_file|replace_file_content|multi_replace_file_content`. `^(Task|Agent)$` → `invoke_subagent`. `^Skill$` → tidak ada tool Skill; skill dibaca via `view_file` dengan arg `IsSkillFile: true` — deteksi skill-status lewat situ.

**`${CLAUDE_PLUGIN_ROOT}`.** Tidak terdokumentasi ada padanannya. Ganti dengan path resolusi mandiri: script wrapper yang mencari `~/.gemini/antigravity-cli/plugins/context-forge/` (atau `$0`-relative karena hooks.json ikut ter-install di root plugin).

### 3.4 Skills

Isi SKILL.md yang menyebut hal spesifik Claude Code perlu netralisasi teks: "CLAUDE.md" → "CLAUDE.md/AGENTS.md" (sudah begitu di banyak tempat), referensi tool (`Task` tool → `invoke_subagent`), dan instruksi memanggil skill lain (di CLI Antigravity: slash command). Struktur folder + scripts/templates/references didukung penuh — tidak perlu diubah.

## 4. Strategi: satu sumber, adapter build

Jangan fork. Buat `scripts/build-antigravity.sh` yang men-generate `dist/antigravity/context-forge/`:

1. Transform `plugin.json` (strip field ekstra).
2. Copy `skills/` apa adanya + text-substitution istilah tool.
3. Transform frontmatter `agents/` (tools map, model map, tambah `subagent`/`mainAgent`) + validasi nama tool terhadap whitelist.
4. Generate `hooks.json` format Antigravity dari sumber tunggal (mis. `hooks/hooks.src.json` dengan anotasi per-platform).
5. Sertakan shim `lib/hook-io.sh`: normalisasi stdin (snake_case ↔ camelCase, nama tool) + emitter output (exit-code semantics vs JSON decision) sehingga script hook inti tetap satu.

Test: tambah bats fixtures payload Antigravity untuk `guard`, `track`, `session-start` (versi PreInvocation), dan smoke test `agy plugin install dist/antigravity/context-forge && agy` lalu `/hooks`, `/forge-init`.

## 5. Risiko kualitas & mitigasi

- **Injeksi digest**: jantung metodologi. Di Antigravity harus lewat `injectSteps`; `ephemeralMessage` bersifat transien — uji apakah bertahan cukup lama; jika tidak, fallback `userMessage` pada invocation 0 saja.
- **Guard**: semantik `deny` Antigravity lebih kaya (`ask`, `deny_unless_prior_grant`) — bisa jadi *lebih baik* dari exit-2 Claude Code.
- **Auto-trigger skill**: Antigravity memakai progressive disclosure yang sama (daftar name+description saat start) — kualitas deskripsi frontmatter menentukan; deskripsi forge sudah kuat.
- **Model**: hanya tier `flash`/`pro`/`inherit` (Gemini). Persona/kalibrasi agent yang dituning untuk Claude perlu diuji ulang perilakunya di Gemini.
- **forge-office / statusline**: bergantung event Claude Code yang granular; di Antigravity turunkan ekspektasi (PreInvocation/PostInvocation lebih kasar) atau tandai fitur "best effort".
- **Versi**: docs CLI v1.1.13 — schema masih muda dan bisa berubah; pin pemeriksaan `$schema` di adapter.
