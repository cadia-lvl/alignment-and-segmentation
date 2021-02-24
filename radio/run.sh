#!/usr/bin/env bash

# NOTE! There were a lot of discrepancies in the metadata. Some of them I've fixed manually.
# Others I fix below.
# Many speakers are in each same audio segment.
# I don't know how well it will go to split that up
# Another problem is that many speakers are assigned the same speaker ID
# Many transcripts are beyond the length of the audio and timestamps are commonly 2-3 seconds off.
# NOTE! Only 60% of transcriptions have audio files with them. => Partially fixed, some files are still too short
# Needed to create a new AM which included the tags in it's phone list.
# Not a solution for all tags though. How should I deal with immersive tags?

stage=0
num_jobs=20
nj_decode=32

. ./path.sh
. ./cmd.sh
# This parses the --stage option if supplied
. utils/parse_options.sh || exit 1;

# Create these symlinks before running:
ln -sfn "$KALDI_ROOT"/egs/wsj/s5/steps steps
ln -sfn "$KALDI_ROOT"/egs/wsj/s5/utils utils

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

if [ "$1" == "-h" ]; then
    echo "Create ASR training data from radio recordings and transcripts from CreditInfo."
    echo "Usage: $(basename $0) [-h]"
    exit 0
fi

# Maybe I should let input_xlsx and the delivery date become variables that I read in

prondict=/models/samromur/prondict_w_samromur.txt
lm_trainingset=/models/samromur/rmh_2020-11-23_uniq.txt

corpusdir=/data/asr/creditinfo/speech/SIM_Afhending_20201201
input_xlsx=$corpusdir/'SÍM-gögn 20201201.xlsx'
input_tsv=data/creditinfo_20201201.tsv
meta=data/metadata.tsv
datadir=data/raw_flexible
langdir=data/lang

# For the acoustic model training
samromur_data=/work/inga/h7/data

mkdir -p $datadir exp mfcc

if [ $stage -le 0 ]; then
    # Convert the audio files from .ts to .wav
    mkdir "$corpusdir"/audio
    for f in "$corpusdir"/audio_ts/*; do name=$(basename "$f"); ffmpeg -i "$f" "$corpusdir"/audio/"${name%.*}".wav; done
    
    # Change from a spreadsheet to a tab separated file
    xlsx2csv -d "tab" $input_xlsx > $input_tsv
fi

if [ $stage -le 1 ]; then
    # Format the metadata
    # This needs to be made more robust
    # 1-4) put text following a single segment into a single line with spk ID in brackets.
    # NOTE! TAB shows up as space here. Need to fix
    # 5) Rewrite the audio filenames to eliminate Icelandic characters and spaces
    # 6) I have changed the auido files from .ts to .wav. Fix the filenames in the metadata
    # 7) Fix missing period after gender-age
    # 8-16) Standardize tags
    # ) Switch spaces to one between words
    TAB=$'\t'
    grep -Ev '^ *$' $input_tsv \
    | sed -r 's/^([A-ZAÐEIOUYÞÆÖ]{2,3})$/[\1]/g' \
    | tr '\n' ' ' \
    | sed -re 's/'"${TAB}"'{5,}/\n/g' -e 's/^ '"${TAB}"'//g' \
    -e 's/Rás 1 9/ras1_9/g' -e  's/Rás 2 9/ras2_9/g' \
    -e 's/\.ts/.wav/g' \
    -e 's/(kk|kvk)([0-9]) /\1\2. /g' \
    -e 's/<n>/<noise>/g' -e 's/<haha>/<laughter>/g' \
    -e 's/<hst>/<coughing>/g' \
    -e 's/<...>/<crosstalk>/g' -e 's:</…>:</crosstalk>:g' \
    -e 's:<m>:<music>:g' -e 's:</m>:</music>:g' \
    -e 's:<m>:<foreign>:g' -e 's:</m>:</foreign>:g' \
    -e 's/<Talað á dönsku>/<danish>/g' -e 's/<Talað á ensku>/<english>/g' \
    -e 's/<Talað á erlendu máli>/<foreign>/g' -e 's/<Talað á norsku>/<norwegian>/g' \
    -e 's/<Talað á sænsku>/<swedish>/g' -e 's/<Talað á spænsku>/<spanish>/g' \
    -e 's/<Talað á þýsku>/<german>/g' \
    -e 's/ +/ /g' \
    > $meta
    
    
    # Remove rows not containing speaker information and
    # text not starting on speaker ID.
    # NOTE! To do: Change this by inserting the first speaker ID in front
    grep -E 'kvk[0-9]|kk[0-9]' $meta | grep -E 'kvk[0-9]|kk[0-9]. +\[' \
    > "$tmp"/m1
    (head -n1 $meta && cat "$tmp"/m1) > "$tmp"/m2
    mv "$tmp"/m2 $meta
    
    # NOTE! After cleaning all of this away I'm left with 1768 time segments
    # of which only 157 contain only one speaker
    
    # Extract info on speaker from the text column
    # NOTE! How to not map tabs to spaces in VS code?
    cut -f14 $meta | grep -E '\bkvk[0-9]\b|\bkk[0-9]\b' |grep -Eo '^[^[]+' \
    | sed -re 's/"//g' -e 's/\. *$//g' -e 's/(kvk|kk)([0-9])\. /\1\2\n/g' -e 's/, /        /g' \
    | cut -f1-3 | grep -E '(kvk[0-9]|kk[0-9])$' \
    | sed -re 's/(kk|kvk)([0-9])/\1    \2/g' -e 's/^[0-9]? //' \
    | sort -t $'\t' -k1,1 | uniq > data/name_id_gender_age.txt
    
    # NOTE! Should I do the following or not? I don't know how to handle immersive tags when aligning
    # For testing purposes create another metafile where certain tags (and segments spoken in a foreign language)
    # have been removed before alignment
    sed -re 's:</?\.\.\.>|</?b>|</?m>: :g' \
    -e 's:[^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+ <Talað [^>]+>,?.? *(\[|$): \1:g' \
    -e 's/\[[A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+ (\[[A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+\]|$)/\1/g' \
    $meta > data/metadata_asr.tsv
    
fi

if [ $stage -le 2 ]; then
    # Create the Kaldi data dir
    python3 local/prep_data.py $corpusdir/audio data/metadata_asr.tsv $datadir
    cut -d' ' -f2- data/raw/text | sed -re 's/[.,?:‘"„“;–-]//g' -e 's/^ | $//g' -e 's/ +/ /g'  > "$tmp"/text
    paste <(cut -d' ' -f1 data/raw/text) "$tmp"/text | tr '\t' ' ' > "$tmp"/clean_text
    mv "$tmp"/clean_text $datadir/text
    
    # Check whether I have the same amount of segments as the speaker segments in the metafile
    paste <(cut -f3 data/metadata_asr.tsv) <(awk -F\[ '{print NF-1}' data/metadata_asr.tsv) > num_segm_per_scriptID_metadatafile.txt
    cut -d' ' -f2 data/raw/segments | sort | uniq -c | awk '$2 ~ /[[:print:]]/ {print $2,$1}' > num_segm_per_scriptID_segments.txt
    wdiff <(sed '1d' num_segm_per_scriptID_metadatafile.txt) num_segm_per_scriptID_segments.txt > wdiff_num_segm_per_scriptID_metadata_segments.txt
    
    utils/validate_data_dir.sh --no-feats "$datadir" \
    || utils/fix_data_dir.sh "$datadir" || exit 1;
fi


if [ $stage -le 4 ]; then
    if [ ! -d "$langdir" ]; then
        echo "Create the lexicon"
        [ -d data/local/dict ] && rm -r data/local/dict
        mkdir -p data/local "$langdir"/log
        utils/slurm.pl --mem 4G "$langdir"/log/prep_lang.log \
        local/prep_lang.sh \
        $prondict \
        data/local/dict \
        "$langdir"
    fi
fi

if [ $stage -le 5 ]; then
    
    echo "I need to train an acoustic model, since the new phones,"
    echo "from the tags, cause mismatch in the phone list"
    echo "Train on Samromur data"
    
    echo "Preparing a pruned trigram language model"
    mkdir -p data/log
    utils/slurm.pl --mem 24G data/log/make_LM_3g.log \
    local/make_LM.sh \
    --order 3 --carpa false \
    --min1cnt 20 --min1cnt 10 --min3cnt 2 \
    $lm_trainingset data/lang \
    data/local/dict/lexicon.txt data \
    || error 1 "Failed creating a pruned trigram language model"
    
    echo "Train a mono system"
    steps/train_mono.sh    \
    --nj $num_jobs           \
    --cmd "$train_cmd" \
    --totgauss 4000    \
    $samromur_data/train_5kshort \
    data/lang          \
    exp/mono
    
    echo "mono alignment. Align train_10k to mono"
    steps/align_si.sh \
    --nj $num_jobs --cmd "$train_cmd" \
    $samromur_data/train_10k data/lang exp/mono exp/mono_ali
    
    echo "first triphone training"
    steps/train_deltas.sh  \
    --cmd "$train_cmd" \
    2000 10000         \
    $samromur_data/train_10k data/lang exp/mono_ali exp/tri1
    
    echo "Aligning train_20k to tri1"
    steps/align_si.sh \
    --nj $num_jobs --cmd "$train_cmd" \
    $samromur_data/train_20k data/lang \
    exp/tri1 exp/tri1_ali
    
    echo "Training LDA+MLLT system tri2"
    steps/train_lda_mllt.sh \
    --cmd "$train_cmd" \
    --splice-opts "--left-context=3 --right-context=3" \
    3000 25000 \
    $samromur_data/train_20k data/lang \
    exp/tri1_ali exp/tri2
    
    echo "Aligning train_40k to tri2"
    steps/align_si.sh \
    --nj $num_jobs --cmd "$train_cmd" \
    $samromur_data/train_40k data/lang \
    exp/tri2 exp/tri2_ali
    
    echo "Train LDA + MLLT + SAT"
    steps/train_sat.sh    \
    --cmd "$train_cmd" \
    4000 40000    \
    $samromur_data/train_40k data/lang     \
    exp/tri2_ali exp/tri3
    
    echo "Third triphone decoding"
    utils/mkgraph.sh data/lang_3g exp/tri3 exp/tri3/graph
    
    for dir in eval test; do
        (
            steps/decode_fmllr.sh \
            --config conf/decode.config \
            --nj "$nj_decode" --cmd "$decode_cmd" \
            exp/tri3/graph $samromur_data/$dir \
            exp/tri3/decode_$dir;
            
            steps/lmrescore_const_arpa.sh \
            --cmd "$decode_cmd" \
            data/lang_{3g,4g} $samromur_data/$dir \
            exp/tri3/decode_$dir \
            exp/tri3/decode_${dir}_rescored
        ) &
    done
    wait
fi


if [ $stage -le 6 ]; then
    echo "Extract MFCC features"
    steps/make_mfcc.sh \
    --nj $num_jobs \
    --mfcc-config conf/mfcc.conf \
    --cmd "$decode_cmd" \
    "$datadir" \
    exp/make_mfcc mfcc
    
    echo "Computing CMVN stats"
    steps/compute_cmvn_stats.sh \
    "$datadir" exp/make_mfcc mfcc;
fi

if [ $stage -le 7 ]; then
    echo "Segment"
    utils/slurm.pl --mem 32G "$datadir"/log/segmentation_flexible.log \
    steps/cleanup/clean_and_segment_data.sh \
    --cmd "$decode_cmd" \
    --nj $nj_decode \
    "$datadir" data/lang \
    exp/tri2_full exp/tri2_full_cleanup \
    "${datadir}"_reseg &
    wait
    
fi

exit 0