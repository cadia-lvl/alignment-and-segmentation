#!/usr/bin/env python3
#
# Author: Judy Fong <lvl@judyyfong.xyz.> Reykjavik University
# License: Apache 2.0
#
# Description: Take the list of show names and episode file names.
#   Then create segments (needs the audio duration), text (needs the subtitle
#   path to extract the text), utt2spk, and wav.scp (needs the media path)
#   files.
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
from extract_text import print_text

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
    return ''

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
    exclude = ['4955849T0']
    with open(pairings, 'r') as show_episode, \
    open(outdir + '/wav.scp', 'w') as wav_scp, \
    open(outdir + '/utt2spk', 'w') as utt2spk, \
    open(outdir + '/raw_text', 'w') as raw_text, \
    open(outdir + '/segments', 'w') as segments:
        pairingreader = csv.reader(show_episode, delimiter=',')
        show_details = {}
        for pair in pairingreader:
            if pair[1] in exclude:
                print('{} has media problems'.format(pair[1]))
                continue
            ep_id = pair[1][:7]
            utt_id = 'unknown-{}'.format(ep_id)
            # Get the show details
            if not show_details or show_details['name'] != pair[0]:
                show_details = [show for show in shows['shows'] if \
                show['name'] == pair[0]][0]

            # Check if the file exists as video and if not check if it
            # exists as audio and use whichever one works
            video_path = '/data/misc/ruv_unprocessed/' + show_details['video_dir'] \
                + '/' + pair[1] + '.mp4'
            audio_path = '/data/misc/ruv_unprocessed/' + \
                show_details['audio_dir'] + '/' + pair[1] + '.wav'
            if file_path(video_path):
                ep_path = video_path
            elif file_path(audio_path):
                ep_path = audio_path
            else:
                # no available file exists so don't process it for asr
                continue

            subs_path = '/data/misc/ruv_unprocessed/' + \
                show_details['text_dir'] + '/' + pair[1] + '.vtt'
            all_text = print_text(subs_path)
            # raw_text
            if not all_text:
                continue
            print('{} {}'.format(utt_id, all_text), file=raw_text)

            # wav.scp
            # ac = audio channels, ar = audio rate (Hz)
            print('{} ffmpeg -i {} -ac 1 -ar 16k -f wav - |'.format(
                ep_id, ep_path), file=wav_scp)

            # utt2spk
            print('{} unknown'.format(utt_id), file=utt2spk)

            # make segments
            audio_length = get_length(ep_path)
            print('{} {} 0 {}'.format(utt_id, ep_id, audio_length),
            file=segments)


if __name__ == '__main__':
    # this portion is run when this file is called directly by the command line
    args = parse_arguments()
    Path(args.outdir).mkdir(parents=True, exist_ok=True)

    files_root = '../extract-data/'
    pairs = files_root + 'data/pairs_show_episode.csv'
    shows_dirs = open(files_root + 'json/show_dirs.json')
    sdirs = json.load(shows_dirs)
    main(sdirs, pairs, args.outdir)
