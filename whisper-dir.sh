#!/bin/bash

FORMATS="aac aif aiff caf flac mp2 mp3 opus tta wav wma wv"

WHISPER_BIN="${WHISPER_BIN:-$HOME/Tools/whisper.cpp/build/bin/whisper-cli}"
MODEL_DIR="${WHISPER_MODEL_DIR:-$HOME/Tools/whisper.cpp/models}"
MODEL="${WHISPER_DEFAULT_MODEL:-medium.en}"
STRIP_TIMESTAMPS=true
OVERWRITE=false
OUTPUT_FILE=""
MAX_CONTEXT=0

usage() {
    echo "Usage: whisper-dir [options] <input_dir>"
    echo "  -m <model>     Model name (default: medium.en)"
    echo "  -o <file>      Output file path (default: <input_dir>/transcriptions.md)"
    echo "  -t             Keep timestamps (stripped by default)"
    echo "  -f             Overwrite output file (appends by default)"
    echo "  -mc <n>        Max context tokens from previous segment (default: 0, reduces hallucinations)"
    exit 1
}

[ $# -eq 0 ] && usage

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m)  MODEL="$2";       shift 2 ;;
        -o)  OUTPUT_FILE="$2"; shift 2 ;;
        -mc) MAX_CONTEXT="$2"; shift 2 ;;
        -t)  STRIP_TIMESTAMPS=false; shift ;;
        -f)  OVERWRITE=true;   shift ;;
        -*)  usage ;;
        *)   POSITIONAL+=("$1"); shift ;;
    esac
done

INPUT_DIR="${POSITIONAL[0]}"

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
    echo "Error: Model '$MODEL' not found. Available models:"
    for f in "$MODEL_DIR"/ggml-*.bin; do
        [ -f "$f" ] && echo "  ${f##*/ggml-}" | sed 's/\.bin$//'
    done
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
        "$WHISPER_BIN" -m "$MODEL_PATH" -f "$f" -mc "$MAX_CONTEXT" 2>/dev/null \
            | sed 's/\[[0-9:\.]* --> [0-9:\.]*\][[:space:]]*//' \
            >> "$OUTPUT_FILE"
    else
        "$WHISPER_BIN" -m "$MODEL_PATH" -f "$f" -mc "$MAX_CONTEXT" 2>/dev/null >> "$OUTPUT_FILE"
    fi

    echo "" >> "$OUTPUT_FILE"
    echo "---" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
done < <(find "$INPUT_DIR" \( "${FIND_ARGS[@]}" \) -type f | sort)

echo "Done. Output: $OUTPUT_FILE"