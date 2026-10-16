# Compressed rollout fixtures

Synthetic JSONL compressed with Zstandard 1.5.7, `--no-content-size`; no real sessions or account data.

- `user`: user metadata, user message, token_count (1000 input including 400 cached; 50 output).
- `subagent`: child metadata plus a user-role message to verify source classification wins.
- `long`: metadata and user message, 2,000,000-character assistant line, trailing user message; verifies bounded preview and oversized-line handling.

The decoder tests also concatenate, truncate and corrupt copies in their own temporary directories. Tests do not require an external encoder or rewrite these fixtures.
