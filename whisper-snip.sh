#!/usr/bin/env bash

WHISPER_BIN="${WHISPER_BIN:-$HOME/Tools/whisper.cpp/build/bin/whisper-cli}"
MODEL_DIR="${WHISPER_MODEL_DIR:-$HOME/Tools/whisper.cpp/models}"
MODEL="${WHISPER_DEFAULT_MODEL:-large-v3-turbo}"
SNIP_SECONDS=120
OVERWRITE=false
OUTPUT_FILE=""
MAX_CONTEXT=0
FIRST_FILE=false
TS_PATTERN='[0-9]{6}_[0-9]{4}'

usage() {
    echo "Usage: whisper-snip [options] [prompt] [input_dir]"
    echo "  -m <model>     Model name (default: large-v3-turbo)"
    echo "  -o <file>      Output file path (default: <input_dir>/transcriptions.md)"
    echo "  -s <seconds>   Snip duration in seconds (default: 120)"
    echo "  -mc <n>        Max context tokens from previous segment (default: 0, reduces hallucinations)"
    echo "  -w             Overwrite existing transcripts (skips them by default)"
    echo "  -ff            First-file mode: only transcribe the chronologically first file per directory"
    echo "  -tp <pattern>  ERE pattern to extract timestamp from filename (default: '[0-9]{6}_[0-9]{4}')"
    echo "                 The pattern is matched anywhere in the filename stem; surrounding clutter is ignored."
    echo "                 Matched strings are compared lexicographically, so zero-padded formats work naturally."
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
        -ff) FIRST_FILE=true;   shift ;;
        -tp) TS_PATTERN="$2";   shift 2 ;;
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

OUTPUT_FILE="${OUTPUT_FILE:-$INPUT_DIR/transcriptions_snip.md}"
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

# Extract timestamp token from a filename using an ERE pattern.
# Matches the pattern anywhere in the basename, ignoring surrounding clutter.
extract_timestamp() {
    local filepath="$1"
    local pattern="$2"
    basename "$filepath" | grep -oE "$pattern" | head -1
}

# Returns 0 if ffprobe can read at least one audio stream; 1 otherwise.
is_readable_audio() {
    ffprobe -v error -select_streams a:0 -show_entries stream=codec_type \
        -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null | grep -q audio
}

# Find all mp3/wav files recursively
mapfile -t files < <(find "$INPUT_DIR" -type f \( -iname "*.mp3" -o -iname "*.wav" \) -not -iname "*_snip.wav" | sort)

SMALL_FILE_BYTES=10240         # 10 KB — skip as too-small to be a real recording
ALSO_NEXT_BYTES=$((10*1024*1024))  # 10 MB — also snip next file when selected file is under this

# In first-file mode, reduce to only the earliest file(s) per immediate parent directory.
# Files under SMALL_FILE_BYTES are skipped; the next chronological file is promoted.
# If the selected first file is under ALSO_NEXT_BYTES, the following file is also included.
if [ "$FIRST_FILE" = true ]; then
    declare -A dir_sorted  # dir -> newline-separated "ts|filepath" pairs

    for f in "${files[@]}"; do
        dir=$(dirname "$f")
        ts=$(extract_timestamp "$f" "$TS_PATTERN")
        if [ -z "$ts" ]; then
            echo "Warning: no timestamp match in '$(basename "$f")' — skipping for first-file selection"
            continue
        fi
        dir_sorted[$dir]+="$ts|$f"$'\n'
    done

    files=()
    for dir in "${!dir_sorted[@]}"; do
        # Sort entries by timestamp, extract paths in order
        sorted_paths=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && sorted_paths+=("${line#*|}")
        done < <(printf '%s' "${dir_sorted[$dir]}" | sort)

        # Walk sorted list; skip files under SMALL_FILE_BYTES or unreadable by ffprobe
        first_selected=""
        first_idx=-1
        for i in "${!sorted_paths[@]}"; do
            candidate="${sorted_paths[$i]}"
            size=$(stat -f%z "$candidate" 2>/dev/null)
            if [[ "${size:-0}" -lt "$SMALL_FILE_BYTES" ]]; then
                echo "  Skipping small file ($(( ${size:-0} / 1024 ))KB < 10KB): $(basename "$candidate")"
                continue
            fi
            if ! is_readable_audio "$candidate"; then
                echo "  Skipping unreadable file: $(basename "$candidate")"
                continue
            fi
            first_selected="$candidate"
            first_idx=$i
            break
        done

        [[ -z "$first_selected" ]] && continue
        files+=("$first_selected")

        # If the selected file is under ALSO_NEXT_BYTES, also snip the next valid file
        first_size=$(stat -f%z "$first_selected" 2>/dev/null)
        if [[ "${first_size:-0}" -lt "$ALSO_NEXT_BYTES" ]]; then
            for (( j = first_idx + 1; j < ${#sorted_paths[@]}; j++ )); do
                candidate="${sorted_paths[$j]}"
                next_size=$(stat -f%z "$candidate" 2>/dev/null)
                if [[ "${next_size:-0}" -ge "$SMALL_FILE_BYTES" ]] && is_readable_audio "$candidate"; then
                    echo "  First file under 10MB — also including next: $(basename "$candidate")"
                    files+=("$candidate")
                    break
                fi
            done
        fi
    done

    IFS=$'\n' files=($(printf '%s\n' "${files[@]}" | sort))
    unset IFS
fi

total=${#files[@]}
count=0

if [ "$OVERWRITE" = true ]; then
    > "$OUTPUT_FILE"
fi

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
