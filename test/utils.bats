#!./test/libs/bats/bin/bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

setup() {
    source utils.sh
    export SETTINGS="$HOME/.m2/settings.xml"
    export EMPTY_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export TEMP_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export JSON_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export DEPENDENCY_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export LI_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export POM_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export WRONG_POM_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export TEMP_DIR=$(mktemp -d /tmp/bats.XXXXXXXXXX)
    cat <<EOT > $POM_FILE
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>group</groupId>
    <artifactId>artifact</artifactId>
    <version>version</version>
</project>
EOT
    cat <<EOT > $DEPENDENCY_FILE
<dependency><groupId>group</groupId><artifactId>artifact</artifactId><version>version</version></dependency>
EOT
    cat <<EOT > $JSON_FILE
{
    "groupId": "group",
    "artifactId": "artifact",
    "version": "version",
    "newVersion": "newversion",
    "url": "url",
    "status": "status",
    "description": "description"
},
EOT
    cat <<EOT > $LI_FILE
    <li class="list-group-item justify-content-between ">
        name
        <div class="hidden-xs-down">
            <span class="badge badge-pill badge-default">default</span>
            <span class="badge badge-pill badge-info">info</span>
            <span class="badge badge-pill badge-badge">description</span>
        </div>
    </li>
EOT
    cat <<EOT > $WRONG_POM_FILE
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>group</groupId>
    <artifactId>artifact</artifactId>
    <version>version</version>
EOT
}

teardown() {
    rm ${TEMP_FILE}
    rm ${JSON_FILE}
    rm ${DEPENDENCY_FILE}
    rm ${LI_FILE}
    rm ${EMPTY_FILE}
    rm ${POM_FILE}
    rm ${WRONG_POM_FILE}
    rm -rf ${TEMP_DIR}
}

@test "Should parse GitHub if GitHub URLs" {
    skip "This command has been deprecated"
    cat <<EOT > $TEMP_FILE
    http://github.com/user/project.git
    https://github.com/user/project
    https://username::;*%$:@github.com/username/repository.git
    https://username:$fooABC@:@github.com/username/repository.git
    https://username:password@github.com/username/repository.git'
EOT

    while read -r url; do
        run normaliseGitHubRepoLayout ${url}
        assert_output $url
    done <$TEMP_FILE
}

@test "Should normalise packaging" {
    normalisePackagingIssue $TEMP_FILE
    run cat $TEMP_FILE
    assert_output ""

    cat <<EOT > $TEMP_FILE
<packaging>hpi</packaging>
EOT
    normalisePackagingIssue $TEMP_FILE
    run cat $TEMP_FILE
    assert_output ''

    cat <<EOT > $TEMP_FILE
    <packaging>jar</packaging>
EOT
    normalisePackagingIssue $TEMP_FILE
    run cat $TEMP_FILE
    assert_output --partial 'jar'
}

@test "Should add json element" {
    addJSONDependency "group" "artifact" "version" "newversion" "url" "status" "description" $TEMP_FILE
    run diff $JSON_FILE $TEMP_FILE
    assert_output ''
}

@test "Should add pom dependency" {
    addDependency "group" "artifact" "version" $TEMP_FILE
    run diff $DEPENDENCY_FILE $TEMP_FILE
    assert_output ''
}

@test "Should add li element" {
    li "name" "default" "info" "badge" "description" $TEMP_FILE
    run diff $LI_FILE $TEMP_FILE
    assert_output ''
}

@test "Should generate dependency when status is success" {
    notify "group" "artifact" "oldversion" "version" "url" "success" "description" "/tmp/null" "/tmp/null" $TEMP_FILE
    run diff $DEPENDENCY_FILE $TEMP_FILE
    assert_output ''
}

@test "Should not generate dependency when status is not success" {
    notify "group" "artifact" "version" "newversion" "url" "failed" "description" "/tmp/null" "/tmp/null" $TEMP_FILE
    run diff $EMPTY_FILE $TEMP_FILE
    assert_output ''
}

@test "Should getPomProperty property given a pom" {
    run getPomProperty $POM_FILE "project.version"
    assert_output 'version'

    run getPomProperty $POM_FILE "project.version1"
    assert_output 'null object or invalid expression'

    run getPomProperty $WRONG_POM_FILE "project.version"
    refute_output 'version'
}

@test "Should getGradleProperty property given gradle project" {
    source helper.sh
    download https://github.com/jenkinsci/gradle-plugin.git "${TEMP_DIR}/gradle-plugin"

    run getGradleProperty ${TEMP_DIR}/gradle-plugin "name"
    assert_output 'gradle-plugin'

    run getGradleProperty ${TEMP_DIR}/gradle-plugin "unknown"
    assert_output ''

    run getGradleProperty $WRONG_POM_FILE "name"
    refute_output 'gradle-plugin'
}

@test "Should get getXMLProperty given a pom" {
    run getXMLProperty $POM_FILE "/project/artifactId"
    assert_output 'artifact'
    run getXMLProperty $POM_FILE "//artifactId"
    assert_output 'artifact'
    run getXMLProperty $WRONG_POM_FILE "//artifactId"
    assert_output --partial 'Premature end of data'
}

@test "Testing convertHttps2Git with different scenarios" {
    run convertHttps2Git "http://github.com/user/project.git"
    assert_output "git@github.com:user/project.git"
    run convertHttps2Git "https://github.com/user/project.git"
    assert_output "git@github.com:user/project.git"
    run convertHttps2Git "https://github.com/user/project"
    assert_output "git@github.com:user/project"
    run convertHttps2Git "http://github.com/user/project"
    assert_output "git@github.com:user/project"
    run convertHttps2Git "https://username:password@github.com/user/project"
    assert_output "git@github.com:user/project"
    run convertHttps2Git 'https://username:$fooABC@:@github.com/user/project'
    assert_output "git@github.com:user/project"
    run convertHttps2Git 'https://username::;*%$:@github.com/user/project'
    assert_output "git@github.com:user/project"
    run convertHttps2Git "git@github.com:user/project.git"
    assert_output "git@github.com:user/project.git"
}
