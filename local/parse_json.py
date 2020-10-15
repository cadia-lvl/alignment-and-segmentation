#!/usr/bin/env python3

import os
import argparse
import json


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="""Parse a json file from the ruv-di dataset to get segment and utt2spk information\n
        Usage: python parse_json.py <input-file>\n
            E.g. python local/parse_json.py /data/ruv-di/version0001/json/4886083R7.json
        """
    )
    parser.add_argument(
        "infile", type=file_path, help="JSON file to parse",
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


def hasNumbers(inputString):
    return any(char.isdigit() for char in inputString)


def extract_spk_and_time(input_list, filename):

    seg = []
    utt2spk = []
    count = 0
    for d in input_list:
        diar_id = d["speaker"]["id"]
        if not hasNumbers(diar_id):
            continue
        elif "foreign" in diar_id or "crosstalk" in diar_id:
            continue
        else:
            spkid = " ".join([s for s in diar_id.split("+") if s.isdigit()])
            if not len(spkid.split()) > 1:
                seg.append(
                    f"{spkid}-{filename}_{count:05d} {spkid}-{filename} {d['start']} {d['end']}"
                )
                utt2spk.append(f"{spkid}-{filename}_{count:05d} {spkid}")
        count = count + 1
    return seg, utt2spk


def main():

    args = parse_arguments()

    with open(args.infile, "r") as f:
        input_dict = json.load(f)
    input_list = input_dict["monologues"]

    base = os.path.basename(args.infile)
    (filename, _) = os.path.splitext(base.replace("_", ""))
    # show_title = os.path.basename(os.path.dirname(json_filename))

    # base_path = "data/ruv-di/"
    base_path = args.outdir
    outdir = base_path + "/" + filename
    if not os.path.exists(base_path):
        os.makedirs(base_path)

    if not os.path.exists(outdir):
        os.makedirs(outdir)

    # Extract the segment timestamps and speaker IDs
    seg, utt2spk = extract_spk_and_time(input_list, filename)

    with open(outdir + "/ruvdi_segments", "w") as fseg:
        fseg.write("\n".join(seg))

    with open(outdir + "/ruvdi_utt2spk", "w") as futt2spk:
        futt2spk.write("\n".join(utt2spk))


if __name__ == "__main__":
    main()
