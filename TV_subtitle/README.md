# Alignment system for RÚV TV data and segmentation system for CreditInfo data
These are the scripts for preparing the RÚV TV material and the radio CreditInfo data for ASR

## Table of Contents
[Easy to use TOC generator](https://ecotrust-canada.github.io/markdown-toc/)

## Installation
They are dependent on [Kaldi](https://github.com/kaldi-asr/kaldi) and the
unreleased Ruv-di dataset. These scripts assume there are speaker ids within
the Ruv-di dataset.

**NOTE! Work in progress.** We use code for the expansion that is not in the official Kaldi version. 
**TO DO:** Extract those files from our Kaldi src dir and ship with this recipe

## Running the alignment scripts 
1. To run the scripts, clone this directory in the Kaldi egs folder or just
make sure  that path.sh points to your working version of kaldi.

2. Adjust the directory locations. 

    Within path.sh change ASSET_ROOT and KALDI_ROOT to your directories.

    Change path for exp, data, mfcc, and mfcc_hires in conf/path.conf

    Within run.sh change srcdir and corpusdir, possibly the in-between
    variables too if you don't have the same directory structure.

3. Then, everything can be run through the bash script run.sh. On the command
line type:

    `./run.sh`

## License
These scripts are currently not licensed.

## Authors/Credit
Reykjavik University

Inga Rún Helgadóttir <ingarun@ru.is>

## Acknowledgements
This project was funded by the Language Technology Programme for Icelandic
2019-2023. The programme, which is managed and coordinated by Almannarómur, is
funded by the Icelandic Ministry of Education, Science and Culture.

## Contribution guidelines
To contribute to this project, create a pull request outlining the changes you
want to make and why. Also, use **shellcheck** to get find bugs.
