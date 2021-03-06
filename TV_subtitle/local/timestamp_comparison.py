#!/usr/bin/env python3

import os
import argparse
from pathlib import Path
import pandas as pd

# NOTE This is a copy of the ipython notebook with the same name. It has not been process into a real script

# I need to find which speakers are within a subtitle time range.
# I have a list of speakers and timestamps in data/ruv-di/<filename>/ruvdi_segments, let's call them diarization segments, and subtitle timestamps in /data/transcripts/<filename>/segments
# I have to find within which diarization timestamps the subtitle timestamps lie and assign the corresponding spkID to the subtitle timestamp


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="""Pair speaker identified diarization segments with the new segments obtained from audio-subtitle text alignment by\n
        finding out which speakers are within a subtitle time range.
        Usage: python local/timestamp_comparison.py <input-file> <output-dir>\n
            E.g. python local/timestamp_comparison.py data/vtt_transcripts/4886083R7.vtt data
        """
    )
    # NOTE! How does this work? Should I call it --loose instead and is it then strict if not provided?
    parser.add_argument(
        "--collar",
        nargs="?",
        default=0.25,
        type=float,
        help="How far outside the diarization segment (end timestamp) can the subtitle segment go in seconds",
    )
    parser.add_argument(
        "--subtitle_segments_file", type=file_path, help="Input subtitle segments file",
    )
    parser.add_argument(
        "--diar_segments_wspkID",
        type=file_path,
        help="diarization segments file with speaker IDs",
    )
    parser.add_argument(
        "--segments_out",
        type=str,
        help="output subtitle segments file with speaker IDs",
    )
    parser.add_argument(
        "--utt2spk_out",
        type=str,
        help="output subtitle utterance ID to speaker ID file",
    )
    return parser.parse_args()


def file_path(path):
    if os.path.isfile(path):
        return path
    else:
        raise argparse.ArgumentTypeError(f"readable_file:{path} is not a valid file")


def extract_spk(sub, spkdi, seg, utt2spk, collar):
    reco_ids = sub[1].unique()  # List of all recording IDs
    for recoid in reco_ids:
        # Create new dataframes with only lines containing this recording ID
        spkdi_part = spkdi[spkdi[1].str.contains(recoid)]
        sub_part = sub[sub[1].str.contains(recoid)]
        # start = 0
        for sub_row in sub_part.itertuples(index=False):
            # Find all rows in the diarization data that have segment start before my subtitle start and segment end after it
            dirows = spkdi_part.loc[
                (spkdi_part[2] <= sub_row[2]) & ((spkdi_part[3] + collar) >= sub_row[3])
            ]
            if not dirows.empty:
                spkid = str(dirows[0]).split("-")[0]  # Extract the spkID from the uttID
                spkid2 = spkid.split()[1]  # Otherwise line numbers come in front
                sub_recoid, count = sub_row[0].split("-")[1:3]
                seg.write(
                    f"{spkid2}-{sub_recoid}-{count} {sub_recoid} {sub_row[2]} {sub_row[3]}\n"
                )
                utt2spk.write(f"{spkid2}-{sub_recoid}-{count} {spkid2}\n")


def main():
    args = parse_arguments()

    output_segments = args.segments_out
    outdir = os.path.dirname(output_segments)
    Path(outdir).mkdir(parents=True)

    sub = pd.read_table(args.subtitle_segments_file, header=None, sep="\s+")
    spkdi = pd.read_table(args.diar_segments_wspkID, header=None, sep="\s+")

    # Pair my speaker identified diarization segments with the new segments obtained from audio-subtitle text alignment, which need speaker IDs.
    # Actually, I'm being a bit lenient by allowing the subtitle timestampe to exceed the diarization one by 0.5 sec
    with open(output_segments, "w") as seg, open(args.utt2spk_out, "w") as utt2spk:
        extract_spk(sub, spkdi, seg, utt2spk, collar=args.collar)


if __name__ == "__main__":
    main()

