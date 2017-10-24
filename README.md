# Cutting Edge

## Usage

Bash script tested it out in :
    - OSX
    - Ubuntu 16


## Testing locally

### Requirements

    mkdir test/libs
    git clone https://github.com/sstephenson/bats test/libs/bats
    git clone https://github.com/ztombol/bats-support test/libs/bats-support
    git clone https://github.com/ztombol/bats-assert test/libs/bats-assert
    git clone https://github.com/ztombol/bats-file test/libs/bats-file

### Test BATS files

    ./test/libs/bats/bin/bats test/*.bats
