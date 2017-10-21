#!./test/libs/bats/bin/bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

setup() {
    source utils.sh
    export SETTINGS="$HOME/.m2/settings.xml"
    export TEMP_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export EDGE_CMD="sh ${BATS_TEST_DIRNAME}/../edge.sh"
}

teardown() {
    rm ${TEMP_FILE}
}

@test "Run edge with no arguments" {
    run ${EDGE_CMD}
    assert_output --partial 'INFO: Using default values'
}

@test "Run edge with --help option" {
    run ${EDGE_CMD} --help
    [ "$status" -eq 0 ]
}

@test "Run edge with --settings option" {
    run ${EDGE_CMD} --settings foo
    [ "$status" -eq 1 ]
    run ${EDGE_CMD} --settings $TEMP_FILE
    [ "$status" -eq 0 ]
}
