spinner_start() {
    SPINNER_MSG="$(awk 'BEGIN{srand()} {lines[NR]=$0} END{print lines[int(rand()*NR)+1]}' "$DIANE_DIR/lib/loading_lines.txt")"
    (while true; do
        printf "\r%s.  " "$SPINNER_MSG"; sleep 0.4
        printf "\r%s.. " "$SPINNER_MSG"; sleep 0.4
        printf "\r%s..." "$SPINNER_MSG"; sleep 0.4
    done) &
    SPINNER_PID=$!
}

spinner_stop() {
    kill $SPINNER_PID 2>/dev/null
    wait $SPINNER_PID 2>/dev/null
    printf "\r%s    \n" "$SPINNER_MSG"
}
