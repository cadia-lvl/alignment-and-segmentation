import os
import argparse

import pandas as pd


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="""Change the file dependent speaker IDs to the constant anonymized speaker IDs for the diarization data.\n
        Use a metafile containing the mapping code.\n
        Usage: python local/switch_to_true_spkID.py <spkID_mapping-file> <diar-segments-file> <output-diar-segments-file>\n
            E.g. python local/switch_to_true_spkID.py data/reco2spk_num2spk_label.csv data/ruv-di/all_segments data/ruv-di/all_segments_wspkID
        """
    )
    parser.add_argument(
        "--spkID_map", type=file_path, help="spkID mapping file",
    )
    parser.add_argument(
        "--diar_segments", type=file_path, help="diarization segments file",
    )
    parser.add_argument(
        "diar_segments_wspkID", type=str, help="output diarization segments file",
    )
    return parser.parse_args()


def file_path(path):
    if os.path.isfile(path):
        return path
    else:
        raise argparse.ArgumentTypeError(f"readable_file:{path} is not a valid file")


# NOTE! Before i start assigning spkIDs. I need to use reco2spk_num2spk_info.csv to fix the speaker IDs in the ruv-di data, and then put all the segment data into one file
def fix_spkID(meta, diar, seg):
    """Map the infile speaker IDs to the overall ones"""
    for diar_row in diar.itertuples(index=False):
        for meta_row in meta.itertuples(index=False):
            if meta_row[0] == diar_row[3] and meta_row[1] == diar_row[0]:
                seg.write(
                    f"{meta_row[2]}-{diar_row[1]} {meta_row[2]}-{diar_row[3]} {diar_row[4]} {diar_row[5]}\n"
                )
                break


def main():
    args = parse_arguments()

    # use reco2spk_num2spk_label.csv to fix the speaker IDs in the ruv-di data, and then put all the segment data into one file
    meta = pd.read_table(args.spkID_map, header=None, sep=",")
    diar = pd.read_table(args.diar_segments, header=None, delim_whitespace=True,)
    with open(args.diar_segments_wspkID, "w") as seg:
        fix_spkID(meta, diar, seg)


if __name__ == "__main__":
    main()
