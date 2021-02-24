#!/usr/bin/env python3

# Author: David Erik Mollberg, Inga Run Helgadottir (Reykjavik University)
# Description:
# This script will create the files text, wav.scp, utt2spk, spk2utt and spk2gender,
# where the text in the text column has been split up by speakers.

import subprocess
import argparse
import string
import re
from pathlib import Path
import pandas as pd


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="""This script will output the files text, wav.scp, utt2spk, spk2utt and spk2gender\n
        to data/train, data/eval and data/test, with test/train/eval splits defined in the metadatafile.\n
        Usage: python3 samromur_prep_data.py <path-to-samromur-audio> <info-file-training>\n
            E.g. python3 prep_data.py /data/asr/creditinfo/audio data/creditinfo_data.tsv\n
        """
    )
    parser.add_argument(
        "audio_dir", type=dir_path, help="The audio dir",
    )
    parser.add_argument(
        "meta_file", type=file_path, help="The metadata file",
    )
    parser.add_argument(
        "output_dir", type=str, help="Where to place the created files",
    )
    return parser.parse_args()


def file_path(path: str):
    if Path(path).is_file():
        return path
    else:
        raise argparse.ArgumentTypeError(f"readable_file:{path} is not a valid file")


def dir_path(path: str):
    if Path(path).is_dir():
        return path
    else:
        raise argparse.ArgumentTypeError(f"Directory:{path} is not a valid directory")


def get_info(s):
    try:
        s2 = (
            s.split("[", 1)[0]
            .strip('"')
            .replace(", ", ",")
            .strip(" ")
            .replace(". ", ".")
            .split(".")
        )
        info_array = [l.split(",") for l in s2]
        return info_array
    except AttributeError:
        print(s)
        return 1


def get_sec(time_str):
    """Get Seconds from time."""
    h, m, s, _ = time_str.split(":")
    return int(h) * 3600 + int(m) * 60 + int(s)


def fetch_anonymous(spkdict, name):
    if name in spkdict.keys():
        return spkdict[name]
    else:
        length = len(spkdict) + 1
        spkdict[name] = f"SPK{length:04d}"
        return spkdict[name]


def append_to_file(df, audio_dir: str, text, wavscp, utt2spk, spk2gender, seg):
    """
    Append relevant data to the files
    """
    # Update the speaker IDs to the new ones for each segment then segment.
    # Estimate new timestamps based on how many words appear before each new
    # sub-segment and add some extra time on each side

    spkdict = dict()
    for i in df.index:
        s = df.at[i, "texti"]
        info_array = get_info(s)

        for speaker in info_array:
            if len(speaker) > 2:
                name = speaker[0]
                spkID = speaker[1]
                new_spkID = fetch_anonymous(spkdict, name)
                s = re.sub(r"\b%s\b" % spkID, new_spkID, s)
                # with open("old_to_new_spkID.tmp", "a") as id:
                #    id.write(f"{spkID} {new_spkID}\n")

                isl_gender = speaker[2][:-1]
                if isl_gender == "kk":
                    gender = "m"
                else:
                    gender = "f"
                spk2gender.write(f"{new_spkID} {gender}\n")

        s2 = s.split("[", 1)[1]
        utts = [utt.split("]") for utt in s2.split("[")]
        # Count the number of words in the original segments (excluding speaker info and IDs)
        num_words = len(" ".join([el[1] for el in utts]).split())
        segm_length = df.at[i, "lengd_i_sek"]
        sek_per_word = segm_length / num_words

        cnt = 0
        prev_words = 0
        for utt in utts:
            uttID = f"{utt[0]}-{df.at[i, 'ScriptID']}_{cnt}"
            text.write(f"{uttID} {utt[1].lower()}\n")
            cnt += 1

            wavscp.write(
                f"{df.at[i, 'ScriptID']} sox - -c1 -esigned -r 16000 -twav - < {Path(audio_dir).joinpath(df.at[i, 'skra'])} |\n"
            )
            utt2spk.write(f"{uttID} {utt[0]}\n")
            # Move the segment start based on how many words come before it
            # Approximate that one words is about 25 milliseconds long
            # Buffer the segments by 2 seconds in both directions
            start = get_sec(df.at[i, "byrjar"]) + sek_per_word * prev_words - 5
            stop = (
                start + sek_per_word * len(utt[1].split()) + 10
            )  # 5 sec before, 5 after ## 2 sec before, 2 after
            if start < 0:
                start = 0.0
            # if stop > get_sec(df.at[i, "endar"]):
            #     stop = get_sec(df.at[i, "endar"])
            seg.write(f"{uttID} {df.at[i, 'ScriptID']} {start} {stop}\n")
            prev_words += len(utt[1].split())


def clean_dir(outdir):
    subprocess.call(
        f"utils/utt2spk_to_spk2utt.pl < {outdir}/utt2spk > {outdir}/spk2utt",
        shell=True,
    )
    subprocess.call(
        f"utils/validate_data_dir.sh --no-feats {outdir} || utils/fix_data_dir.sh {outdir}",
        shell=True,
    )


def main():

    args = parse_arguments()

    audio_dir = args.audio_dir
    metadata = args.meta_file
    outdir = args.output_dir
    Path(outdir).mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(metadata, sep="\t")

    Path(outdir).mkdir(parents=True, exist_ok=True)
    print(f"\nCreating files in {outdir}")

    with open(f"{outdir}/text", "w") as text, open(
        f"{outdir}/wav.scp", "w"
    ) as wav, open(f"{outdir}/utt2spk", "w") as utt2spk, open(
        f"{outdir}/spk2gender", "w"
    ) as spk2gender, open(
        f"{outdir}/segments", "w"
    ) as seg:
        append_to_file(df, audio_dir, text, wav, utt2spk, spk2gender, seg)

    clean_dir(outdir)


if __name__ == "__main__":
    main()
