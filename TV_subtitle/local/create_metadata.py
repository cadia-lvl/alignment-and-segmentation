#!/usr/bin/env python3
# Author: Judy Y. Fong <lvl@judyyfong.xyz.> Reykjavik University
# License: Apache 2.0
#
# Description: Create metadata and split audio command file

import os
import argparse
from pathlib import Path

def parse_arguments():
    parser = argparse.ArgumentParser(
        description="""Create metadata and split audio command\n
        Usage: python create_metadata.py <in-dir> <out-dir>\n
            E.g. python local/create_metadata.py data/reseg data/splitaudio
        """
    )
    parser.add_argument(
        "indir", type=str, help="base path for wav.scp and segments files",
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


def create_metadata(indir, outdir):
    # write code here
    swap = {
            'Krakkafréttir': 'Krakkafrettir',
            'Fréttirkl1900': 'Frettirkl1900',
            'Kastljós': 'Kastljos',
            'stundinokkar': 'StundinOkkar'
            }
    ruvdi = [
            '4886083',
            '4886107',
            '4886131',
            '4898511',
            '4898535',
            '4930605',
            '4934417',
            '4934441',
            '4934466',
            '4959359',
            '4959383',
            '4959408',
            '5004302',
            '5006014',
            '5008564',
            '5008565',
            '5008566',
            '5008567',
            '5008568',
            '5008569',
            '5008571',
            '5008572',
            '5012547',
            '5012548',
            '5012551',
            '5012552',
            '5012553',
            '5012565',
            '5012569',
            '5019095',
            '5021994',
            '5021995',
            '5022004',
            '5022010',
            '5022028'
            ]
    episodes = {}
    with open(indir + '/wav.scp', 'r') as infile:
        data = infile.readlines()
        for i in data:
            wave_items = i.split()
            media_path = wave_items[3].split('/')
            episode, fileformat = media_path[-1].split('.')
            if media_path[-2] in swap:
                media_path[-2] = swap[media_path[-2]]
            if wave_items[0] in ruvdi:
                continue
            episodes[wave_items[0]] = { 
                                        'show_name': media_path[-2],
                                        'path': wave_items[3]
                                      }
            # print(wave_items[0], media_path[-2], wave_items[3])
    with open(indir + '/segments', 'r') as infile, open(
    outdir + '/metadata.tsv', 'w') as metadata_file:
        data = infile.readlines()
        for i in data:
            seg_items = i.split()
            if seg_items[1] in ruvdi:
                continue
            new_seg_id = seg_items[0][8:]
            print( '{}\t{}\t{}\t{:.2f}'.format(
                    new_seg_id, 
                    seg_items[1], 
                    episodes[seg_items[1]]['show_name'],
                    float(seg_items[3]) - float(seg_items[2])
                ), file=metadata_file)
            episode_path = outdir + '/audio/' + \
            episodes[seg_items[1]]['show_name'] + '/' + seg_items[1]
            Path(episode_path).mkdir(parents=True,exist_ok=True)
            # prevent ffmpeg from getting the next line from stdin so give it
            # /dev/null instead
            print(
                'ffmpeg -ss {} -to {} -i {} -ac 1 -ar 16k -f flac -nostdin data/splitaudio/audio/{}/{}/{}.flac'
                .format(seg_items[2], seg_items[3],
            episodes[seg_items[1]]['path'], episodes[seg_items[1]]['show_name'],
            seg_items[1],new_seg_id))


def main():

    args = parse_arguments()

    Path(args.outdir).mkdir(parents=True, exist_ok=True)

    create_metadata(args.indir, args.outdir)


if __name__ == '__main__':
    # this portion is run when this file is called directly by the command line
    # TODO: import wav.scp and segments file as arguments
    main()
