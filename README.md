# Diane

A personal secretary for organizing voice memos from the field. Diane is directly inspired by Matt Webb's post ["Diane, I wrote a lecture by talking about it"](https://interconnected.org/home/2025/03/20/diane). Point the Diane script at a directory holding all of your voice memos and get a tidy transcription written to notes.md. The script leverages [whisper.cpp](https://github.com/ggerganov/whisper.cpp) to transcribe all audio recordings in a folder, then hands them to Diane (running on Claude Code) to organize. Diane is meant to clean and organize notes, not summarize them. All of the original information should appear in the output and all notes are written in the tone and perspective you recorded them in. You can also address Diane directly to issue instructions about how to handle the notes, e.g. "Diane, remove that previous note about bad weather, it's cleared up now." Diane will follow the action and make a small note of it at the bottom of the output file. See the system prompt [DIANE.md](DIANE.md) for more information about how Diane handles transcriptions.

This repo reflects the working state of my Diane tool, which raises two warnings. Firstly, this repo is unlikely to be stable and has not be tested on other machines. Second, I am optimizing Diane for my use-case in field research. Essentially, I'm replacing my lab notebook with voice memos + Diane. As such, I am liable to insert idiosyncracies into the pipeline to fine-tune for my work. I've taken a few steps to make it easier for you, dear reader, to adapt, but generalization is a second-tier priority for me.

## Pipeline

1.  **whisper-dir.sh** runs [whisper.cpp](https://github.com/ggerganov/whisper.cpp) on every audio file in the current directory and concatenates the results into `transcriptions.md`.
    -   By default, whisper-dir skips already-transcribed files
    -   If you add new files to the directory, whisper-dir will append them to an existing `transcriptions.md`
2.  **Diane** feeds that transcript to Claude with the system prompt in `DIANE.md`, writing the result to `notes.md`.

## Command hierarchy

Diane follows instructions based on the hierarchy:

1.  Special instructions - any special instructions to Diane with the optional positional argument when calling the tool
2.  Voice memos - direct commands to Diane in the voice memos override the system prompt. So you can overwrite the default formatting instructions by saying, "Diane, this isn't a lab notebook entry, I'm going to record a discussion about data cleaning that we need to do. I would like you to create a list of action items organized by filename."
3.  System prompt - the contents of [DIANE.md](DIANE.md)

## Requirements

-   [whisper.cpp](https://github.com/ggerganov/whisper.cpp) built locally
-   [Claude Code CLI](https://github.com/anthropics/claude-code) installed and authenticated

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
```

## Usage

```         
Diane [-m model] [-e effort] [-w whisper-model] [-h] [instruction]

Options:
  -m <model>         Claude model to use (default: sonnet)
                     Aliases: sonnet, opus, haiku
                     Full IDs: claude-sonnet-4-6, claude-opus-4-7, etc.
  -e <level>         Thinking effort: low, medium, high, xhigh, max (default: medium)
  -w <whisper-model> Whisper model to use (default: from config, or medium.en)
                     Examples: tiny.en, base.en, small.en, medium.en, large-v3
  -h                 Show this help message

Arguments:
  instruction  Optional note to Diane about how to handle this session
```

**Examples:**

``` bash
# Defaults — transcribe and summarize everything in the current directory
Diane

# Write a comment to Diane regarding the notes
Diane "This is a one-off recording as I taught undergrads the protocol; please write this one up as a numbered research protocol"

# Higher thinking effort with Haiku
Diane -m haiku -e high

# A lightweight transcription
Diane -m haiku -e low -w tiny.en
```

`whisper-dir` can also be used standalone:

```         
whisper-dir [options] <input_dir>

  -m <model>   Whisper model name (default: from config, or medium.en)
  -o <file>    Output file (default: <input_dir>/transcriptions.md)
  -t           Keep timestamps (stripped by default)
  -f           Overwrite output file instead of appending
```