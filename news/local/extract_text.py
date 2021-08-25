#!/usr/bin/env python3

# Author: Judy Fong (Reykjavik University)
# Description:
# Extract text from a teleprompter/888 file

from itertools import groupby
from decimal import Decimal
import os
import argparse
from pathlib import Path


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="""Extract text from a subtitle file\n
        Usage: python extract_text.py <input-file> <output-dir>\n
            E.g. python local/extract_text.py
            data/vtt_transcripts/4886083R7.txt data/text
        """
    )
    parser.add_argument(
        "subtitle_file", type=file_path, help="Input subtitle file",
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


# Convert timestamps to seconds and partial seconds so hh:mm:ss.ff
def time_in_seconds(a_time):
    hrs, mins, secs = a_time.split(":")
    return Decimal(hrs) * 3600 + Decimal(mins) * 60 + Decimal(secs.replace(",", "."))


def no_transcripts(subtitle_path):
    ACCESS_ERROR_ONLY = 36
    return os.stat(subtitle_path).st_size == ACCESS_ERROR_ONLY


def get_text(subtitle_filename, outdir):
    # skip header(first two) lines in file
    if no_transcripts(subtitle_filename):
        print(f"{subtitle_filename} is presumed to not have transcripts")
    else:
        base = os.path.basename(subtitle_filename)
        (filename, ext) = os.path.splitext(base.replace("_", ""))
        outfile = outdir + "/" + filename

        if ext == ".vtt":
            with open(subtitle_filename, "r") as fin, open(outfile, "w") as ftext:
                next(fin)
                next(fin)
                groups = groupby(fin, str.isspace)
                count = 0
                for (_, *rest) in (map(str.strip, v) for g, v in groups if not g):
                    # write to text file
                    # better to create individual speaker ids per episode or shows, more speaker ids,
                    # because a global one would create problems for cepstral mean normalization ineffective in training
                    string = " ".join([*rest[1:]])
                    ftext.write(f"unknown-{filename}_{count:05d} {string}\n")
                    count = count + 1
        else:
            with open(outfile, "w") as ftext:
                # data = open(subtitle_filename).read().replace('\n', '')
                # print(f"unknown-{filename} {data}", file=ftext)
                data = open(subtitle_filename).read().replace('\n',' ').encode().decode('utf-8-sig')
                print(f"unknown-{filename} {data}", file=ftext)

def main():

    args = parse_arguments()

    Path(args.outdir).mkdir(parents=True, exist_ok=True)

    get_text(args.subtitle_file, args.outdir)


if __name__ == "__main__":
    main()
