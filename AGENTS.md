# Guidance for agents and contributors

## Adapters

Claude Code and Codex don't document their log formats, and they change them without notice. An adapter change (`ClaudeCodeAdapter`, `CodexAdapter`, `SessionLog`, including the record types and keys they know) merges only with passing fixture tests and the owner's review, whoever wrote it, an agent included. A new record shape gets a sanitized fixture from a real log. CI runs `swift test` on every push and pull request.
