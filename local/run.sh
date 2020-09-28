#!/usr/bin/env bash

# Get data on the format that Kaldi wants before aligning and segmenting the data.
# I get subtitle data but since the timestamps are often off I will put all the text together and resegment
# I don't have speaker IDs so for the segmentation I will try using a single sudo one for everyone
# and see whether that will be good enough
# I start with extracting the same data as Judy has for diarization to be able to assign speaker IDs later
# Run from H2 directory

# Create these symlinks before running:
#ln -s ../kaldi/egs/wsj/steps steps
#ln -s ../kaldi/egs/wsj/utils utils

srcdir=/home/staff/inga/models/acoustic_model/chain/5.4/tdnn_1_clean_sp/20190114
langdir=$srcdir/lmdir/lang
extractor=$srcdir/extractor
mfcc=/work/inga/mfcc

. ./path.sh
. ./cmd.sh

if [ $# != 4 ]; then
    echo ""
    echo ""
    echo "Usage: local/expand.sh [options] <diarization-corpus-dir> <output-data-dir> <output-diarization-data-dir> <exp-dir>"
    echo "e.g.: local/expand.sh data/cleantext.txt data/text_expanded"
fi

corpusdir=/data/ruv-di/version0001
datadir=/work/inga/data/h2/unsegmented
ruvdi=$datadir/..
expdir=/work/inga/exp/h2/segmentation

mkdir -p $datadir/log, $expdir, $mfcc


# From a list of recording IDs fetch the subtitles. List from Judy's diarization dir
echo 'Extract subtitle files from RUV'
for file in $(ls $corpusdir/wav); do
    if [ "$file" != '/dev/fd/63' ]; then
        php local/extract_vtt.php "${file%.*}" $datadir/vtt_transcripts
    fi
done

echo 'Create the files necessary for Kaldi'
echo 'Create wav.scp'
for d in $(ls $datadir/vtt_transcripts); do
    echo -e unknown-"${d%.*}"' sox -twav - -c1 -esigned -r16000 -G -twav - < '/data/ruv-di/version0001/wav/"${d%.*}".wav' |' >> $datadir/wav.scp
done

echo 'Create utt2spk'
for d in $(ls $datadir/transcripts); do
    echo -e unknown-"${d%.*}"' unknown' >> $datadir/utt2spk
done

echo 'Create spk2utt'
utils/utt2spk_to_spk2utt.pl < $datadir/utt2spk > $datadir/spk2utt

echo 'Create segment and text files out of vtt subtitle files'
# These are segmented into subtitles
for file in $(ls $datadir/vtt_transcripts/*.vtt); do
    name=$(basename "$file")
    python local/create_segments_and_text.py \
    "$file" $datadir/transcripts/"${name%.*}"
done

echo 'Because of incorrect subtitle timestamps. Join the text segments from each file together into a line with uttID'
# All subtitles of a file are joined into one text connected to an uttID
# and the text from all files are put into one. One line per recording
for d in $($datadir/transcripts/); do
    if [ "$d" != '/dev/fd/63' ]; then
        cut -d' ' -f2- data/transcripts/"${d%.*}"/text \
        | tr '\n' ' ' | sed -r "s/.*/unknown-${d%.*} &/" \
        >> $datadir/raw_text \
        echo >> $datadir/raw_text
    fi
done

echo 'Clean the text'
utils/slurm.pl --mem 4G $datadir/log/clean_text.log \
local/clean_text.sh $datadir/raw_text $datadir/text_cleaned &
wait
# NOTE! Fix the uttIDs
sed -i -r 's/^(unknown) ([0-9]+) ([a-z]) ([0-9])/\1-\2\u\3\4/' $datadir/text_cleaned

echo 'Expand abbreviations and numbers'
utils/slurm.pl --mem 4G $datadir/log/expand_text.log \
local/expand_text.sh $datadir/text_cleaned $datadir/text_expanded &

echo "Remove punctuations to make the text better fit for acoustic modelling."
sed -re 's: [^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö ] : :g' -e 's: +: :g' \
< ${datadir}/text_expanded > $datadir/text || exit 1;

utils/validate_data_dir.sh --no-feats $datadir || utils/fix_data_dir.sh ${datadir} || exit 1;

echo "Extract features"
steps/make_mfcc.sh \
--nj 20 \
--mfcc-config conf/mfcc.conf \
--cmd "$train_cmd"           \
${datadir} $expdir/make_mfcc $mfcc

utils/copy_data_dir.sh ${datadir} ${datadir}_hires

echo "Create high resolution features which are used with Kaldi's nnet models"
steps/make_mfcc.sh \
--nj 20 \
--mfcc-config conf/mfcc_hires.conf \
--cmd "$decode_cmd" \
${datadir}_hires \
$expdir/make_hires/ $mfcc

utils/validate_data_dir.sh ${datadir}_hires || utils/fix_data_dir.sh ${datadir}_hires || exit 1;


# Estimate the OOV rate to see whether I need to update my lexicon
# cut -d' ' -f2- "${datadir}"/text | tr ' ' '\n' | sort |uniq -c > "${datadir}"/words.cnt
# comm -23 <(awk '$2 ~ /[[:print:]]/ { print $2 }' "${datadir}"/words.cnt | sort) <(cut -d" " -f1 $langdir/words.txt | sort) > "${datadir}"/vocab_text_only.tmp
# join -1 1 -2 1 "${datadir}"/vocab_text_only.tmp <(awk '$2 ~ /[[:print:]]/ { print $2" "$1 }' ${datadir}/words.cnt | sort -k1,1) | sort | awk '{total = total + $2}END{print total}'
# # Get 2.3% OOV rate. I think that is ok.

echo "Create crude shorter segments using an out-of-domain recognizer"
# There is no max length option!
utils/slurm.pl --mem 8G $datadir/log/segmentation_long_utterances.log \
steps/cleanup/segment_long_utterances_nnet3.sh \
--nj 1 \
--extractor "$extractor" \
"$srcdir" "$langdir" \
"${datadir}"_hires ${datadir}_segm_long \
"$expdir"/long &

utils/validate_data_dir.sh ${datadir}_segm_long || utils/fix_data_dir.sh ${datadir}_segm_long

steps/make_mfcc.sh \
--nj 20 \
--mfcc-config conf/mfcc_hires.conf \
--cmd "$decode_cmd" \
${datadir}_segm_long \
$expdir/make_hires/ $mfcc

echo "Re-segment using an out-of-domain recognizer"
utils/slurm.pl --mem 8G $datadir/log/segmentation.log \
steps/cleanup/clean_and_segment_data_nnet3.sh \
--nj 20 \
--extractor "$extractor" \
${datadir}_segm_long "$langdir" \
"$srcdir" "$expdir" \
${datadir}/../judy_reseg &
wait
#--segmentation-opts "--max-internal-silence-length=1.0 --max-internal-non-scored-length=1.0 --min-segment-length=1.0" \

# Calculae the duration of the new segments
utils/data/get_utt2dur.sh ${datadir}/../judy_reseg
awk '{sum = sum + $2}END{print sum, sum/NR}' ${datadir}/../judy_reseg
# Get 17494.2 seconds, i.e. around 4 hrs and 50 min, for Judy's ruv-di set. Average segment length is 4.3 sek
# Sum of Judy's diarization segments is 25123.2 seconds or almost 7 hrs.
# Original length of audio was 8.3 hrs

# Do analysis on segment length

echo 'Process RUV diarization data, since it contains speaker information. Then I can compare the new segments'
echo 'to the diarization segments and extract speaker information'

# Since the first file has a different kind of spkIDs I need to get them on the same format as in the other files.
cp -r $corpusdir/json/ $ruvdi
sed -re 's/([0-9]+)[A-ZAÐEIOUYÞÆÖa-zaðeiouyþæö]+[0-9]+/\1/g' \
-e 's/([0-9]+)[A-ZAÐEIOUYÞÆÖa-zaðeiouyþæö]+/\1/g' \
< $ruvdi/json/4886083R7.json \
> $ruvdi/json/4886083R7_new.json

mv $ruvdi/json/4886083R7_new.json $ruvdi/json/4886083R7.json

for file in $(ls $ruvdi/json); do
    if [ "$file" != '/dev/fd/63' ]; then
        python local/parse_json.py $ruvdi/json/"$file" $ruvdi
    fi
done

for f in "$ruvdi"/*/ruvdi_segments; do (cat "${f}"; echo) >> $ruvdi/all_segments; done
grep -Ev '^$' $ruvdi/all_segments | tr '-' ' ' > tmp && mv tmp $ruvdi/all_segments

echo 'Assign speaker IDs from diarization data'
# NOTE! The following script needs rewriting
python local/timestamp_comparison.py

exit 0