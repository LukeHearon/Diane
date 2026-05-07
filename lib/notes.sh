#!/bin/zsh

DIANE_DIR="$(dirname "$0")/.."
CURRENT_DIR="$(pwd)"

TRANSCRIPT_FILE="$CURRENT_DIR/transcriptions.md"
NOTES_FILE="$CURRENT_DIR/notes.md"

DELETE_TRANSCRIPTIONS=false

usage() {
    echo "Usage: Diane notes [flags] [message]"
    echo ""
    echo "Transcribes audio files in the current directory and organizes them into notes.md."
    echo ""
    echo "Flags:"
    echo "  -m <model>   Claude model to use (default: sonnet)"
    echo "               Aliases: sonnet, opus, haiku"
    echo "               Full IDs: claude-sonnet-4-6, claude-opus-4-7, etc."
    echo "  -e <level>   Thinking effort: low, medium, high, xhigh, max (default: medium)"
    echo "  -w <model>   Whisper model to use (default: large-v3-turbo)"
    echo "               Examples: tiny.en, base.en, small.en, medium.en, large-v3"
    echo "  -mc <n>      Max context tokens from previous segment (default: 0, reduces hallucinations)"
    echo "  -o <path>    Output file path (default: notes.md in current directory)"
    echo "  -d           Delete transcriptions.md after notes.md is written"
    echo "  -h           Show this help message"
    echo ""
    echo "Arguments:"
    echo "  message  Optional message passed directly to Diane (overrides everything else)"
    echo ""
    echo "Examples:"
    echo "  Diane notes"
    echo "  Diane notes \"This is a one-off recording — write it up as a numbered protocol\""
    echo "  Diane notes -e high"
    echo "  Diane notes -m opus -e high \"Focus on the weather data\""
    echo "  Diane notes -w large-v3 \"Speaker has a strong accent\""
    echo "  Diane notes -d"
    exit 0
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)  NOTES_FILE="$2";            shift 2 ;;
        -d)  DELETE_TRANSCRIPTIONS=true; shift ;;
        -h)  usage ;;
        -*)  usage ;;
        *)   POSITIONAL+=("$1"); shift ;;
    esac
done

USER_INSTRUCTION="${POSITIONAL[0]}"

if [ -f "$NOTES_FILE" ]; then
    echo "Error: notes.md already exists in this directory. Remove it first if you want to re-run Diane."
    exit 1
fi

WHISPER_ARGS=(-m "$DIANE_WHISPER_MODEL" "$CURRENT_DIR")
[ -n "$DIANE_WHISPER_MAX_CONTEXT" ] && WHISPER_ARGS=(-mc "$DIANE_WHISPER_MAX_CONTEXT" "${WHISPER_ARGS[@]}")
"$DIANE_DIR/whisper-dir.sh" "${WHISPER_ARGS[@]}" || exit 1

if [ ! -s "$TRANSCRIPT_FILE" ]; then
    echo "No audio files found or transcription produced nothing."
    exit 1
fi

echo "Sending transcription to Diane..."

PROMPT="$(cat "$TRANSCRIPT_FILE")"
if [ -n "$USER_INSTRUCTION" ]; then
    PROMPT="$PROMPT

---
Special instruction from the researcher: $USER_INSTRUCTION"
fi

NOTES_TMP="$(mktemp)"
claude -p "$PROMPT" \
    --model "$DIANE_MODEL" \
    --effort "$DIANE_EFFORT" \
    --system-prompt "$(cat "$(dirname "$0")/shared.md"; printf '\n\n'; cat "$(dirname "$0")/notes.md")" \
    --tools "" \
    > "$NOTES_TMP"

mv "$NOTES_TMP" "$NOTES_FILE"
echo "Notes written to: $NOTES_FILE"

if [ "$DELETE_TRANSCRIPTIONS" = true ]; then
    rm "$TRANSCRIPT_FILE"
    echo "Deleted transcriptions.md"
fi
