# Build with the repository root as the Docker context.
# The installer stage does not require a GPU. Pass
# CRYOSPARC_WORKER_NOGPU=false only when the build environment has a usable GPU.

ARG CUDA_IMAGE=nvidia/cuda:12.8.2-base-ubuntu24.04

FROM ubuntu:24.04 AS package-unpack

WORKDIR /build

COPY pkg/cryosparc_master.tar.gz /build/pkg/cryosparc_master.tar.gz
COPY pkg/cryosparc_master_patch.tar.gz /build/pkg/cryosparc_master_patch.tar.gz
COPY pkg/cryosparc_worker.tar.gz /build/pkg/cryosparc_worker.tar.gz
COPY pkg/cryosparc_worker_patch.tar.gz /build/pkg/cryosparc_worker_patch.tar.gz

RUN mkdir -p \
        /opt/cryosparc/cryosparc_master \
        /opt/cryosparc/cryosparc_worker \
        /opt/cryosparc/initial \
    && tar -xzf /build/pkg/cryosparc_master.tar.gz \
        --strip-components=1 \
        --directory /opt/cryosparc/cryosparc_master \
    && tar -xzf /build/pkg/cryosparc_worker.tar.gz \
        --strip-components=1 \
        --directory /opt/cryosparc/cryosparc_worker

FROM ${CUDA_IMAGE} AS runtime-base

ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        iproute2 \
        libglib2.0-0 \
        libgomp1 \
        libsm6 \
        libx11-6 \
        libxext6 \
        libxrender1 \
        locales \
        openssh-client \
        openssh-server \
        passwd \
        procps \
        sudo \
    && sed -i \
        -e 's/^# *C.UTF-8 UTF-8/C.UTF-8 UTF-8/' \
        -e 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' \
        /etc/locale.gen \
    && locale-gen C.UTF-8 en_US.UTF-8 \
    && mkdir -p /run/sshd /root/.ssh \
    && ssh-keygen -A \
    && sed -i \
        -e 's/^#PermitRootLogin.*/PermitRootLogin prohibit-password/' \
        -e 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/' \
        -e 's/^#PasswordAuthentication.*/PasswordAuthentication no/' \
        -e 's/^PasswordAuthentication.*/PasswordAuthentication no/' \
        -e 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/' \
        -e 's/^PubkeyAuthentication.*/PubkeyAuthentication yes/' \
        /etc/ssh/sshd_config \
    && rm -rf /var/lib/apt/lists/*

FROM runtime-base AS installer

ARG CRYOSPARC_BUILD_LICENSE_ID=00000000-0000-0000-0000-000000000000
ARG CRYOSPARC_INITIAL_EMAIL=admin@example.org
ARG CRYOSPARC_INITIAL_USERNAME=admin
ARG CRYOSPARC_INITIAL_FIRSTNAME=Cryo
ARG CRYOSPARC_INITIAL_LASTNAME=SPARC
ARG CRYOSPARC_INITIAL_PASSWORD=Passw0rd
ARG CRYOSPARC_WORKER_NOGPU=true

ENV CRYOSPARC_FORCE_HOSTNAME=true

COPY --from=package-unpack /opt/cryosparc /opt/cryosparc
COPY --from=package-unpack /build/pkg /build/pkg

RUN test -n "${CRYOSPARC_INITIAL_PASSWORD}"

# The bundled installer probes the license server for patches. The patch files
# are supplied locally, so skip that network-only probe and install them below.
RUN sed -i '/^check_and_offer_patch_install$/d' \
    /opt/cryosparc/cryosparc_master/install/install_master.sh

RUN cd /opt/cryosparc/cryosparc_master \
    && ./install.sh \
        --license "${CRYOSPARC_BUILD_LICENSE_ID}" \
        --hostname localhost \
        --port 61000 \
        --dbpath /opt/cryosparc/initial/cryosparc_database \
        --allowroot \
        --yes \
        --ignore-port-conflicts

RUN worker_args=() \
    && if [[ "${CRYOSPARC_WORKER_NOGPU}" == "true" ]]; then worker_args+=(--nogpu); fi \
    && cd /opt/cryosparc/cryosparc_worker \
    && ./install.sh \
        --license "${CRYOSPARC_BUILD_LICENSE_ID}" \
        --yes \
        "${worker_args[@]}"

RUN cp /build/pkg/cryosparc_master_patch.tar.gz /opt/cryosparc/cryosparc_master/ \
    && cp /build/pkg/cryosparc_worker_patch.tar.gz /opt/cryosparc/cryosparc_worker/ \
    && export PATH=/opt/cryosparc/cryosparc_master/bin:/opt/cryosparc/cryosparc_worker/bin:$PATH \
    && cd /opt/cryosparc/cryosparc_master \
    && ./bin/cryosparcm start \
    && ./bin/cryosparcm user create \
        --email "${CRYOSPARC_INITIAL_EMAIL}" \
        --password "${CRYOSPARC_INITIAL_PASSWORD}" \
        --username "${CRYOSPARC_INITIAL_USERNAME}" \
        --firstname "${CRYOSPARC_INITIAL_FIRSTNAME}" \
        --lastname "${CRYOSPARC_INITIAL_LASTNAME}" \
    && ./bin/cryosparcm patch --install --yes \
    && cd /opt/cryosparc/cryosparc_worker \
    && ./bin/cryosparcw patch \
    && cd /opt/cryosparc/cryosparc_master \
    && ./bin/cryosparcm stop \
    && chmod -R u+rwX,go+rX /opt/cryosparc/initial/cryosparc_database \
    && rm -f \
        /opt/cryosparc/cryosparc_master/cryosparc_master_patch.tar.gz \
        /opt/cryosparc/cryosparc_worker/cryosparc_worker_patch.tar.gz \
    && rm -rf \
        /opt/cryosparc/cryosparc_master/run \
        /opt/cryosparc/cryosparc_worker/run \
        /build/pkg

FROM runtime-base AS workstation

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    CRYOSPARC_INSTALL_ROOT=/opt/cryosparc \
    CRYOSPARC_BASE_PORT=61000

COPY --from=installer /opt/cryosparc /opt/cryosparc
COPY containers/workstation/run.sh /usr/local/bin/cryosparc-workstation

RUN chmod 755 /usr/local/bin/cryosparc-workstation

EXPOSE 22 61000

ENTRYPOINT ["/usr/local/bin/cryosparc-workstation"]
