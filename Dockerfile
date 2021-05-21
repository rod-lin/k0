ARG k_git=https://github.com/kframework/k.git
ARG k_version=master
ARG jdk_build=https://download.java.net/java/GA/jdk15.0.2/0d1cfde4252546c6931946de8db48ee2/7/GPL/openjdk-15.0.2_linux-x64_bin.tar.gz

###########################
# Base image for building #
###########################

FROM ubuntu:20.04 AS base

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y \
        build-essential m4 libgmp-dev libmpfr-dev \
        pkg-config flex bison z3 libz3-dev maven \
        python3 cmake gcc clang-8 lld-8 llvm-8-tools \
        zlib1g-dev libboost-test-dev libyaml-dev \
        libjemalloc-dev wget git curl

# install a custom version of openjdk
ARG jdk_build
RUN mkdir jdk-install && \
    cd jdk-install && \
    wget -q --show-progress $jdk_build && \
    tar xf *.tar.* && \
    mv jdk-* /opt/jdk && \
    cd .. && \
    rm -r jdk-install
ENV PATH="/opt/jdk/bin:${PATH}"

# install haskell
RUN curl -sSL https://get.haskellstack.org/ | sh

#####################
# Build K framework #
#####################

FROM base AS build

# clone the K repo
ARG k_git
ARG k_version
RUN git clone --depth 1 --branch $k_version $k_git k && \
    cd k && \
    git submodule update --depth 1 --init --recursive

# build k
RUN cd k && mvn -T 1C package -DskipTests

# strip symbols not used for relocation
RUN cd /k/k-distribution/target/release/k && \
    strip --strip-unneeded bin/* $(find lib/kllvm -name "*") | exit 0

# remove some less used binaries
RUN cd /k/k-distribution/target/release/k/bin/ && \
    rm -f kore-format kore-prof kore-repl

# pack a custom jvm with only the components we need
RUN deps=$(jdeps --ignore-missing-deps --print-module-deps k/k-distribution/target/release/k/lib/kframework/java/*.jar) && \
    jlink --output /jre \
          --strip-debug \
          --no-header-files \
          --no-man-pages \
          --compress=2 \
          --add-modules $deps

###################################################
# Pack final image with only runtime dependencies #
###################################################

FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        libc-dev flex bison z3 libjemalloc-dev \
        libgmp-dev libmpfr-dev libyaml-0-2 \
        llvm-8 clang-8 lld-8 libtinfo-dev libffi-dev && \
    rm -rf /var/lib/apt/lists/* && \
    ln -s /usr/bin/clang-8 /usr/bin/gcc

COPY --from=build /jre /opt/jre
COPY --from=build /k/k-distribution/target/release/k/bin /opt/k/bin
COPY --from=build /k/k-distribution/target/release/k/lib /opt/k/lib
COPY --from=build /k/k-distribution/target/release/k/include /opt/k/include

ENV PATH="/opt/k/bin:/opt/jre/bin:${PATH}"
