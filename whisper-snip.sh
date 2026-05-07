#!/usr/bin/env bash

WHISPER_BIN="${WHISPER_BIN:-$HOME/Tools/whisper.cpp/build/bin/whisper-cli}"
MODEL_DIR="${WHISPER_MODEL_DIR:-$HOME/Tools/whisper.cpp/models}"
MODEL="${WHISPER_DEFAULT_MODEL:-large-v3-turbo}"
SNIP_SECONDS=120
OVERWRITE=false
OUTPUT_FILE=""
MAX_CONTEXT=0

usage() {
    echo "Usage: whisper-snip [options] [prompt] [input_dir]"
    echo "  -m <model>     Model name (default: large-v3-turbo)"
    echo "  -o <file>      Output file path (default: <input_dir>/transcriptions.md)"
    echo "  -s <seconds>   Snip duration in seconds (default: 120)"
    echo "  -mc <n>        Max context tokens from previous segment (default: 0, reduces hallucinations)"
    echo "  -w             Overwrite output file (appends by default)"
    echo ""
    echo "  prompt         Optional hint for whisper (e.g. 'voice memos from the Diel Drivers experiment')"
    echo "  input_dir      Directory to search (default: current directory)"
    exit 1
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m)  MODEL="$2";        shift 2 ;;
        -o)  OUTPUT_FILE="$2";  shift 2 ;;
        -s)  SNIP_SECONDS="$2"; shift 2 ;;
        -mc) MAX_CONTEXT="$2";  shift 2 ;;
        -w)  OVERWRITE=true;    shift ;;
        -*)  usage ;;
        *)   POSITIONAL+=("$1"); shift ;;
    esac
done

WHISPER_PROMPT="${POSITIONAL[0]:-}"
INPUT_DIR="${POSITIONAL[1]:-.}"

# If first positional looks like a directory (or is absent), treat it as input_dir with no prompt
if [ -d "$WHISPER_PROMPT" ]; then
    INPUT_DIR="$WHISPER_PROMPT"
    WHISPER_PROMPT=""
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

# Find all mp3/wav files recursively
mapfile -t files < <(find "$INPUT_DIR" -type f \( -iname "*.mp3" -o -iname "*.wav" \) -not -iname "*_snip.wav" | sort)
total=${#files[@]}
count=0

for f in "${files[@]}"; do
    count=$((count + 1))
    filename=$(basename "$f")
    rel_path="${f#$INPUT_DIR/}"
    snip_path="${f%.*}_snip.wav"

    if [ "$OVERWRITE" = false ] && [ -f "$OUTPUT_FILE" ] && grep -qF "# $rel_path" "$OUTPUT_FILE"; then
        echo "[$count/$total] Skipping (already transcribed): $rel_path"
        continue
    fi

    echo "[$count/$total] Snipping + transcribing: $rel_path"

    # Snip first N seconds to a wav using ffmpeg
    ffmpeg -y -i "$f" -t "$SNIP_SECONDS" -ar 16000 -ac 1 \
        -af "afade=t=out:st=$((SNIP_SECONDS - 3)):d=3" \
        "$snip_path" -loglevel error

    if [ ! -f "$snip_path" ]; then
        echo "  Warning: ffmpeg failed for $filename, skipping"
        continue
    fi

    # Run whisper, strip timestamps and non-speech tokens
    prompt_arg=()
    [ -n "$WHISPER_PROMPT" ] && prompt_arg=(--prompt "$WHISPER_PROMPT")
    transcript=$("$WHISPER_BIN" -m "$MODEL_PATH" -f "$snip_path" -mc "$MAX_CONTEXT" "${prompt_arg[@]}" 2>/dev/null \
        | sed 's/\[[0-9:\.]* --> [0-9:\.]*\][[:space:]]*//' \
        | sed '/^[[:space:]]*[\[\(*]/d' \
        | sed '/^[[:space:]]*$/d')

    # Delete the snip wav
    rm -f "$snip_path"

    # Skip if no speech detected (empty, whitespace, or only bracketed tokens)
    stripped=$(echo "$transcript" | sed '/^[[:space:]]*[\[\(]/d' | tr -d '[:space:]')
    if [ -z "$stripped" ]; then
        echo "  No speech detected"
        echo "# $rel_path" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "[no speech detected]" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "---" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        continue
    fi

    # Append to output
    echo "# $rel_path" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "$transcript" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "---" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
done

echo "Done. Output: $OUTPUT_FILE"
