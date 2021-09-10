# Author: Judy Fong <lvl@judyyfong.xyz.> Reykjavik University
# Description:

import itertools as it
import collections as ct
import more_itertools as m_it

def main():
    # write code here
    print()

    #get the 2nd, 4th, 5h, and 8th columns of rttm file
    # for each row thats a new segment for that audio file
    # example segments file:
    # SPK0033-5004311T0_00000 SPK0033-5004311T0 0 4.875

    rttm_contents = open('data/rttm_threshold', 'r').read().split()
    n = 10
    rows = list(m_it.chunked(rttm_contents, n))
    prev_ep_name = ''
    count = 0
    utter_id = 0
    for row in rows:
        names = row[1].split('-')
        if prev_ep_name ==  names[1]:
            n = int(row[7]) + count
            utter_id = utter_id + 1
        else:
            utter_id = 0
            prev_ep_name = names[1]
            print(prev_ep_name)
            count = count + 1000
            # make sure spk ids between episodes are unique
            n = int(row[7]) + count
        end_time = float(row[4]) + float(row[3])
        # TODO: print to file, segments file specifically
        print(f'SPK{n:05}-{names[1]}_{utter_id:05} unknown-{names[1]} {row[3]} {end_time:.3f}')


if __name__ == '__main__':
    # this portion is run when this file is called directly by the command line
    main()
