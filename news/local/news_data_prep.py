#!/usr/bin/env python3
# Author: Judy Fong <lvl@judyyfong.xyz.> Reykjavik University
# License: Apache 2.0

# Description: 
# parameter is the output directory
# Create the files for a kaldi data prep folder. This requires some extra
# files. Look at ~/repos/extract-data/ruv/airdate2title2media2text.csv to get
# the text and video files, for full path then use json/show_dirs.json

# 1. create wav.scp (ffmpeg -i video audio.flac) : look at
# ~/repos/extract-data/ruv/airdate2title2media2text.csv to get the text and
# video files, get the full path using json/show_dirs.json
# 2. create utt2spk
# 3. create raw_text

# 4. create segments, get audio length in seconds
# requires importing utility method from
# github.com/cadia-lvl/broadcast_data_prep (make pip package?) by Judy Fong

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
import os
import re
import subprocess
import argparse
from pathlib import Path

# parse_arguments are from the TV_subtitles local/extract_text.py file in this
# repo by Judy Fong
def parse_arguments():
    parser = argparse.ArgumentParser(
        description="""Create segments, utt2spk, wav.scp, and raw_text files\n
        Usage: python local/news_data_prep.py <output-dir>\n
            E.g. python local/news_data_prep.py data
        """
    )
    parser.add_argument(
        "outdir", type=str, help="base path for output files",
    )
    return parser.parse_args()


def file_path(path):
    if os.path.isfile(path):
        return path
    else:
        raise argparse.ArgumentTypeError(f"readable_file:{path} is not a valid file")


def main(shows, media2text, outdir):
    episodes = {}
    current_show = [ show for show in shows['shows'] if show['name'] == 'Fréttir kl 1900'][0]
    print (current_show)
    data_root = '/data/misc/ruv_unprocessed/'

    # TODO: non expandable text in these utterance ids for some reason
    non_expandable = ['unknown-5004139',
                      'unknown-5004165',
                      'unknown-4942730',
                      'unknown-4942878',
                      'unknown-4942882',
                      'unknown-4942883'
                      ]

    # open csv file
    with open(media2text, 'r') as audio_text, \
    open(outdir + '/wav.scp', 'w') as wav_scp, \
    open(outdir + '/utt2spk', 'w') as utt2spk, \
    open(outdir + '/raw_text', 'w') as raw_text, \
    open(outdir + '/segments', 'w') as segments:
        datareader = csv.reader(audio_text, delimiter=',')
        for row in datareader:
            # Use the numerical part [:7] of the filename BEFORE the letter as
            # the partial utterance id
            utt_id = 'unknown-{}'.format(row[2][:7])
            if utt_id in non_expandable:
                continue

            # wav.scp
            print('{} ffmpeg -i {}{}/{} -f wav - |'.format(row[2][:7], data_root,
                  current_show['video_dir'], row[2]), file=wav_scp)
            # utt2spk
            print('{} {}'.format(utt_id, utt_id), file=utt2spk)
            # raw_text, still need to normalize it before it becomes text
            text_file = data_root + current_show['text_dir'] + '/' + row[3]
            # add t to prevent bom issues
            with open(text_file, 'rt') as t_f:
                condensed_output = ' '.join(t_f.read().split())
            print('{} {}'.format(utt_id, condensed_output), file=raw_text)
            # segments
            print('{} {} 0 {}'.format(utt_id, row[2][:7], get_length(data_root
            + current_show['video_dir'] + '/' + row[2])), file=segments)


def get_length(filename):
    '''
    Get length/duration of media from ffprobe utility

    Thank you! SingleNegationEliminatio and Boris from stackoverflow.com
    https://stackoverflow.com/a/3844467/7813827
    '''
    result = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
                             "format=duration", "-of",
                             "default=noprint_wrappers=1:nokey=1", filename],
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    return float(result.stdout)


if __name__ == '__main__':
    # this portion is run when this file is called directly by the command line
    args = parse_arguments()

    Path(args.outdir).mkdir(parents=True, exist_ok=True)

    files_root = '../../../../extract-data/ruv/'
    airdate2title2media2text = files_root + 'airdate2title2media2text.csv'
    shows_dirs = open(files_root + 'json/show_dirs.json')
    sdirs = json.load(shows_dirs)
    main(sdirs, airdate2title2media2text, args.outdir)
