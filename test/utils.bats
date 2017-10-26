#!./test/libs/bats/bin/bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
load 'libs/bats-file/load'

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
    "description": "description",
    "envelope": "envelope",
    "validate": "validate"
},
EOT
    cat <<EOT > $LI_FILE
    <li class="list-group-item justify-content-between ">
        name
        <div class="hidden-xs-down">
            <span class="badge badge-pill badge-default">default</span>
            <span class="badge badge-pill badge-info">info</span>
            <span class="badge badge-pill badge-badge">description</span>
            <span class="badge badge-pill badge-envelope">validate</span>
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
    rm ${TEMP_FILE}*
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
    # Without the json extension
    addJSONDependency "group" "artifact" "version" "newversion" "url" "status" "description" "envelope" "validate" ${TEMP_FILE}
    run diff $JSON_FILE $TEMP_FILE
    refute_output ''
    # With the json extension
    addJSONDependency "group" "artifact" "version" "newversion" "url" "status" "description" "envelope" "validate" ${TEMP_FILE}.json
    run diff -w $JSON_FILE ${TEMP_FILE}.json
    assert_output ''

    # Multiline
    cat <<EOT > $TEMP_FILE
{
    "groupId": "group",
    "artifactId": "artifact",
    "version": "version",
    "newVersion": "newversion",
    "url": "url",
    "status": "status",
    "description": "description",
    "envelope": "envelope",
    "validate": "dep0|dep1"
},
EOT
    rm ${TEMP_FILE}.json
    addJSONDependency "group" "artifact" "version" "newversion" "url" "status" "description" "envelope" "dep0\ndep1" ${TEMP_FILE}.json
    run diff -w $TEMP_FILE ${TEMP_FILE}.json
    assert_output ''
}

@test "Should add pom dependency" {
    # Without the xml extension
    addDependency "group" "artifact" "version" $TEMP_FILE
    run diff $DEPENDENCY_FILE $TEMP_FILE
    refute_output ''
    # With the xml extension
    addDependency "group" "artifact" "version" ${TEMP_FILE}.xml
    run diff -w $DEPENDENCY_FILE ${TEMP_FILE}.xml
    assert_output ''
    # With the pme extension
    addDependency "group" "artifact" "version" ${TEMP_FILE}.pme
    run diff -w $DEPENDENCY_FILE ${TEMP_FILE}.pme
    assert_output ''
}

@test "Should add li element" {
    # Without the html extension
    li "name" "default" "info" "badge" "description" "envelope" "validate" $TEMP_FILE
    run diff $LI_FILE $TEMP_FILE
    refute_output ''
    # With the html extension
    li "name" "default" "info" "badge" "description" "envelope" "validate" ${TEMP_FILE}.html
    run diff -w $LI_FILE ${TEMP_FILE}.html
    assert_output ''
}

@test "Should generate dependency when status is success" {
    # Without the xml extension
    notify "group" "artifact" "oldversion" "version" "url" "success" "description" "success" "validate" "/tmp/null" "/tmp/null" ${TEMP_FILE} "/tmp/null"
    run diff $DEPENDENCY_FILE ${TEMP_FILE}
    refute_output ''
    # With the xml extension
    notify "group" "artifact" "oldversion" "version" "url" "success" "description" "success" "validate" "/tmp/null" "/tmp/null" ${TEMP_FILE}.xml "/tmp/null"
    run diff -w $DEPENDENCY_FILE ${TEMP_FILE}.xml
    assert_output ''
    # With the xml extension
    notify "group" "artifact" "oldversion" "version" "url" "success" "description" "success" "validate" "/tmp/null" "/tmp/null" "/tmp/null" ${TEMP_FILE}.xml
    run diff -w $DEPENDENCY_FILE ${TEMP_FILE}.xml
    refute_output ''
}

@test "Should not generate dependency when status is not success" {
    # Without the xml extension
    notify "group" "artifact" "version" "newversion" "url" "failed" "description" "envelope" "validate" "/tmp/null" "/tmp/null" ${TEMP_DIR}/new "/tmp/null"
    assert_file_not_exist ${TEMP_DIR}/new
    # With the xml extension
    notify "group" "artifact" "version" "newversion" "url" "failed" "description" "envelope" "validate" "/tmp/null" "/tmp/null" ${TEMP_FILE}.xml "/tmp/null"
    assert_file_not_exist ${TEMP_FILE}.xml
}

@test "Should getPomProperty property given a pom" {
    run getPomProperty $POM_FILE "project.version"
    assert_output 'version'

    run getPomProperty $POM_FILE "project.version1"
    assert_output 'null object or invalid expression'

    run getPomProperty $WRONG_POM_FILE "project.version"
    refute_output 'version'

    export _JAVA_OPTIONS="-Xmx1g"
    run getPomProperty $WRONG_POM_FILE "project.version"
    refute_output '_JAVA_OPTIONS'
    unset _JAVA_OPTIONS
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

    export _JAVA_OPTIONS="-Xmx1g"
    run getGradleProperty ${TEMP_DIR}/gradle-plugin "name"
    refute_output '_JAVA_OPTIONS'
    unset _JAVA_OPTIONS
}

@test "Should get getXMLProperty given a pom" {
    run getXMLProperty $POM_FILE "/project/artifactId"
    [ "$status" -eq 0 ]
    assert_output 'artifact'
    run getXMLProperty $POM_FILE "//artifactId"
    [ "$status" -eq 0 ]
    assert_output 'artifact'
    run getXMLProperty $WRONG_POM_FILE "//artifactId"
    [ "$status" -eq 1 ]
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

@test "Should analyseTopological when filtering topological errors" {
    cat <<EOT > $TEMP_FILE
[ERROR] Plugin [nodejs]
ERROR Plugin [nodejs]
[ERROR] plugin [nodejs]
[INFO] Plugin [nodejs]
EOT
    run analyseTopological $TEMP_FILE
    assert_output ' [nodejs]'
}

@test "Should getOverridedProperty" {
    cat <<EOT > $TEMP_FILE
[url]

    key = value
EOT
    run getOverridedProperty ${TEMP_FILE} url.key
    [ "$status" -eq 0 ]
    assert_output 'value'
    run getOverridedProperty ${TEMP_FILE} url. @
    [ "$status" -eq 1 ]
    assert_output ''
    run getOverridedProperty "null" url.key
    [ "$status" -eq 1 ]
    assert_output ''
}