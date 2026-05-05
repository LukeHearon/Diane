#!/bin/bash

# Load config
DIANE_CONFIG="${DIANE_CONFIG:-$HOME/.config/diane/config.txt}"
if [ -f "$DIANE_CONFIG" ]; then
    # shellcheck source=/dev/null
    source "$DIANE_CONFIG"
fi

FORMATS="aac aif aiff caf flac mp2 mp3 opus tta wav wma wv"

WHISPER_BIN="${WHISPER_BIN:-$HOME/Tools/whisper.cpp/build/bin/whisper-cli}"
MODEL_DIR="${WHISPER_MODEL_DIR:-$HOME/Tools/whisper.cpp/models}"
MODEL="${WHISPER_DEFAULT_MODEL:-medium.en}"
STRIP_TIMESTAMPS=true
OVERWRITE=false
OUTPUT_FILE=""

usage() {
    echo "Usage: whisper-dir [options] <input_dir>"
    echo "  -m <model>     Model name (default: medium.en)"
    echo "  -o <file>      Output file path (default: <input_dir>/transcriptions.md)"
    echo "  -t             Keep timestamps (stripped by default)"
    echo "  -f             Overwrite output file (appends by default)"
    exit 1
}

[ $# -eq 0 ] && usage

while getopts "m:o:tf" opt; do
    case $opt in
        m) MODEL="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        t) STRIP_TIMESTAMPS=false ;;
        f) OVERWRITE=true ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

INPUT_DIR="${1}"

if [ -z "$INPUT_DIR" ]; then
    echo "Error: input_dir is required"
    usage
fi

if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: '$INPUT_DIR' is not a directory"
    exit 1
fi

OUTPUT_FILE="${OUTPUT_FILE:-$INPUT_DIR/transcriptions.md}"
MODEL_PATH="$MODEL_DIR/ggml-${MODEL}.bin"

if [ ! -f "$WHISPER_BIN" ]; then
    echo "Error: whisper-cli not found at $WHISPER_BIN"
    exit 1
fi

if [ ! -f "$MODEL_PATH" ]; then
    echo "Error: Model not found at $MODEL_PATH"
    exit 1
fi

if [ "$OVERWRITE" = true ]; then
    > "$OUTPUT_FILE"
fi

FIND_ARGS=()
for ext in $FORMATS; do
    FIND_ARGS+=(-o -name "*.$ext")
done
# Build find expression: remove the leading -o
FIND_ARGS=("${FIND_ARGS[@]:1}")

total=$(find "$INPUT_DIR" \( "${FIND_ARGS[@]}" \) -type f | wc -l | tr -d ' ')
count=0

while IFS= read -r f; do
    [ -f "$f" ] || continue
    count=$((count + 1))
    relpath="${f#$INPUT_DIR/}"
    if [ "$OVERWRITE" = false ] && [ -f "$OUTPUT_FILE" ] && grep -qF "# $relpath" "$OUTPUT_FILE"; then
        echo "[$count/$total] Skipping (already transcribed): $relpath"
        continue
    fi
    echo "[$count/$total] Transcribing: $relpath"
    echo "# $relpath" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    if [ "$STRIP_TIMESTAMPS" = true ]; then
        "$WHISPER_BIN" -m "$MODEL_PATH" -f "$f" 2>/dev/null \
            | sed 's/\[[0-9:\.]* --> [0-9:\.]*\][[:space:]]*//' \
            >> "$OUTPUT_FILE"
    else
        "$WHISPER_BIN" -m "$MODEL_PATH" -f "$f" 2>/dev/null >> "$OUTPUT_FILE"
    fi

    echo "" >> "$OUTPUT_FILE"
    echo "---" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
done < <(find "$INPUT_DIR" \( "${FIND_ARGS[@]}" \) -type f | sort)

echo "Done. Output: $OUTPUT_FILE"