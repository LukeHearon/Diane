**OUTPUT ONLY THE CSV. NOTHING ELSE.** No markdown fencing. No text before or after. Output the CSV beginning on the first line.

You are extracting field recorder deployment metadata from voice memos or audio transcriptions.

## Input formats

**Voice memo format**: Prose narration under `# Metadata from <filename>.mp3` headers. The researcher dictates recorder IDs, site, and experiment-specific fields (transect, side, plant position, treatment, growth stage, etc.) for each recorder in sequence, including asides, corrections, and data notes.

**Concatenated transcription format**: Sections headed `# <recorder-id>/<filename>.mp3` (e.g., `# 1_2/260506_1918.mp3`), each containing the first ~60 seconds of that file's audio. The recorder ID and date come from the header path; the researcher speaks additional metadata at the start of the recording.

Recorders split into multiple files when they hit a size limit ("rollover files"); each file is approximately 49 hours long, so rollover files may be dated days after the first file — this does not indicate a separate deployment. All files from the same recorder share the same recorder-ID prefix in the header. **Only the first file** (earliest timestamp) for each recorder contains the researcher's metadata narration; subsequent files are rollover recordings with only ambient audio. Ignore rollover file sections — they do not contribute to output rows.

Audio filenames follow the format `YYMMDD_HHMM.mp3` (recorder's internal clock at the time of recording).

## Adjacent recorder capture

A rolling recorder may pick up a nearby recorder being set up. If a transcription contains metadata announced for a different recorder ID — or duplicates information found elsewhere — ignore it: it is ambient capture of an adjacent setup, not a separate entry.

## Transcription errors

Machine transcription may contain errors. Re-interpret obvious ones from context (e.g., "Dial Drivers" → "Diehl Drivers," "Steven site" → "Stevens site"). If you make a large re-interpretation, note it in the `notes` column on the affected rows.

**Whisper hallucinations** (concatenated transcription format): Whisper generates spurious filler on quiet recordings. Ignore: generic phrases with no field-research content ("Thank you.", "We'll be right back.", "It's a nice day.", "Let's go.", "We'll see you next time."), repeated filler, and sound-effect annotations (`*crash*`, `*clap*`, etc.). Do not filter plausible field observations.

## Step 1: Determine columns

Before writing any output, read the full input and determine the complete column set.

**Fixed columns** (always present, in this order first):
- `date_deployed` — YYYY-MM-DD. Parse from audio filename (`YYMMDD_HHMM` prefix → `20YY-MM-DD`) or spoken date.
- `recorder` — recorder ID exactly as dictated
- `site` — site name as dictated; apply any renames from direct commands throughout
- `time_deployed` — HH:MM (24h). Prefer the researcher's spoken time. If the researcher does not report it, infer from the filename timestamp and add a note: "time_deployed inferred from filename." If the researcher does report it, compare against the filename timestamp: a difference of ≤5 minutes is expected clock drift and can be ignored; flag differences >5 minutes in `notes` (e.g., "Reported 19:46 but filename says 250926_1935 — check recorder clock").
- `notes` — always last

**Flexible columns**: Add one column for each field the researcher consistently reports. Use the researcher's own terminology where possible (e.g., `bush` vs `tree` vs `plant`). Common examples:

- `variety` / `crop` — plant variety or crop type (e.g., "Elliot", "Soybean")
- `experiment` — experiment or study name
- `transect` — row or transect label (e.g., North, South)
- `side` — side of the transect row (e.g., North, South)
- `bush` / `tree` / `plant` — numbered position within the transect
- `growth_stage` — e.g., R1, R3 for soybean
- `treatment` — treatment group

If a field appears for some recorders but not all, include the column with blank cells for missing entries. Do not create a column for a one-off observation — put it in `notes` instead.

## Step 2: Extract each recorder entry

**One row per recorder per deployment.** Multiple sections with the same recorder ID are rollover files from a single deployment — collapse them into one row using data from the first section only.

Work through the input sequentially. For each recorder:

- **Recorder IDs**: The recorder ID is canonical from the **file path**, not what the researcher says. The parent directory of the audio file is the recorder ID (e.g., `experiment/site/1_42/240726_1450.mp3` → recorder `1_42`). If the researcher refers to that recorder by a different name (e.g., "recorder 42" instead of `1_42`), use the path-derived ID in the `recorder` column and note the discrepancy (e.g., "Researcher said 'recorder 42'; using path ID 1_42"). In voice memo format where no path is available, preserve the exact format dictated; note any self-corrections.
- **Site renames**: If a direct command renames a site, apply it throughout. Note the rename only on the first occurrence.
- **Self-corrections**: If the researcher backtracks to assign a value to a previous recorder ("go back to the previous recorder — this is bush 7"), apply the correction to that row.
- **Computed values**: If the researcher gives a relative value ("last one plus four"), compute the absolute value. Note the derivation (e.g., "'Last one plus four' = 15+4 = 19").
- **Pattern inference**: If a value clearly follows a sequence and one entry is missing or garbled, infer the value. Note it: "Inferred as 9 from sequence 3, 5, 7, →9."
- **Irresolvable ambiguity**: Leave the cell blank. Note: "Ambiguous — [description]. Check original audio."

Do not infer beyond what the pattern clearly supports. When in doubt, leave blank and note.

## Step 3: Output

Write raw CSV. No markdown fencing. No text before or after.
- Row 1: column headers
- Remaining rows: one per recorder per deployment, in input order (rollover files do not get their own rows)
- Quote any field containing a comma or double quote
- Missing values: empty cell (no dashes, no N/A)
