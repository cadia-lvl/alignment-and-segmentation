#!/usr/bin/env bash

# Copyright 2021 Judy Fong (Reykjavík University) - lvl@judyyfong.xyz
# This is based on the run.sh script made by inga in the TV_subtitles recipe
#           2020 Inga Rún Helgadóttir

# License Apache 2.0

# Description: Get the news data in the format that Kaldi wants before aligning
# and segmenting the data. Start by using teleprompter/888 data but since there
# are no timestamps, put all the text together and resegment. There are no
# speaker IDs so for the segmentation use a single speaker ID per audio file
# and see whether that will be good enough.
# The utterance ids are only the first 7 digits of an episode number since the
# original episode numbers/event ids have a variable length but kaldi want a
# standard length.

# Run from the H2 directory

# NOTE! segment_long_utterances_nnet3.sh creates new speaker IDs, how should I
# treat spkIDs up to that point?
# Split into multiple unknown speakers or not? I guess multiple is better.
#SBATCH --nodelist=terra

#SBATCH --out=logs/run%J.out

set -eo pipefail

stage=0

srcdir=/data/models/althingi/acoustic_model/chain/5.4/tdnn/20190114
langdir=$srcdir/lmdir/lang
extractor=$srcdir/extractor
# TODO: is corpusdir even needed when the dataset is loaded in from the python
# file and it cannot change?
# corpusdir=data/news
normalize=true

. ./path.sh
. ./cmd.sh

# Create these symlinks before running:
ln -sfn "$KALDI_ROOT"/egs/wsj/s5/steps steps
ln -sfn "$KALDI_ROOT"/egs/wsj/s5/utils utils

if [ "$1" == "-h" ]; then
  echo "Create ASR training data from TV recordings and text data,"
  echo "Usage: $(basename $0) [-h]"
  exit 0
fi

# This parses the --stage option if supplied
. utils/parse_options.sh || exit 1;

# NOTE! change path for $data, $exp and $mfcc in conf/path.conf
corpusname=news-data
datadir="$data"/"$corpusname"
expdir="$exp"/"$corpusname"/segmentation
mfcc="$mfcc"

# Test the existance of input data and models
for d in $srcdir $langdir $extractor; do
  [ ! -d "$d" ] && echo "$0: expected $f to exist" && exit 1;
done

# Check if expand-numbers is installed and install it otherwise
if "$normalize" && ! command -v expand-numbers &> /dev/null; then
  echo "Expand-numbers does not exist, installing..."
  tar zxvf ../tools/expand-numbers-linux-amd64.tar.gz -d $KALDI_ROOT/src/fstbin
fi

if [ $stage -le 0 ]; then
  mkdir -p "$datadir"/log "$expdir" "$mfcc"
fi

if [ $stage -le 1 ]; then
  echo 'Create the files necessary for Kaldi and raw_text'
  echo 'Create utt2spk, wav.scp, segments and raw_text'
  python3 local/news_data_prep.py "$datadir"

  echo 'Create spk2utt'
  utils/utt2spk_to_spk2utt.pl < "$datadir"/utt2spk > "$datadir"/spk2utt
fi

# TODO: start on stage 4 of the run script and get stages from there
if [ $normalize ] && [ $stage -le 2 ] ; then
  echo 'Clean the text'
  utils/slurm.pl --mem 4G "$datadir"/log/clean_text.log \
  local/clean_text.sh "$datadir"/raw_text "$datadir"/text_cleaned &
  wait
  # NOTE! Fix the uttIDs
  sed -i -r 's/^(unknown) ([0-9]+)/\1-\2/' "$datadir"/text_cleaned
  # NOTE! We use code for the expansion that is not in the official Kaldi version.
  # TO DO: Extract those files from our Kaldi src dir and ship with this recipe
  echo 'Expand abbreviations and numbers'
  utils/slurm.pl --mem 4G "$datadir"/log/expand_text.log \
  local/expand_text.sh "$datadir"/text_cleaned "$datadir"/text_expanded

  echo "Remove punctuations to make the text better fit for acoustic modelling."
  sed -re 's: [^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö ] : :g' -e 's: +: :g' \
  < "${datadir}"/text_expanded > "$datadir"/text || exit 1;

  utils/validate_data_dir.sh --no-feats "$datadir" || utils/fix_data_dir.sh "${datadir}" || exit 1;
elif [ $stage -le 2 ]; then
  cp "$datadir"/raw_text "$datadir"/text

fi

if [ $stage -le 3 ]; then
  echo "Extract high resolution features which are used with Kaldi's nnet models"
  steps/make_mfcc.sh \
  --nj 60 \
  --mfcc-config conf/mfcc_hires.conf \
  --cmd "$decode_cmd" \
  "${datadir}" \
  "$expdir"/make_hires/ "$mfcc"

  utils/validate_data_dir.sh "${datadir}" || utils/fix_data_dir.sh "${datadir}" || exit 1;
fi

if [ $stage -le 4 ]; then
  # Estimate the OOV rate to see whether I need to update my lexicon
  cut -d' ' -f2- "${datadir}"/text | tr ' ' '\n' | sort |uniq -c > "${datadir}"/words.cnt
  comm -23 <(awk '$2 ~ /[[:print:]]/ { print $2 }' "${datadir}"/words.cnt | sort) <(cut -d" " -f1 $langdir/words.txt | sort) > "${datadir}"/vocab_text_only.tmp
  join -1 1 -2 1 "${datadir}"/vocab_text_only.tmp <(awk '$2 ~ /[[:print:]]/ { print $2" "$1 }' ${datadir}/words.cnt | sort -k1,1) | sort | awk '{total = total + $2}END{print "OOV: " total}'
  cat "$datadir"/words.cnt | awk '{total = total + $1}END{print "total words: " total}'
  # What is the OOV rate?
  # Get 2.7% OOV rate. I think under 3% is ok.

fi

if [ $stage -le 5 ]; then
  echo "Create crude shorter segments using an out-of-domain recognizer"
  steps/cleanup/segment_long_utterances_nnet3.sh \
  --nj 20 \
  --extractor "$extractor" \
  --cmd "$decode_cmd" \
  "$srcdir" "$langdir" \
  "${datadir}" "${datadir}"_segm_long \
  "$expdir"/long
#  "$datadir"/log/segmentation_long_utterances.log

  utils/validate_data_dir.sh "${datadir}"_segm_long || utils/fix_data_dir.sh "${datadir}"_segm_long

  steps/make_mfcc.sh \
  --nj 20 \
  --mfcc-config conf/mfcc_hires.conf \
  --cmd "$decode_cmd" \
  "${datadir}"_segm_long \
  "$expdir"/make_hires/ "$mfcc"
fi

if [ $stage -le 6 ]; then
  echo "Re-segment using an out-of-domain recognizer"
  utils/slurm.pl --mem 8G "$datadir"/log/segmentation.log \
  steps/cleanup/clean_and_segment_data_nnet3.sh \
  --cmd "$decode_cmd" \
  --nj 20 \
  --extractor "$extractor" \
  "${datadir}"_segm_long "$langdir" \
  "$srcdir" "$expdir" \
  "${datadir}"_reseg &
  wait

  # Calculate the duration of the new segments
  utils/data/get_utt2dur.sh "${datadir}"_reseg
  awk '{sum = sum + $2}END{print sum, sum/NR}' "${datadir}"_reseg/utt2dur
  # Get 2609 seconds, i.e. around 43 min.  Average segment length is ?? sek
  # Original length of audio was ?? hrs

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

