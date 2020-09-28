import pandas as pd

# NOTE This is a copy of the ipython notebook with the same name. It has not been process into a real script

# I need to find which speakers are within a subtitle time range.
# I have a list of speakers and timestamps in data/ruv-di/<filename>/ruvdi_segments, let's call them diarization segments, and subtitle timestamps in /data/transcripts/<filename>/segments
# I have to find within which diarization timestamps the subtitle timestamps lie and assign the corresponding spkID to the subtitle timestamp
# NOTE! Before i start assigning spkIDs. I need to use reco2spk_num2spk_info.csv to fix the speaker IDs in the ruv-di data, and then put all the segment data into one file
def fix_spkID(meta, diar, seg):
    """Map the infile speaker IDs to the overall ones"""
    for diar_row in diar.itertuples(index=False):
        for meta_row in meta.itertuples(index=False):
            if meta_row[0] == diar_row[3] and meta_row[1] == diar_row[0]:
                seg.write(
                    f"{meta_row[3]}-{diar_row[1]} {meta_row[3]}-{diar_row[3]} {diar_row[4]} {diar_row[5]}\n"
                )
                break


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


if __name__ == "__main__":

    # use reco2spk_num2spk_info.csv to fix the speaker IDs in the ruv-di data, and then put all the segment data into one file
    meta = pd.read_table(
        "/home/staff/inga/h2/data/reco2spk_num2spk_info.csv", header=None, sep=","
    )
    diar = pd.read_table(
        "/home/staff/inga/h2/data/ruv-di/all_segments",
        header=None,
        delim_whitespace=True,
    )

    with open("/home/staff/inga/h2/data/ruv-di/all_segments_wspkID", "w") as seg:
        fix_spkID(meta, diar, seg)
    # Now I can pair my speaker identified diarization segments with the new segments obtained from audio-subtitle text alignment, which need speaker IDs.

    sub = pd.read_table(
        "/work/inga/data/h2/judy_reseg/segments", header=None, delim_whitespace=True
    )
    spkdi = pd.read_table(
        "/home/staff/inga/h2/data/ruv-di/all_segments_wspkID",
        header=None,
        delim_whitespace=True,
    )

    # Actually, I'm being a bit lenient by allowing the subtitle timestampe to exceed the diarization one by 0.5 sec
    strict = True
    with open("/work/inga/data/h2/judy_reseg/segments_wspkid_strict2", "w") as seg:
        extrack_spk(sub, spkdi, seg, strict=True)

