FROM maven:3.5-jdk-8-alpine

RUN apk add --no-cache git wget
RUN git clone https://github.com/bats-core/bats-core.git
RUN cd bats-core ; ./install.sh /usr/local
