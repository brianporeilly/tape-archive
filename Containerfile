ARG FEDORA_VERSION=44

FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION} AS build

# Reference LTFS release to build (tag, branch, or commit)
ARG LTFS_REF=v2.4.9.0-10523

# LTFS build prerequisites
RUN dnf install -y \
    fuse-devel \
    libxml2-devel \
    e2fsprogs-devel \
    glib2-devel \
    icu libicu-devel \
    libuuid-devel \
    net-snmp-devel \
    git \
    automake \
    autoconf \
    libtool \
    make \
    gcc \
    gcc-c++ \
    && dnf clean all

# Clone and compile reference LTFS
RUN git init -q /src/ltfs \
    && cd /src/ltfs \
    && git fetch -q --depth 1 https://github.com/LinearTapeFileSystem/ltfs.git "$LTFS_REF" \
    && git checkout -q FETCH_HEAD \
    && git submodule update --init --recursive --depth 1 \
    && ./autogen.sh \
    && ./configure CFLAGS="-g -O2 -Wno-error=declaration-after-statement" \
    && make -j"$(nproc)" \
    && make install


FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION}

# LTFS runtime libraries, plus runtime tools used by tapectl
RUN dnf install -y \
    fuse \
    fuse-libs \
    libxml2 \
    libicu \
    libuuid \
    net-snmp-libs \
    net-snmp-agent-libs \
    rsync \
    util-linux \
    procps-ng \
    && dnf clean all

COPY --from=build /usr/local/ /usr/local/

# Make sure libltfs and the tape/iosched plugins are found, and fail the build
# if any of their shared-library dependencies is missing from this stage
RUN echo /usr/local/lib > /etc/ld.so.conf.d/ltfs.conf && ldconfig \
    && ! ldd /usr/local/bin/ltfs /usr/local/bin/mkltfs /usr/local/lib/ltfs/*.so | grep 'not found' \
    && mkdir -p /mnt/tape /source

COPY --chmod=0755 tapectl /usr/local/bin/tapectl

ENV TAPE_DEVICE=/dev/sg1 TAPE_MOUNT=/mnt/tape TAPE_SOURCE=/source \
    LTFS_BIN=ltfs MKLTFS_BIN=mkltfs

ENTRYPOINT ["/usr/local/bin/tapectl"]
CMD ["help"]
