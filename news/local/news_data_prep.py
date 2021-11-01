#!/usr/bin/env python3
# Author: Judy Fong <lvl@judyyfong.xyz.> Reykjavik University
# License: Apache 2.0

# Description: 
# 1. create wav.scp (ffmpeg -i video audio.flac) : look at
# ~/repos/extract-data/ruv/airdate2title2media2text.csv to get the text and
# video files, get the full path using json/show_dirs.json
# 2. create utt2spk

# TODO: 2. look at ~/repos/extract-data/ruv/airdate2title2media2text.csv to get
# the text and video files, for full path then use json/show_dirs.json

# TODO: create raw_text, segments, etc
# TODO: get audio length in seconds

# examples:
# ==> data/one-news-data/segments <==
# unknown-5004311T0 5004311T0 0 1381.248
# unknown-5004312T0 5004312T0 0 1403.093
# 
# ==> data/one-news-data/utt2spk <==
# unknown-5004311T0 unknown
# unknown-5004312T0 unknown
# 
# ==> data/one-news-data/wav.scp <==
# 5004311T0 sox -twav - -c1 -esigned -r16000 -G -twav - < data/one-news/wav/5004311T0.wav |
# 5004312T0 sox -twav - -c1 -esigned -r16000 -G -twav - < data/one-news/wav/5004312T0.wav |
 

import csv
import json
import re

def main(shows, media2text):
    episodes = {}
    current_show = [ show for show in shows['shows'] if show['name'] ==
    'Fréttir kl 1900'][0]
    print (current_show)
    data_root = '/data/misc/ruv_unprocessed/'
    # open csv file
    with open(media2text, 'r') as audio_text, \
    open('data/tempwav.scp', 'w') as wav_scp, \
    open('data/temputt2spk', 'w') as utt2spk, \
    open('data/tempraw_text', 'w') as raw_text:
        datareader = csv.reader(audio_text, delimiter=',')
        for row in datareader:
            # Use the numerical part [:7] of the filename BEFORE the letter as
            # the partial utterance id
            utt_id = 'NEWS-{}'.format(row[2][:7])

            # wav.scp
            print('{} ffmpeg -i < {}{}/{} |'.format(row[2][:7], data_root,
            current_show['video_dir'], row[2]), file=wav_scp)
            # utt2spk
            print('{} {}'.format(utt_id, utt_id), file=utt2spk)
            # raw_text, still need to normalize it before it becomes text
            text_file = data_root + current_show['text_dir'] + '/' + row[3]
            with open(text_file) as f:
                condensed_output = ' '.join(f.read().split())
            print('{} {}'.format(utt_id, condensed_output), file=raw_text)
            # TODO almost segments
            audio_length = 0
            print('{} {} 0 {}'.format(utt_id, row[2][:7], audio_length))

if __name__ == '__main__':
    # this portion is run when this file is called directly by the command line
    files_root = '../../../../extract-data/ruv/'
    airdate2title2media2text = files_root + 'airdate2title2media2text.csv'
    shows_dirs = open(files_root + 'json/show_dirs.json')
    sdirs = json.load(shows_dirs)
    main(sdirs, airdate2title2media2text)
