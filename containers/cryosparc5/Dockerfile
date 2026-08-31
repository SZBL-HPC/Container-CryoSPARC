# Build with the repository root as the Docker context.
# The installer stage does not require a GPU. Pass
# CRYOSPARC_WORKER_NOGPU=false only when the build environment has a usable GPU.

ARG CUDA_IMAGE=nvidia/cuda:12.8.2-base-ubuntu24.04
ARG CRYOSPARC_CLUSTER_HOSTS="12.12.4.3 login03 login03.szbl.hpc etcd_node"
ARG CRYOSPARC_INCLUDE_WORKER=true

FROM --platform=linux/amd64 ${CUDA_IMAGE} AS runtime-base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        aria2 \
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
    && mkdir -p /etc/ssh/sshd_config.d /run/sshd /root/.ssh \
    && ssh-keygen -A \
    && rm -rf /var/lib/apt/lists/*

COPY containers/cryosparc5/sshd_config /etc/ssh/sshd_config.d/10-cryosparc.conf

FROM runtime-base AS installer-base

ENV CRYOSPARC_FORCE_HOSTNAME=true

# Podman automatically unpacks local archives; its Dockerfile parser does not
# support the explicit --unpack=true option.
ADD pkg/cryosparc_master.tar.gz /opt/cryosparc/

# Optional package stages are selected by boolean build args. Unselected stages
# are not evaluated, so missing worker or patch archives are valid.
FROM installer-base AS installer-worker-true

ADD pkg/cryosparc_worker.tar.gz /opt/cryosparc/

FROM installer-base AS installer-worker-false

FROM installer-worker-${CRYOSPARC_INCLUDE_WORKER} AS installer

ARG CRYOSPARC_BUILD_LICENSE_ID=00000000-0000-0000-0000-000000000000
ARG CRYOSPARC_WORKER_NOGPU=true

# Keep optional patch packages while excluding the large base packages and
# backup directories under pkg/.
COPY --exclude='pkg/*/**' \
    --exclude=cryosparc_master.tar.gz \
    --exclude=cryosparc_worker.tar.gz \
    pkg/ /build/pkg/

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

RUN if [[ -f /opt/cryosparc/cryosparc_worker/install.sh ]]; then \
        worker_args=() \
        && if [[ "${CRYOSPARC_WORKER_NOGPU}" == "true" ]]; then worker_args+=(--nogpu); fi \
        && cd /opt/cryosparc/cryosparc_worker \
        && ./install.sh \
            --license "${CRYOSPARC_BUILD_LICENSE_ID}" \
            --yes \
            "${worker_args[@]}"; \
    fi

RUN if [[ -f /build/pkg/cryosparc_master_patch.tar.gz ]]; then \
        cp /build/pkg/cryosparc_master_patch.tar.gz /opt/cryosparc/cryosparc_master/; \
    fi \
    && if [[ -f /build/pkg/cryosparc_worker_patch.tar.gz ]]; then \
        cp /build/pkg/cryosparc_worker_patch.tar.gz /opt/cryosparc/cryosparc_worker/; \
    fi

RUN export PATH=/opt/cryosparc/cryosparc_master/bin:/opt/cryosparc/cryosparc_worker/bin:$PATH \
    && cd /opt/cryosparc/cryosparc_master \
    && ./bin/cryosparcm start \
    && if [[ -f /opt/cryosparc/cryosparc_master/cryosparc_master_patch.tar.gz ]]; then \
        ./bin/cryosparcm patch --install --yes; \
    fi \
    && if [[ -f /opt/cryosparc/cryosparc_worker/cryosparc_worker_patch.tar.gz ]]; then \
        cd /opt/cryosparc/cryosparc_worker \
        && ./bin/cryosparcw patch; \
    fi \
    && cd /opt/cryosparc/cryosparc_master \
    && ./bin/cryosparcm stop

RUN rm -f \
        /opt/cryosparc/cryosparc_master/cryosparc_master_patch.tar.gz \
        /opt/cryosparc/cryosparc_worker/cryosparc_worker_patch.tar.gz \
    && rm -rf \
        /opt/cryosparc/cryosparc_master/run \
        /opt/cryosparc/cryosparc_worker/run \
        /opt/cryosparc/initial \
        /build/pkg

RUN chmod -R a+rwX /opt/cryosparc

FROM runtime-base AS master0

COPY --from=installer /opt/cryosparc/cryosparc_master /opt/cryosparc/cryosparc_master

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    CRYOSPARC_INSTALL_ROOT=/opt/cryosparc \
    CRYOSPARC_BASE_PORT=61000 \
    CRYOSPARC_SUPERVISOR_PID_FILE=/var/run/cryosparc-supervisord.pid

COPY --chmod=755 containers/cryosparc5/cryosparc /usr/local/bin/cryosparc
COPY --chmod=755 containers/cryosparc5/entrypoint /usr/local/bin/cryosparc-container
COPY --chmod=755 containers/cryosparc5/cryosparcm /usr/local/bin/cryosparcm
COPY --chmod=755 containers/cryosparc5/cryosparc-download-data /usr/local/bin/cryosparc-download-data

ARG CRYOSPARC_CLUSTER_HOSTS
RUN if [[ -n "${CRYOSPARC_CLUSTER_HOSTS}" ]] && ! grep -Fqx -- "${CRYOSPARC_CLUSTER_HOSTS}" /etc/hosts; then \
        printf '%s\n' "${CRYOSPARC_CLUSTER_HOSTS}" >> /etc/hosts; \
    fi \
    && sed -i \
        's#^pidfile=%(ENV_CRYOSPARC_LOG_DIR)s/supervisord.pid$#pidfile=%(ENV_CRYOSPARC_SUPERVISOR_PID_FILE)s#' \
        /opt/cryosparc/cryosparc_master/config/supervisord.conf \
    && mkdir -p /var/run \
    && chmod 777 /var/run \
    && mkdir -p /ssd \
    && chmod 777 /ssd

EXPOSE 22 61000 61001 61002 61003 61004 61005 61006

ENTRYPOINT ["/usr/local/bin/cryosparc-container"]

FROM master0 AS master

COPY --chmod=644 containers/cryosparc5/cluster_info.json /opt/cryosparc/cryosparc_master/bin/cluster_info.json
COPY --chmod=644 containers/cryosparc5/cluster_script.sh /opt/cryosparc/cryosparc_master/bin/cluster_script.sh

FROM master0 AS workstation

COPY --from=installer /opt/cryosparc/cryosparc_worker /opt/cryosparc/cryosparc_worker
COPY --chmod=755 containers/cryosparc5/cryosparcw /usr/local/bin/cryosparcw

FROM workstation AS hybrid

COPY --chmod=644 containers/cryosparc5/cluster_info.json /opt/cryosparc/cryosparc_master/bin/cluster_info.json
COPY --chmod=644 containers/cryosparc5/cluster_script.sh /opt/cryosparc/cryosparc_master/bin/cluster_script.sh
