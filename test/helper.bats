#!./test/libs/bats/bin/bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

setup() {
    source helper.sh
    export TEMP_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export EFFECTIVE_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export TEMP_DIR=$(mktemp -d /tmp/bats.XXXXXXXXXX)
    export OVERRIDE_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export NO_SCM_POM_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export CONNECTION_POM_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export TEMP_DIR_NEW=${TEMP_DIR}.new
    export JSON_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export ENVELOPE_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export DIFFERENT_VERSION_JSON_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)

    cat <<EOT > $OVERRIDE_FILE
[url]
    ant = overrided_url
EOT

    cat <<EOT > $NO_SCM_POM_FILE
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>group</groupId>
  <artifactId>artifact</artifactId>
  <version>1.0</version>
  <packaging>hpi</packaging>
</project>
EOT

    cat <<EOT > $CONNECTION_POM_FILE
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>org.jenkins-ci.plugins</groupId>
  <artifactId>gradle</artifactId>
  <version>1.26</version>
  <packaging>hpi</packaging>
  <scm>
    <connection>scm:git:git://github.com/jenkinsci/gradle-plugin.git</connection>
  </scm>
</project>
EOT

    # Using templates
    cp */resource/verify/dependencies.json $JSON_FILE
    cp */resource/verify/envelope.json $ENVELOPE_FILE
    cp */resource/verify/different_version_dependencies.json $DIFFERENT_VERSION_JSON_FILE
}

teardown() {
    rm ${TEMP_FILE}
    rm -rf ${TEMP_DIR}
    rm -rf ${TEMP_DIR_NEW}
    rm ${OVERRIDE_FILE}
    rm ${NO_SCM_POM_FILE}
    rm ${CONNECTION_POM_FILE}
    rm $EFFECTIVE_FILE
    rm ${JSON_FILE}
    rm ${ENVELOPE_FILE}
    rm ${DIFFERENT_VERSION_JSON_FILE}
}

@test "Should return effective POM" {
    wget -q "https://raw.githubusercontent.com/jenkinsci/maven-plugin/maven-plugin-3.0/pom.xml" -O ${TEMP_FILE}
    run getEffectivePom ${TEMP_FILE} ${EFFECTIVE_FILE} "${TEMP_DIR_NEW}"
    [ "$status" -eq 0 ]

    run getEffectivePom "null" ${EFFECTIVE_FILE} "${TEMP_DIR_NEW}"
    [ "$status" -eq 1 ]
}

@test "Should return URL when queering Maven plugin" {
    wget -q "https://raw.githubusercontent.com/jenkinsci/maven-plugin/maven-plugin-3.0/pom.xml" -O ${TEMP_FILE}
    run getURL ${TEMP_FILE} "${TEMP_DIR_NEW}" true ${OVERRIDE_FILE}
    assert_output "http://github.com/jenkinsci/maven-plugin"
}

@test "Should return overrided_url when quering ANT plugin in an existing override file" {
    wget -q "https://raw.githubusercontent.com/jenkinsci/ant-plugin/ant-1.7/pom.xml" -O ${TEMP_FILE}
    run getURL ${TEMP_FILE} "${TEMP_DIR_NEW}" true ${OVERRIDE_FILE}
    assert_output "overrided_url"
}

@test "Should return unreachalbe when quering ace-editor plugin " {
    wget -q "https://raw.githubusercontent.com/jenkinsci/js-libs/master/ace-editor/pom.xml" -O ${TEMP_FILE}
    run getURL ${TEMP_FILE} "${TEMP_DIR_NEW}" true ${OVERRIDE_FILE}
    assert_output ${CTE_SCM}
}

@test "Should return scm when quering POM without SCM " {
    run getURL ${NO_SCM_POM_FILE} "${TEMP_DIR_NEW}" true ${OVERRIDE_FILE}
    assert_output ${CTE_SCM}
}

@test "Should return connection URL when quering POM scm " {
    run getURL ${CONNECTION_POM_FILE} "${TEMP_DIR_NEW}" true ${OVERRIDE_FILE}
    assert_output "git://github.com/jenkinsci/gradle-plugin.git"
}

@test "Should return same git url when based on organisation/repo" {
    cat <<EOT > $TEMP_FILE
    https://github.com/user/project
    https://username::;*%$:@github.com/username/repository.git
    https://username::;*%$:@github.com/username/repository
    https://username:$fooABC@:@github.com/username/repository.git
    https://username:$fooABC@:@github.com/username/repository
    https://username:password@github.com/username/repository.git
    https://username:password@github.com/username/repository
    git@github.com:/cloudbees/project
    git@github.com:/cloudbees/project.git
EOT
    while read -r url; do
        run transform ${url}
        assert_output $url
    done <$TEMP_FILE
}

@test "Should transform git url based on organisation/repo" {
    run transform 'http://github.com/user/project.git/submodule'
    assert_output 'https://github.com/user/project.git'
    run transform 'https://github.com/user/project/submodule'
    assert_output 'https://github.com/user/project'
    run transform 'https://username::;*%$:@github.com/username/repository.git/submodule'
    assert_output 'https://username::;*%$:@github.com/username/repository.git'
    run transform 'https://username::;*%$:@github.com/username/repository/submodule'
    assert_output 'https://username::;*%$:@github.com/username/repository'
    run transform 'https://username:$fooABC@:@github.com/username/repository.git/submodule'
    assert_output 'https://username:$fooABC@:@github.com/username/repository.git'
    run transform 'https://username:$fooABC@:@github.com/username/repository/submodule'
    assert_output 'https://username:$fooABC@:@github.com/username/repository'
    run transform 'https://username:password@github.com/username/repository.git/submodule'
    assert_output 'https://username:password@github.com/username/repository.git'
    run transform 'https://username:password@github.com/username/repository/submodule'
    assert_output 'https://username:password@github.com/username/repository'
    run transform 'git@github.com:/cloudbees/project/submodule'
    assert_output 'git@github.com:/cloudbees/project'
    run transform 'git@github.com:/cloudbees/project/submodule.git'
    assert_output 'git@github.com:/cloudbees/project'
    run transform 'scm:git:git://github.com/cloudbees/repository.git/submodule'
    assert_output 'git@github.com:cloudbees/repository.git'
}

@test "Should return git+ssh when using cloudbees private repo" {
    run transform 'http://github.com/cloudbees/project.git'
    assert_output 'git@github.com:cloudbees/project.git'
    run transform 'http://github.com/cloudbees/project'
    assert_output 'git@github.com:cloudbees/project'
    run transform 'https://username:password@github.com/cloudbees/repository.git/submodule'
    assert_output 'git@github.com:cloudbees/repository.git'
    run transform 'https://username:password@github.com/cloudbees/repository/submodule'
    assert_output 'git@github.com:cloudbees/repository'
    run transform 'scm:git:git://github.com/cloudbees/repository.git'
    assert_output 'git@github.com:cloudbees/repository.git'
    run transform 'git@github.com:cloudbees/cloudbees-aws-cli-plugin.git'
    assert_output 'git@github.com:cloudbees/cloudbees-aws-cli-plugin.git'
}

@test "Should return git+https when using public repos with git+git" {
    run transform 'git://github.com/jenkinsci/project.git'
    assert_output 'https://github.com/jenkinsci/project.git'
    run transform 'git://github.com/jenkinsci/project'
    assert_output 'https://github.com/jenkinsci/project'
    run transform 'git://github.com/jenkinsci/project/asa'
    assert_output 'https://github.com/jenkinsci/project'
}

@test "Should transform scm/connection urls" {
    run transform 'scm:git:git://github.com/user/repo.git'
    assert_output 'https://github.com/user/repo.git'
    run transform 'scm:git:git@github.com:user/repo.git'
    assert_output 'https://github.com/user/repo.git'
    run transform 'scm:git:git://github.com/cloudbees/repo.git'
    assert_output 'git@github.com:cloudbees/repo.git'
    run transform 'scm:git:git@github.com:cloudbees/repo.git'
    assert_output 'git@github.com:cloudbees/repo.git'
}

@test "Should download" {
    run download "https://github.com/octocat/Hello-World" ${TEMP_DIR}
    assert_output "${CTE_SKIPPED}"
    run download "https://github.com/octocat/Hello-World1" "${TEMP_DIR_NEW}"
    assert_output "${CTE_UNREACHABLE}"
    run download "https://github.com/octocat/Hello-World" "${TEMP_DIR_NEW}"
    assert_output "${CTE_PASSED}"
}

@test "Should buildDependency" {
    download https://github.com/dantheman213/java-hello-world-maven.git "${TEMP_DIR_NEW}"
    run buildDependency "${TEMP_DIR_NEW}" "${TEMP_FILE}" "${HOME}/.m2/settings.xml" true
    assert_output "${CTE_PASSED}"
    echo "passed" > "${TEMP_DIR_NEW}/.status.flag"
    run buildDependency "${TEMP_DIR_NEW}" "${TEMP_FILE}" "${HOME}/.m2/settings.xml" true
    assert_output "${CTE_PASSED}"
    echo "failed" > "${TEMP_DIR_NEW}/.status.flag"
    run buildDependency "${TEMP_DIR_NEW}" "${TEMP_FILE}" "${HOME}/.m2/settings.xml" true
    assert_output "${CTE_FAILED}"
}

@test "Should buildDependency with override options for some maven customised builds" {
    download https://github.com/dantheman213/java-hello-world-maven.git "${TEMP_DIR_NEW}/maven"
    cat <<EOT > ${TEMP_DIR}/myapp.build
[build]
    command = mvn --help
EOT
    run buildDependency "${TEMP_DIR_NEW}/maven" "${TEMP_FILE}" "${HOME}/.m2/settings.xml" "true" "${TEMP_DIR}"
    assert_output "${CTE_PASSED}"

    # This is cached
    cat <<EOT > ${TEMP_DIR}/myapp.build
[build]
    command = mvn axz
EOT
    run buildDependency "${TEMP_DIR_NEW}/maven" "${TEMP_FILE}" "${HOME}/.m2/settings.xml" "true" "${TEMP_DIR}"
    assert_output "${CTE_PASSED}"

    # remove cached flag
    rm ${TEMP_DIR_NEW}/maven/.status.flag
    cat <<EOT > ${TEMP_DIR}/myapp.build
[build]
    command = mvn axz
EOT
    run buildDependency "${TEMP_DIR_NEW}/maven" "${TEMP_FILE}" "${HOME}/.m2/settings.xml" "true" "${TEMP_DIR}"
    assert_output "${CTE_FAILED}"
}

@test "Should buildDependency with override options for gradle customised builds" {
    download https://github.com/jenkinsci/gradle-plugin.git "${TEMP_DIR_NEW}/gradle-plugin"
    cat <<EOT > ${TEMP_DIR}/gradle-plugin.build
[build]
    command = ./gradlew tasks
EOT
    run buildDependency "${TEMP_DIR_NEW}/gradle-plugin" "${TEMP_FILE}" "${HOME}/.m2/settings.xml" "true" "${TEMP_DIR}"
    assert_output "${CTE_PASSED}"

    cat <<EOT > ${TEMP_DIR}/gradle-plugin.build
[build]
    command = ./xyz
EOT
    # This is cached
    run buildDependency "${TEMP_DIR_NEW}/gradle-plugin" "${TEMP_FILE}" "${HOME}/.m2/settings.xml" "true" "${TEMP_DIR}"
    assert_output "${CTE_PASSED}"

    # This is cached
    rm ${TEMP_DIR_NEW}/gradle-plugin/.status.flag
    run buildDependency "${TEMP_DIR_NEW}/gradle-plugin" "${TEMP_FILE}" "${HOME}/.m2/settings.xml" "true" "${TEMP_DIR}"
    assert_output "${CTE_FAILED}"
}

@test "Should cleanLeftOvers" {
    run cleanLeftOvers "${TEMP_DIR}" "/dev/null"
    assert_output ""
    [ "$status" -eq 0 ]

    run cleanLeftOvers "${TEMP_DIR}/1" "/dev/null"
    assert_output ""
    [ "$status" -eq 0 ]
}

@test "Should not verify when no files" {
    run verify "" "" "/dev/null"
    assert_output "${CTE_WARNING}"
    [ "$status" -eq 1 ]

    run verify "foo" "bar" "/dev/null"
    assert_output "${CTE_WARNING}"
    [ "$status" -eq 1 ]

    run verify "" "bar" "/dev/null"
    assert_output "${CTE_WARNING}"
    [ "$status" -eq 1 ]

    run verify "foo" "" "/dev/null"
    assert_output "${CTE_WARNING}"
    [ "$status" -eq 1 ]

    run verify "${JSON_FILE}" "${ENVELOPE_FILE}" "/dev/null"
    assert_output ""
    [ "$status" -eq 0 ]
}

@test "Should verify when files" {
    run verify "${JSON_FILE}" "${ENVELOPE_FILE}" "/dev/null"
    assert_output ""
    [ "$status" -eq 0 ]

    run verify "${DIFFERENT_VERSION_JSON_FILE}" "${ENVELOPE_FILE}" "${TEMP_FILE}"
    [ "$status" -eq 1 ]
    run cat ${TEMP_FILE}
    assert_output "WARN: org.jenkins-ci.plugins:active-directory envelope-version '2.7-SNAPSHOT' doesn't match pme-version '1.2-SNAPSHOT'"
}

@test "Should getJsonPropertyFromEnvelope" {
    run getJsonPropertyFromEnvelope 'credentials' 'groupId' $ENVELOPE_FILE
    assert_output "org.jenkins-ci.plugins"
    [ "$status" -eq 0 ]

    run getJsonPropertyFromEnvelope 'credentials' 'wrong' $ENVELOPE_FILE
    assert_output "null"
    [ "$status" -eq 0 ]

    run getJsonPropertyFromEnvelope 'key' 'groupId' $ENVELOPE_FILE
    assert_output "null"
    [ "$status" -eq 0 ]
}

