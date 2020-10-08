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
    parser.add_argument(
        "--strict",
        default=True,
        action="store_false",
        help="Should the speaker ID pairing be strict or loose, i.e. should both timestamps be inside a diarization segments",
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
    return parser.parse_args()


def file_path(path):
    if os.path.isfile(path):
        return path
    else:
        raise argparse.ArgumentTypeError(f"readable_file:{path} is not a valid file")


def extrack_spk(sub, spkdi, seg, strict: bool):
    ids = sub[1].unique()
    recoid_list = [id.split("-")[1] for id in ids]  # List of all recording IDs
    for recoid in recoid_list:
        # Create new dataframes with only lines containing this recording ID
        spkdi_part = spkdi[spkdi[1].str.contains(recoid)]
        sub_part = sub[sub[1].str.contains(recoid)]
        # start = 0
        for sub_row in sub_part.itertuples(index=False):
            # Find all rows is diarization data that have segment start before my subtitle start and segment end after it
            if strict:
                dirows = spkdi_part.loc[
                    (spkdi_part[2] <= sub_row[2])
                    & ((spkdi_part[3] + 0.5) >= sub_row[3])
                ]
            else:
                dirows = spkdi_part.loc[
                    (spkdi_part[2] <= sub_row[2]) & (spkdi_part[3] >= sub_row[2])
                ]
            if not dirows.empty:
                spkid = str(dirows[1]).split("-")[0]  # Extract the spkID from the uttID
                spkid2 = spkid.split()[1]
                sub_recoid, count = sub_row[0].split("-")[1:3]
                seg.write(
                    f"{spkid2}-{sub_recoid}-{count} {spkid2}-{sub_recoid} {sub_row[2]} {sub_row[3]}\n"
                )


def main():
    args = parse_arguments()

    output_segments = args.segments_out
    outdir = os.path.dirname(output_segments)
    Path(outdir).mkdir()

    sub = pd.read_table(args.subtitle_segments_file, header=None, sep="\s+")
    spkdi = pd.read_table(args.diar_segments_wspkID, header=None, sep="\s+")

    # Pair my speaker identified diarization segments with the new segments obtained from audio-subtitle text alignment, which need speaker IDs.
    # Actually, I'm being a bit lenient by allowing the subtitle timestampe to exceed the diarization one by 0.5 sec
    with open(output_segments, "w") as seg:
        extrack_spk(sub, spkdi, seg, strict=args.strict)


if __name__ == "__main__":
    main()

