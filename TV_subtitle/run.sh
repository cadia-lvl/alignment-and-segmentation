#!/usr/bin/env bash

# Copyright 2020 Inga Rún Helgadóttir

# Get data in the format that Kaldi wants before aligning and segmenting the
# data.

# Start by getting subtitle data but since the timestamps are often off, put
# all the text together and resegment.
# There are no speaker IDs so for the segmentation use a single sudo one for
# everyone and see whether that will be good enough.
# Extract the same data as Judy has for diarization(ruvdi) to be able to assign
# speaker IDs later.

# Run from H2 directory

# NOTE! segment_long_utterances_nnet3.sh creates new speaker IDs, how should I
# treat spkIDs up to that point?
# Split into multiple unknown speakers or not? I guess multiple is better.

set -eo pipefail

stage=0

srcdir=/models/althingi/acoustic_model/chain/5.4/tdnn/20190114
langdir=$srcdir/lmdir/lang
extractor=$srcdir/extractor
corpusdir=/data/misc/ruv-di/version0002
normalize=true

. ./path.sh
. ./cmd.sh

# Create these symlinks before running:
ln -sfn "$KALDI_ROOT"/egs/wsj/s5/steps steps
ln -sfn "$KALDI_ROOT"/egs/wsj/s5/utils utils

if [ "$1" == "-h" ]; then
  echo "Create ASR training data from TV recordings and subtitle data,"
  echo "paired with diarization data for speaker info"
  echo "Usage: $(basename $0) [-h]"
  exit 0
fi

# This parses the --stage option if supplied
. utils/parse_options.sh || exit 1;

# change path for $data, $exp and $mfcc in conf/path.conf
datadir="$data"/h2/asr_ruvdi
ruvdi="$datadir"/../ruv-di
expdir="$exp"/h2/segmentation
mfcc="$mfcc"

# Test the existance of input data and models
for d in $srcdir $langdir $extractor; do
  [ ! -d "$d" ] && echo "$0: expected $f to exist" && exit 1;
done

for f in $corpusdir/reco2spk_num2spk_label.csv; do
  [ ! -f "$f" ] && echo "$0: expected $f to exist" && exit 1;
done

# Check if expand-numbers is installed and install it otherwise
if "$normalize" && ! command -v expand-numbers &> /dev/null; then
  tar zxvf ../tools/expand-numbers-linux-amd64.tar.gz -d $KALDI_ROOT/src/fstbin
fi

if [ $stage -le 0 ]; then
  mkdir -p "$datadir"/log "$expdir" "$mfcc" "$ruvdi"
  
  cp $corpusdir/reco2spk_num2spk_label.csv "$ruvdi"
fi

if [ $stage -le 1 ]; then
  # From a list of recording IDs fetch the subtitles. List from Judy's diarization dir
  echo 'Extract subtitle files from RUV'
  mkdir -p "$datadir"/vtt
  for path in "$corpusdir"/wav/*; do
    file=$(basename "$path")
    php local/extract_vtt.php "${file%.*}" "$datadir"/vtt
  done
fi

if [ $stage -le 2 ]; then
  echo 'Create the files necessary for Kaldi'
  echo 'Create text files out of vtt subtitle files'
  for file in "$datadir"/vtt/*.vtt; do
    name=$(basename "$file")
    python3 local/extract_text.py \
    "$file" "$datadir"/transcripts/"${name%.*}"
  done
  
  echo 'Create wav.scp'
  for path in "$datadir"/transcripts/*; do
    name=$(basename "$path")
    echo -e "${name}"' sox -twav - -c1 -esigned -r16000 -G -twav - < '"$corpusdir/wav/${name}".wav' |' >> "$datadir"/wav.scp
  done
  
  echo "Create a segments file"
  while IFS= read -r line
  do
    name=$(basename "$line")
    dur=$(soxi -D "$line")
    number=$(LC_NUMERIC="en_US.UTF-8" printf "%.7g" "$dur")
    echo -e unknown-"${name%.*}" "${name%.*}" 0 "$number" >> "$datadir"/segments
  done < <(cut -d' ' -f12 "$datadir"/wav.scp)
  
  echo 'Create utt2spk'
  for path in "$datadir"/transcripts/*; do
    name=$(basename "$path")
    echo -e unknown-"${name}"' unknown' >> "$datadir"/utt2spk
  done
  
  echo 'Create spk2utt'
  utils/utt2spk_to_spk2utt.pl < "$datadir"/utt2spk > "$datadir"/spk2utt
fi

if [ $stage -le 3 ]; then
  echo 'Because of incorrect subtitle timestamps. Join the text segments from each file together into a line with uttID'
  # All subtitles of a file are joined into one text connected to an uttID
  # and the text from all files are put into one. One line per recording
  for path in "$datadir"/transcripts/*; do
    name=$(basename "$path")
    if [ -f "$datadir"/transcripts/"${name}"/text ]; then
      cut -d' ' -f2- "$datadir"/transcripts/"${name}"/text \
      | tr '\n' ' ' | sed -r "s/.*/unknown-${name} &/" \
      >> "$datadir"/raw_text
      echo >> "$datadir"/raw_text
    fi
  done
fi

if $normalize && [ $stage -le 4 ]; then
  echo 'Clean the text'
  utils/slurm.pl --mem 4G "$datadir"/log/clean_text.log \
  local/clean_text.sh "$datadir"/raw_text "$datadir"/text_cleaned &
  wait
  # NOTE! Fix the uttIDs
  sed -i -r 's/^(unknown) ([0-9]+) ([a-z]) ([0-9])/\1-\2\u\3\4/' "$datadir"/text_cleaned
  
  # NOTE! We use code for the expansion that is not in the official Kaldi version.
  # TO DO: Extract those files from our Kaldi src dir and ship with this recipe
  echo 'Expand abbreviations and numbers'
  utils/slurm.pl --mem 4G "$datadir"/log/expand_text.log \
  local/expand_text.sh "$datadir"/text_cleaned "$datadir"/text_expanded
  
  echo "Remove punctuations to make the text better fit for acoustic modelling."
  sed -re 's: [^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö ] : :g' -e 's: +: :g' \
  < "${datadir}"/text_expanded > "$datadir"/text || exit 1;
  
  utils/validate_data_dir.sh --no-feats "$datadir" || utils/fix_data_dir.sh "${datadir}" || exit 1;
else
  cp "$datadir"/raw_text "$datadir"/text
  
fi

if [ $stage -le 5 ]; then
  echo "Extract high resolution features which are used with Kaldi's nnet models"
  steps/make_mfcc.sh \
  --nj 20 \
  --mfcc-config conf/mfcc_hires.conf \
  --cmd "$decode_cmd" \
  "${datadir}" \
  "$expdir"/make_hires/ "$mfcc"
  
  utils/validate_data_dir.sh "${datadir}" || utils/fix_data_dir.sh "${datadir}" || exit 1;
fi

if [ $stage -le 6 ]; then
  # Estimate the OOV rate to see whether I need to update my lexicon
  # cut -d' ' -f2- "${datadir}"/text | tr ' ' '\n' | sort |uniq -c > "${datadir}"/words.cnt
  # comm -23 <(awk '$2 ~ /[[:print:]]/ { print $2 }' "${datadir}"/words.cnt | sort) <(cut -d" " -f1 $langdir/words.txt | sort) > "${datadir}"/vocab_text_only.tmp
  # join -1 1 -2 1 "${datadir}"/vocab_text_only.tmp <(awk '$2 ~ /[[:print:]]/ { print $2" "$1 }' ${datadir}/words.cnt | sort -k1,1) | sort | awk '{total = total + $2}END{print total}'
  # # Get 2.3% OOV rate. I think that is ok.
  
  echo "Create crude shorter segments using an out-of-domain recognizer"
  utils/slurm.pl --mem 8G "$datadir"/log/segmentation_long_utterances.log \
  steps/cleanup/segment_long_utterances_nnet3.sh \
  --nj 20 \
  --extractor "$extractor" \
  "$srcdir" "$langdir" \
  "${datadir}" "${datadir}"_segm_long \
  "$expdir"/long
  
  utils/validate_data_dir.sh "${datadir}"_segm_long || utils/fix_data_dir.sh "${datadir}"_segm_long
  
  steps/make_mfcc.sh \
  --nj 20 \
  --mfcc-config conf/mfcc_hires.conf \
  --cmd "$decode_cmd" \
  "${datadir}"_segm_long \
  "$expdir"/make_hires/ "$mfcc"
fi

if [ $stage -le 7 ]; then
  echo "Re-segment using an out-of-domain recognizer"
  utils/slurm.pl --mem 8G "$datadir"/log/segmentation.log \
  steps/cleanup/clean_and_segment_data_nnet3.sh \
  --nj 20 \
  --extractor "$extractor" \
  "${datadir}"_segm_long "$langdir" \
  "$srcdir" "$expdir" \
  "${datadir}"_reseg &
  wait
  
  # Calculate the duration of the new segments
  utils/data/get_utt2dur.sh "${datadir}"_reseg
  awk '{sum = sum + $2}END{print sum, sum/NR}' "${datadir}"_reseg/utt2dur
  # Get 17494.2 seconds, i.e. around 4 hrs and 50 min, for Judy's ruv-di set. Average segment length is 4.3 sek
  # Sum of Judy's diarization segments is 25123.2 seconds or almost 7 hrs.
  # Original length of audio was 8.3 hrs
  
  # The segmentation process created very long suffices on the utterance IDs.
  # Shorten them. I can do that since these are not coupled to real speaker IDs.
  mv "${datadir}"_reseg/segments "${datadir}"_reseg/segments_orig
  i=0
  while IFS= read -r line
  do
    printf -v j "%05d" "$i" # Pad the suffix with zeros
    echo "$line" | sed -r "s/^(unknown-[^-]+)[^ ]+/\1-$j/" >> "${datadir}"_reseg/segments
    i=$((i+1))
  done < <(grep -v '^ *#' < "${datadir}"_reseg/segments_orig)
  
  # Change the suffices in text as well
  mv "${datadir}"_reseg/text "${datadir}"_reseg/text_orig
  i=0
  while IFS= read -r line
  do
    printf -v j "%05d" "$i" # Pad the suffix with zeros
    echo "$line" | sed -r "s/^(unknown-[^-]+)[^ ]+/\1-$j/" >> "${datadir}"_reseg/text
    i=$((i+1))
  done < <(grep -v '^ *#' < "${datadir}"_reseg/text_orig)
fi

if [ $stage -le 8 ]; then
  echo 'Process RUV diarization data, since it contains speaker information. Then I can compare the new segments'
  echo 'to the diarization segments and extract speaker information'
  
  # Since the first file has a different kind of spkIDs I need to get them on the same format as in the other files.
  cp -r $corpusdir/json/ "$ruvdi"
  sed -re 's/([0-9]+)[A-ZAÐEIOUYÞÆÖa-zaðeiouyþæö]+[0-9]+/\1/g' \
  -e 's/([0-9]+)[A-ZAÐEIOUYÞÆÖa-zaðeiouyþæö]+/\1/g' \
  < "$ruvdi"/json/4886083R7.json \
  > "$ruvdi"/json/4886083R7_new.json
  
  mv "$ruvdi"/json/4886083R7_new.json "$ruvdi"/json/4886083R7.json
  
  for path in "$ruvdi"/json/* ; do
    file=$(basename "$path")
    python3 local/parse_json.py "$ruvdi"/json/"$file" "$ruvdi"
  done
  
  for f in "$ruvdi"/*/ruvdi_segments; do (cat "${f}"; echo) >> "$ruvdi"/all_segments; done
  grep -Ev '^$' "$ruvdi"/all_segments | tr '-' ' ' > tmp && mv tmp "$ruvdi"/all_segments
fi

if [ $stage -le 9 ]; then
  # NOTE I need to make changes because of how segment_long_utterances_nnet3.sh treats speaker IDs and suffices!
  echo 'Change the file dependent speaker IDs to the constant speaker IDs for the diarization data'
  python3 local/switch_to_true_spkID.py \
  --spkID_map "$ruvdi"/reco2spk_num2spk_label.csv \
  --diar_segments "$ruvdi"/all_segments \
  "$ruvdi"/all_segments_wspkID
fi

if [ $stage -le 10 ]; then
  echo 'Assign speaker IDs from diarization data'
  python3 local/timestamp_comparison.py \
  --subtitle_segments_file "${datadir}"_reseg/segments \
  --diar_segments_wspkID "$ruvdi"/all_segments_wspkID \
  --segments_out "${datadir}"_final/segments \
  --utt2spk_out "${datadir}"_final/utt2spk
fi

if [ $stage -le 11 ]; then
  echo 'Fix the spkIDs in the other files'
  
  echo 'Fix IDs in text'
  # Keep lines in text where the (speaker removed) uttID exists in the final
  # segments file
  
  # Unsetting exit on errors
  # Need to make the script not exit on errors because if grep doesn't find
  # anything then it probably exits on a non-zero code and therefore it
  # doesn't continue the loop
  set +e
  while IFS= read -r line
  do
    partID=$(echo "$line" | cut -d'-' -f2- | cut -d' ' -f1)
    text=$(echo "$line" | cut -d' ' -f2-)
    match=$(grep "$partID" "${datadir}"_final/segments | cut -d' ' -f1)
    if [ -n "$match" ]; then
      echo -e "$match $text" >> "${datadir}"_final/text
    fi
  done < "${datadir}"_reseg/text
  set -e
  
  # Copy wav.scp over
  cp "${datadir}"_reseg/wav.scp "${datadir}"_final/wav.scp
  
  echo 'Create spk2utt'
  utils/utt2spk_to_spk2utt.pl < "$datadir"_final/utt2spk > "$datadir"_final/spk2utt
  
  echo "Validate and fix ${datadir}_final"
  utils/validate_data_dir.sh --no-feats "${datadir}_final" || utils/fix_data_dir.sh "${datadir}_final" || exit 1;
fi

echo "$0 has finished running"

exit 0
