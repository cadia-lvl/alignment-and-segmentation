#! /bin/bash
# Author: Judy Fong <lvl@judyyfong.xyz>

# License: Apache 2.0

# Description: TODO: Using the wav.scp and segments files, get the name of the
#   media file, get the path of the media file get the segment name, the name
#   of the media file, the start, and end time Cut the media file into the
#   segments.  Each folder is per show

# example: unknown-4813755-00005 4813755 55.05 60.76
# 4813755 ffmpeg -i /data/misc/ruv_unprocessed/videos/Kiljan/4813755R12.mp4 -ac 1 -ar 16k -f wav - |

# TODO: after audio is split then create dataset
# 1. text will cutt off unknown and preserve the rest of the file
#  cut -c 9-
# 2. segments and wav.scp will be combined as a tsv
#   headers: id (ep_seg_id), episode, show, duration
# 3. create dataset

# Works on one segment for one audio file 
# audio/show/episode/segments
# list of show directory names
start_time=55.05
end_time=60.76
duration=5.71
video=/data/misc/ruv_unprocessed/videos/Kiljan/4813755R12.mp4
audio="unknown-4813755-00005"
segment_dir=data/splitaudiotest/
audio_file="${segment_dir}${audio}.flac"
echo $audio_file
mkdir -p $segment_dir
ffmpeg -ss $start_time -to ${end_time} -i ${video} -ac 1 -ar 16k -f flac ${audio_file}
