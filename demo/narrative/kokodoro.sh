#!/bin/bash
# Convert all .txt files in demo/narrative/ to .wav using kokorodoki TTS

REPO_ROOT="$HOME/git/aicatalyst-team/aicr-example-deployments"
NARRATIVE_DIR="demo/narrative"
VOICE="af_kore" # Use --list-voices to get a list of available voices
SPEED=1.20
LANGUAGE=a # Use --list-languages to get a list of languages

if [ -n "$1" ]; then
    txt_files=("$1")
    if [ ! -f "${txt_files[0]}" ]; then
        echo "Error: ${txt_files[0]} not found"
        exit 1
    fi
else
    txt_files=("${REPO_ROOT}/${NARRATIVE_DIR}"/*.txt)
fi
count=0
for txt_file in "${txt_files[@]}"; do
    basename=$(basename "$txt_file" .txt)
    wav_file="${NARRATIVE_DIR}/${basename}.wav"
    echo "Converting ${NARRATIVE_DIR}/${basename}.txt -> ${wav_file}"
    docker run --cpus 21 -t -e SKIP_STARTUP_MSG=1 \
        -v "${REPO_ROOT}:/mnt:Z" -w /mnt --rm \
        mltframework/kokorodoki \
        -l a -v ${VOICE} -s ${SPEED} -l ${LANGUAGE} \
        -f "${NARRATIVE_DIR}/${basename}.txt" \
        -o "${wav_file}"
    count=$((count+1))
done

echo "Done. Generated ${count} wav files."
