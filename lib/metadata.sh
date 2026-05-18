#!/bin/zsh

DIANE_DIR="$(dirname "$0")/.."
CURRENT_DIR="$(pwd)"

TRANSCRIPT_FILE="$CURRENT_DIR/metadata_transcriptions.md"
OUTPUT_FILE="$CURRENT_DIR/metadata.csv"

DELETE_TRANSCRIPTIONS=false
WHISPER_SNIP_SECONDS=""
WHISPER_PROMPT=""

usage() {
    echo "Usage: Diane metadata [flags] [message]"
    echo ""
    echo "Snips and transcribes audio files in the current directory, then extracts"
    echo "recorder deployment metadata into metadata.csv."
    echo ""
    echo "Flags:"
    echo "  -m <model>    Claude model to use (default: sonnet)"
    echo "                Aliases: sonnet, opus, haiku"
    echo "                Full IDs: claude-sonnet-4-6, claude-opus-4-7, etc."
    echo "  -e <level>    Thinking effort: low, medium, high, xhigh, max (default: medium)"
    echo "  -w <model>    Whisper model to use (default: large-v3-turbo)"
    echo "                Examples: tiny.en, base.en, small.en, medium.en, large-v3"
    echo "  -s <seconds>  Audio snip duration in seconds (default: 120)"
    echo "  -wp <prompt>  Transcription hint passed to whisper"
    echo "  -mc <n>       Max context tokens from previous segment (default: 0)"
    echo "  -o <path>     Output file path (default: metadata.csv in current directory)"
    echo "  -d            Delete metadata_transcriptions.md after metadata.csv is written"
    echo "  -v            Verbose: print Claude's thinking after run completes (requires jq)"
    echo "  -h            Show this help message"
    echo ""
    echo "Arguments:"
    echo "  message  Optional message passed directly to Diane (overrides everything else)"
    echo ""
    echo "Examples:"
    echo "  Diane metadata"
    echo "  Diane metadata \"Add a varieties column where every entry is Elliot\""
    echo "  Diane metadata -s 60"
    echo "  Diane metadata -wp \"voice memos from the Diel Drivers experiment\""
    echo "  Diane metadata -m opus -e high"
    echo "  Diane metadata \"Recorders 3 and 4 were swapped — correct in output\""
    exit 0
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)  OUTPUT_FILE="$2";          shift 2 ;;
        -s)  WHISPER_SNIP_SECONDS="$2"; shift 2 ;;
        -wp) WHISPER_PROMPT="$2";       shift 2 ;;
        -d)  DELETE_TRANSCRIPTIONS=true; shift ;;
        -v)  DIANE_VERBOSE=true;        shift ;;
        -h)  usage ;;
        -*)  usage ;;
        *)   POSITIONAL+=("$1"); shift ;;
    esac
done

USER_INSTRUCTION="${POSITIONAL[0]}"

if [ -f "$OUTPUT_FILE" ]; then
    echo "Error: metadata.csv already exists in this directory. Remove it first if you want to re-run Diane."
    exit 1
fi

SNIP_ARGS=(-m "$DIANE_WHISPER_MODEL")
[ -n "$WHISPER_SNIP_SECONDS" ]     && SNIP_ARGS+=(-s "$WHISPER_SNIP_SECONDS")
[ -n "$DIANE_WHISPER_MAX_CONTEXT" ] && SNIP_ARGS+=(-mc "$DIANE_WHISPER_MAX_CONTEXT")
SNIP_ARGS+=(-o "$TRANSCRIPT_FILE")
[ -n "$WHISPER_PROMPT" ]           && SNIP_ARGS+=("$WHISPER_PROMPT")
SNIP_ARGS+=("$CURRENT_DIR")

"$DIANE_DIR/whisper-snip.sh" "${SNIP_ARGS[@]}" || exit 1

if [ ! -s "$TRANSCRIPT_FILE" ]; then
    echo "No audio files found or transcription produced nothing."
    exit 1
fi

PROMPT="$(cat "$TRANSCRIPT_FILE")"
if [ -n "$USER_INSTRUCTION" ]; then
    PROMPT="$PROMPT

---
Special instruction from the researcher: $USER_INSTRUCTION"
fi

OUTPUT_TMP="$(mktemp)"
SYSTEM_PROMPT="$(cat "$(dirname "$0")/shared.md"; printf '\n\n'; cat "$(dirname "$0")/metadata.md")"

if [ "${DIANE_VERBOSE:-false}" = true ]; then
    if ! command -v jq &>/dev/null; then
        echo "Error: -v requires jq. Install it with: brew install jq"
        exit 1
    fi
    while IFS= read -r line; do
        thinking=$(printf '%s' "$line" | jq -r 'if .type == "assistant" then (.message.content[]? | select(.type == "thinking") | .thinking) else empty end' 2>/dev/null)
        [[ -n "$thinking" ]] && printf '\033[2m%s\033[0m\n' "$thinking"
        result=$(printf '%s' "$line" | jq -r 'if .type == "result" and .subtype == "success" then .result else empty end' 2>/dev/null)
        [[ -n "$result" ]] && printf '%s\n' "$result" > "$OUTPUT_TMP"
    done < <(claude -p "$PROMPT" \
        --output-format stream-json --verbose \
        --model "$DIANE_MODEL" \
        --effort "$DIANE_EFFORT" \
        --system-prompt "$SYSTEM_PROMPT" \
        --tools "")
else
    source "$DIANE_DIR/lib/spinner.sh"
    spinner_start
    claude -p "$PROMPT" \
        --model "$DIANE_MODEL" \
        --effort "$DIANE_EFFORT" \
        --system-prompt "$SYSTEM_PROMPT" \
        --tools "" \
        > "$OUTPUT_TMP"
    spinner_stop
fi

mv "$OUTPUT_TMP" "$OUTPUT_FILE"
echo "Metadata written to: $OUTPUT_FILE"

if [ "$DELETE_TRANSCRIPTIONS" = true ]; then
    rm "$TRANSCRIPT_FILE"
    echo "Deleted metadata_transcriptions.md"
fi
