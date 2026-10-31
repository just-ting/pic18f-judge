FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
USER root
ENV USER=root HOME=/root

# install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip make gcc g++ unzip \
    libxext6 libxrender1 libxtst6 libxi6 libusb-1.0-0 \
    default-jre-headless \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
# install 32bit libraries for mplabx v5.x
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    libc6:i386 libstdc++6:i386 libgcc-s1:i386 \
    libexpat1:i386 \
    libx11-6:i386 libxext6:i386 zlib1g:i386 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# install mplabx
COPY install/MPLABX-*.sh /tmp/
RUN chmod +x /tmp/MPLABX-*.sh && /tmp/MPLABX-*sh -- --mode unattended --unattendedmodeui none --installdir /opt/microchip/mplabx

# install xc8
COPY install/xc8-*.run /tmp/
RUN chmod +x /tmp/xc8-*.run && /tmp/xc8-*.run --mode unattended --unattendedmodeui none --installdir /opt/microchip/xc8 --LicenseType FreeMode --netservername localhost

# install PIC18Fxxxx packs
COPY packs/*.atpack /tmp/PIC18F_xxxx_packs/
RUN unzip -q /tmp/PIC18F_xxxx_packs/*.atpack -d /tmp/PIC18F_xxxx_packs \
 && cp -a /tmp/PIC18F_xxxx_packs/xc8/pic/* /opt/microchip/xc8/pic/ \
 && rm -rf /tmp/PIC18F_xxxx_packs

# set environment variables: mpasmx, xc8-cc, mdb.sh
ENV PATH="/opt/microchip/mplabx/mpasmx:/opt/microchip/xc8/pic/bin:/opt/microchip/xc8/v3.10/bin:/opt/microchip/mplabx/mplab_platform/bin:${PATH}"
# symlink xc8 compiler driver to /usr/local/bin
RUN ln -s /opt/microchip/xc8/pic/bin/driver18 /usr/local/bin/xc8-cc \
 && ln -s /opt/microchip/xc8/pic/bin/driver /usr/local/bin/xc8

WORKDIR /workspace
COPY judge/ /workspace/judge

ENTRYPOINT ["/bin/bash"]
