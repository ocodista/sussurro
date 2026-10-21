#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${SUSSURRO_PROOF_CONFIGURATION:-debug}"
FIXTURES="$ROOT/Tests/Fixtures/phase1"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sussurro-phase1-proof.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

swift build --package-path "$ROOT" -c "$CONFIGURATION" --product sussurro-mcp
BIN="$ROOT/.build/$CONFIGURATION/sussurro-mcp"
cp "$FIXTURES/fake-whisper-cli.sh" "$TEMP_DIR/whisper-cli"
chmod 700 "$TEMP_DIR/whisper-cli"
cp "$FIXTURES/model.bin" "$TEMP_DIR/model.bin"
# Keep the proof offline while satisfying the same structural readiness check as
# production: the fixture starts with a recognized GGUF header and is padded to
# the minimum sensible model size. It is intentionally not a usable model.
truncate -s 1048576 "$TEMP_DIR/model.bin"

# Poison conventional proxy settings: the proof must complete using only local files/processes.
export HTTP_PROXY="http://127.0.0.1:1"
export HTTPS_PROXY="http://127.0.0.1:1"
export ALL_PROXY="http://127.0.0.1:1"
export NO_PROXY="*"

python3 - "$BIN" "$TEMP_DIR/whisper-cli" "$TEMP_DIR/model.bin" "$FIXTURES/fixture.wav" "$FIXTURES/schema.json" "$TEMP_DIR/last.json" <<'PY'
import json
import subprocess
import sys

binary, cli, model, audio, schema_path, last_path = sys.argv[1:]
with open(schema_path, encoding="utf-8") as handle:
    schema = json.load(handle)
requests = [
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"proof","version":"1"}}},
    {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}},
    {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"transcribe_audio","arguments":{"audio_path":audio}}},
    {"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"structure_text","arguments":{"text":"speaker: Ana\nminutes: 12\napproved: true","schema":schema}}},
    {"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"structure_audio","arguments":{"audio_path":audio,"schema":schema}}},
    {"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"get_last_transcription","arguments":{}}},
    {"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"get_local_readiness","arguments":{}}},
]
completed = subprocess.run(
    [binary, "--whisper-cli", cli, "--model", model, "--language", "en", "--last-transcription-file", last_path],
    input="".join(json.dumps(item, separators=(",", ":")) + "\n" for item in requests),
    text=True,
    capture_output=True,
    check=False,
    timeout=30,
)
if completed.returncode != 0:
    raise SystemExit(f"MCP exited {completed.returncode}: {completed.stderr}")
responses = [json.loads(line) for line in completed.stdout.splitlines() if line.strip()]
assert len(responses) == len(requests), (completed.stdout, completed.stderr)
by_id = {item["id"]: item for item in responses}
assert by_id[1]["result"]["serverInfo"]["name"] == "sussurro"
assert {tool["name"] for tool in by_id[2]["result"]["tools"]} == {
    "transcribe_audio", "structure_text", "structure_audio", "get_last_transcription", "get_local_readiness"
}
expected_text = "speaker: Ana\nminutes: 12\napproved: true"
assert by_id[3]["result"]["structuredContent"]["text"] == expected_text
expected_json = {"speaker":"Ana", "minutes":12, "approved":True}
assert by_id[4]["result"]["structuredContent"] == expected_json
assert by_id[5]["result"]["structuredContent"] == expected_json
assert by_id[6]["result"]["structuredContent"]["text"] == expected_text
readiness = by_id[7]["result"]["structuredContent"]
assert readiness["is_mcp_ready"] is True
assert readiness["is_dictation_ready"] is False
assert readiness["privacy_summary"].startswith("Audio and transcripts stay on this Mac")
assert "text" not in readiness and "audio_path" not in readiness
assert all(not by_id[index]["result"]["isError"] for index in range(3, 8))
print("PASS Phase 1.1: transcription + schema-valid JSON + MCP stdio + local readiness")
print("PASS Network-independent fixture: poisoned proxy environment; local files/processes only")
PY
