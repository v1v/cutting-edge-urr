# Cutting Edge

## Usage

Bash script tested it out in :
* OSX
* Ubuntu 16

## Testing locally

    There are some unit tests for this project, you can run them by following the below details

### Requirements

    ```bash
        mkdir test/libs
        git clone https://github.com/sstephenson/bats test/libs/bats
        git clone https://github.com/ztombol/bats-support test/libs/bats-support
        git clone https://github.com/ztombol/bats-assert test/libs/bats-assert
        git clone https://github.com/ztombol/bats-file test/libs/bats-file
    ```

### Test BATS files

    ```bash
        ./test/libs/bats/bin/bats test/*.bats
    ```

## Known issues

* Gradle plugin is causing some infinite loops.
* GetURL function doesn't solve git+protocol:/organisation/project/submodule since it's solved in the
    transform phase.
