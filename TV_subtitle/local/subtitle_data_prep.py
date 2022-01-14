#!/usr/bin/env python3
#
# Author: Judy Fong <lvl@judyyfong.xyz.> Reykjavik University
# License: Apache 2.0
#
# Description: Take the list of show names and episode file names.
# Then create
# TODO the wav.scp,
# needs the media path

# TODO segments,
# needs the audio duration

# TODO text,
# needs the subtitle path to extract the text

# and utt2spk files.
#
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
import subprocess
import argparse
from pathlib import Path

# parse_arguments are from the TV_subtitles local/extract_text.py file in this
# repo by Judy Fong
def parse_arguments():
    parser = argparse.ArgumentParser(
        description="""Create segments, utt2spk, wav.scp, and raw_text files\n
        Usage: python local/subtitle_data_prep.py <output-dir>\n
            E.g. python local/subtitle_data_prep.py data
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


def main(shows, pairings, outdir):
    with open(pairings, 'r') as show_episode, \
    open(outdir + '/wav.scp', 'w') as wav_scp, \
    open(outdir + '/utt2spk', 'w') as utt2spk, \
    open(outdir + '/raw_text', 'w') as raw_text, \
    open(outdir + '/segments', 'w') as segments:
        pairingreader = csv.reader(show_episode, delimiter=',')
        for pair in pairingreader:
            ep_id = pair[1][:7]
            utt_id = 'unknown-{}'.format(ep_id)
            print(pair[0])
            # utt2spk file
            print('{} unknown'.format(utt_id), file=utt2spk)
            # TODO: check if the file exists as video and if not check if it
            # exists as audio and use whichever one works
            # attempted wav.scp
            print('{} ffmpeg |'.format(ep_id))



if __name__ == '__main__':
    # this portion is run when this file is called directly by the command line
    args = parse_arguments()
    Path(args.outdir).mkdir(parents=True, exist_ok=True)

    files_root = '../extract-data/'
    pairs = files_root + 'data/pairs_show_episode.csv'
    shows_dirs = open(files_root + 'json/show_dirs.json')
    sdirs = json.load(shows_dirs)
    main(sdirs, pairs, args.outdir)
