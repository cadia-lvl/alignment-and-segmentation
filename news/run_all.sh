#!/usr/bin/env bash

# Copyright 2021 Judy Fong (Reykjavík University) - lvl@judyyfong.xyz
#           2020 Inga Rún Helgadóttir

# License Apache 2.0

# Description: Get the news data in the format that Kaldi wants before aligning
# and segmenting the data. Start by using teleprompter/888 data but since
# there are no timestamps, put all the text together and resegment. There are no speaker IDs so for the segmentation use a single speaker ID per audio file and see whether that will be good enough.

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
datadir="$data"/news-data
expdir="$exp"/news-data/segmentation
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
