# Diane

A personal secretary for transcripting and organizing voice memos from field work, directly inspired by Matt Webb's post ["Diane, I wrote a lecture by talking about it"](https://interconnected.org/home/2025/03/20/diane). I'm developing Diane for my bioacoustics experiments, so the capabilities may be a little particular to my work. Essentially, I'm replacing my lab notebook with voice memos + Diane, and replacing hand-written metadata with automatic extraction from our recorders. I also intend to test out voice memos as my primary method of data collection, but that's a later poject.

Diane doesn't just organize notes, she can execute instructions you give in the voice memos themselves. For example, in the middle of taking a voice memo you could say, "Diane, split the weather notes into two subheadings, one for temperature and one for precipitation." Diane will follow all instructions in the voice memos with a _higher_ level of 

This repo is unlikely to be stable and has not been tested on machines other than mine. I've taken a few steps to make it easier for other people to try out the tool, but generalization is not a priority for me at this moment.




## Pipelines

Diane currently has two actions: notes and metadata.

### `Diane notes`

Point Diane at a directory and use the "notes" action to organize field notes into a tidy `notes.md`. 

1.  **whisper-dir.sh** runs [whisper.cpp](https://github.com/ggerganov/whisper.cpp) on every audio file in the current directory and concatenates the results into `transcriptions.md`.
    -   By default, whisper-dir skips already-transcribed files
    -   If you add new files to the directory, whisper-dir will append them to an existing `transcriptions.md`
2.  **Diane** feeds that transcript to Claude with the system prompt in `lib/notes.md` and outputs Diane's work to `notes.md` in the working directory.

Diane is meant to clean and organize notes, not summarize them — all of the original information should appear in the output, written in the tone and perspective you recorded it in. You can also address Diane directly in a memo to issue instructions, e.g. "Diane, remove that previous note about bad weather, it's cleared up now." See the system prompts in `lib/` for more detail on how each action handles its input.

### `Diane metadata`


Or, if you're deploying field recorders, use `Diane metadata` to pull recorder IDs, sites, positions, and other deployment fields from the first few seconds of each file into a `metadata.csv`. Both actions use [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for transcription and Claude Code for the AI step.

1.  **whisper-snip.sh** trims the first N seconds (default: 120) from each audio file, transcribes each snip, and concatenates the results into `metadata_transcriptions.md`.
2.  **Diane** feeds that transcript to Claude with the system prompt in `lib/metadata.md`, writing the result to `metadata.csv`.

## Command hierarchy

Both actions follow the same instruction hierarchy:

1.  Special instructions — an optional positional argument passed when calling Diane
2.  Voice memos — direct commands to Diane in the memos override the system prompt. E.g., "Diane, this isn't a lab notebook entry, I'm going to record a discussion about data cleaning that we need to do. I would like you to create a list of action items organized by filename."
3.  System prompt — the contents of `lib/notes.md` or `lib/metadata.md`

## Platform

macOS only. The scripts use `/bin/zsh` and have not been tested on Linux or Windows.

## Requirements

-   [whisper.cpp](https://github.com/ggerganov/whisper.cpp) built locally
-   [Claude Code CLI](https://github.com/anthropics/claude-code) installed and authenticated
-   [ffmpeg](https://ffmpeg.org/) (required for `Diane metadata` only)
-   [jq](https://jqlang.org/) (required for `-v` verbose mode only)

## Setup

**1. Build whisper.cpp and download a model**

``` bash
git clone https://github.com/ggerganov/whisper.cpp
cd whisper.cpp
cmake -B build && cmake --build build -j
bash models/download-ggml-model.sh medium.en
```

**2. Configure Diane**

[config.txt](config.txt) points to your whisper-cli binary and whisper model directory. Edit this file to point to your whisper installation.

**3. Put the scripts on your PATH**

``` bash
ln -s /path/to/diane/Diane /usr/local/bin/Diane
ln -s /path/to/diane/whisper-dir.sh /usr/local/bin/whisper-dir
ln -s /path/to/diane/whisper-snip.sh /usr/local/bin/whisper-snip
```

## Usage

```         
Diane <action> [flags] [message]

Actions:
  notes      Transcribe audio files and organize into notes.md
  metadata   Extract recorder deployment metadata into metadata.csv

Arguments:
  message  Optional message passed directly to Diane (overrides everything else)

Run 'Diane notes -h' or 'Diane metadata -h' for action-specific flags.
```

The only positional arguments are the action and the optional message to Diane. Everything else is a flag.

### `Diane notes`

```         
Diane notes [flags] [message]

Flags:
  -m <model>   Claude model to use (default: sonnet)
               Aliases: sonnet, opus, haiku
               Full IDs: claude-sonnet-4-6, claude-opus-4-7, etc.
  -e <level>   Thinking effort: low, medium, high, xhigh, max (default: medium)
  -w <model>   Whisper model to use (default: from config, or medium.en)
               Examples: tiny.en, base.en, small.en, medium.en, large-v3
  -mc <n>      Max context tokens from previous segment (default: 0, reduces hallucinations)
  -d           Delete transcriptions.md after notes.md is written
  -v           Print Claude's thinking after run completes (requires jq)
  -h           Show this help message
```

**Examples:**

``` bash
# Defaults — transcribe and organize everything in the current directory
Diane notes

# Message to Diane
Diane notes "This is a one-off recording as I taught undergrads the protocol; please write this one up as a numbered research protocol"

# Higher thinking effort with Haiku
Diane notes -m haiku -e high

# A lightweight transcription
Diane notes -m haiku -e low -w tiny.en
```

### `Diane metadata`

```         
Diane metadata [flags] [message]

Flags:
  -m <model>    Claude model to use (default: sonnet)
                Aliases: sonnet, opus, haiku
                Full IDs: claude-sonnet-4-6, claude-opus-4-7, etc.
  -e <level>    Thinking effort: low, medium, high, xhigh, max (default: medium)
  -w <model>    Whisper model to use (default: from config, or large-v3-turbo)
                Examples: tiny.en, base.en, small.en, medium.en, large-v3
  -s <seconds>  Audio snip duration in seconds (default: 120)
  -wp <prompt>  Transcription hint passed to whisper
  -mc <n>       Max context tokens from previous segment (default: 0)
  -d            Delete metadata_transcriptions.md after metadata.csv is written
  -v            Stream Claude's thinking in real time (requires jq)
  -h            Show this help message
```

**Examples:**

``` bash
# Defaults — snip and extract metadata from everything in the current directory
Diane metadata

# Message to Diane
Diane metadata "Add a varieties column where every entry is Elliot"

# Give whisper a hint about the recording context
Diane metadata -wp "voice memos from the Diel Drivers experiment"

# Shorter snips if you narrate metadata quickly
Diane metadata -s 60

# Combine flags and a message
Diane metadata -m opus -e high "Recorders 3 and 4 were swapped — correct in output"
```

`whisper-dir` and `whisper-snip` can also be used standalone. Both default to the current directory, so you can call either with no arguments.

**`whisper-dir`** — transcribes all audio files in a directory and concatenates the results into a single markdown file.

```
whisper-dir [options] [input_dir]

  -m <model>   Whisper model name (default: large-v3-turbo)
  -o <file>    Output file (default: <input_dir>/transcriptions.md)
  -t           Keep timestamps (stripped by default)
  -f           Overwrite existing transcripts (skips them by default)
  -mc <n>      Max context tokens from previous segment (default: 0)
  input_dir    Directory to transcribe (default: current directory)
```

**`whisper-snip`** — like `whisper-dir`, but trims each file to the first N seconds before transcribing. Useful when you only need the beginning of each recording (e.g. recorder deployment metadata).

```
whisper-snip [options] [prompt] [input_dir]

  -m <model>     Whisper model name (default: large-v3-turbo)
  -o <file>      Output file (default: <input_dir>/transcriptions.md)
  -s <seconds>   Snip duration in seconds (default: 120)
  -mc <n>        Max context tokens from previous segment (default: 0)
  -w             Overwrite existing transcripts (skips them by default)
  prompt         Optional transcription hint passed to whisper
  input_dir      Directory to search (default: current directory)
```
