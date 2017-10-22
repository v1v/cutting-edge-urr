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

}

teardown() {
    rm ${TEMP_FILE}
    rm -rf ${TEMP_DIR}
    rm -rf ${TEMP_DIR_NEW}
    rm ${OVERRIDE_FILE}
    rm ${NO_SCM_POM_FILE}
    rm ${CONNECTION_POM_FILE}
    rm $EFFECTIVE_FILE
}

@test "Should return URL when queering Maven plugin" {
    wget -q "https://raw.githubusercontent.com/jenkinsci/maven-plugin/maven-plugin-3.0/pom.xml" -O ${TEMP_FILE}
    run getURL ${TEMP_FILE} ${EFFECTIVE_FILE} "${TEMP_DIR_NEW}" ${OVERRIDE_FILE}
    assert_output "http://github.com/jenkinsci/maven-plugin"
}

@test "Should return overrided_url when quering ANT plugin in an existing override file" {
    wget -q "https://raw.githubusercontent.com/jenkinsci/ant-plugin/ant-1.7/pom.xml" -O ${TEMP_FILE}
    run getURL ${TEMP_FILE} ${EFFECTIVE_FILE} "${TEMP_DIR_NEW}" ${OVERRIDE_FILE}
    assert_output "overrided_url"
}

@test "Should return unreachalbe when quering ace-editor plugin " {
    wget -q "https://raw.githubusercontent.com/jenkinsci/js-libs/master/ace-editor/pom.xml" -O ${TEMP_FILE}
    run getURL ${TEMP_FILE} ${EFFECTIVE_FILE} "${TEMP_DIR_NEW}" ${OVERRIDE_FILE}
    assert_output ${CTE_UNREACHABLE}
}

@test "Should return scm when quering POM without SCM " {
    run getURL ${NO_SCM_POM_FILE} ${EFFECTIVE_FILE} "${TEMP_DIR_NEW}" ${OVERRIDE_FILE}
    assert_output ${CTE_SCM}
}

@test "Should return connection URL when quering POM scm " {
    run getURL ${CONNECTION_POM_FILE} ${EFFECTIVE_FILE} "${TEMP_DIR_NEW}" ${OVERRIDE_FILE}
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
    run buildDependency "${TEMP_DIR_NEW}" "${TEMP_FILE}" "true" "~/.m2/settings.xml" ""
    assert_output "${CTE_PASSED}"
    echo "passed" > "${TEMP_DIR_NEW}/.status.flag"
    run buildDependency "${TEMP_DIR_NEW}" "${TEMP_FILE}" "true" "~/.m2/settings.xml" ""
    assert_output "${CTE_PASSED}"
    echo "failed" > "${TEMP_DIR_NEW}/.status.flag"
    run buildDependency "${TEMP_DIR_NEW}" "${TEMP_FILE}" "true" "~/.m2/settings.xml" ""
    assert_output "${CTE_FAILED}"
}
