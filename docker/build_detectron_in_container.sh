#!/bin/bash

set -eu -o pipefail

declare -xr BASE_DOCKER_IMAGE="nvidia/cuda:9.0-cudnn7-devel-ubuntu16.04"
declare -xr BUILDER_CONTAINER=detectron-builder

docker pull "${BASE_DOCKER_IMAGE}"

nvidia-docker build "$(mktemp -d)" \
	      --build-arg BASE_DOCKER_IMAGE="${BASE_DOCKER_IMAGE}" \
	      -t "${BUILDER_CONTAINER}":base \
	      -f -<<'_DOCKERFILE_EOF_'
ARG BASE_DOCKER_IMAGE
FROM ${BASE_DOCKER_IMAGE} AS BASE_DEPS_LAYER

ARG PYTHON_VERSION=3.7

RUN apt-get update && apt-get install -y --no-install-recommends \
         build-essential \
         cmake \
         git \
         curl \
         ca-certificates \
	 sudo \
         libjpeg-dev \
         libpng12-dev \
	 libglib2.0-0 \
	 &&\
     rm -rf /var/lib/apt/lists/*

FROM BASE_DEPS_LAYER AS CONDA_DEPS_LAYER

RUN curl -o ~/miniconda.sh -O  https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh  && \
     chmod +x ~/miniconda.sh && \
     ~/miniconda.sh -b -p /opt/conda && \
     rm ~/miniconda.sh && \
     /opt/conda/bin/conda install -y python=${PYTHON_VERSION}

RUN /opt/conda/bin/conda install -y \
       numpy \
       pyyaml \
       scipy \
       opencv \
       graphviz \
       mkl \
       mkl-include \
       cython \
       typing

RUN /opt/conda/bin/conda install -y -c pytorch magma-cuda90

RUN /opt/conda/bin/conda install -y -c pytorch pytorch-nightly
    
RUN /opt/conda/bin/conda clean -ya

FROM CONDA_DEPS_LAYER AS BUILDER_LAYER

ENV PATH /opt/conda/bin:$PATH

ENV GOSU_VERSION 1.11
RUN set -eux; \
# save list of currently installed packages for later so we can clean up
	dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	curl -fsSL -o /usr/local/bin/gosu \
	     -O "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
	curl -fsSL -o /usr/local/bin/gosu.asc \
	     -O "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
# verify the signature
	export GNUPGHOME="$(mktemp -d)"; \
# for flaky keyservers, consider https://github.com/tianon/pgp-happy-eyeballs, ala https://github.com/docker-library/php/pull/666
	gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	command -v gpgconf && gpgconf --kill all || :; \
	rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	chmod +x /usr/local/bin/gosu; \
# verify that the binary works
	gosu --version; \
	gosu nobody true

_DOCKERFILE_EOF_

touch ._prepare_and_await.sh && chmod a+x $_

cat <<'_ENTRYPOINT_EOF_' | tee ._prepare_and_await.sh
#!/bin/bash

set -eux -o pipefail

declare -xr CONTAINER_USER_ID
declare -xr CONTAINER_USER_NAME

echo "Starting with UID : ${CONTAINER_USER_ID}"
useradd --shell /bin/bash \
	-u "${CONTAINER_USER_ID}" -o -c "" \
	-m "${CONTAINER_USER_NAME}"

echo "${CONTAINER_USER_NAME}:${CONTAINER_USER_NAME}" | chpasswd
usermod -aG sudo ${CONTAINER_USER_NAME}
mkdir -p /etc/sudoers.d
echo "${CONTAINER_USER_NAME} ALL=(ALL) NOPASSWD: ALL" \
     > "/etc/sudoers.d/${CONTAINER_USER_NAME}"

export HOME=/home/"${CONTAINER_USER_NAME}"
chmod a+w /home/"${CONTAINER_USER_NAME}"
chown "${CONTAINER_USER_NAME}" /home/"${CONTAINER_USER_NAME}"

# exec /usr/local/bin/gosu "${CONTAINER_USER_NAME}" /bin/bash $@
sleep infinity
_ENTRYPOINT_EOF_

repo_root="$(git rev-parse --show-toplevel)"

docker rm -f "${BUILDER_CONTAINER}" &>/dev/null || true

nvidia-docker run -d \
	      --env CONTAINER_USER_NAME=detectron \
	      --env CONTAINER_USER_ID="$(id -u)" \
	      --env PYTHONPATH=/workspace \
	      --volume "${repo_root}":/workspace \
	      --workdir /workspace \
	      --name "${BUILDER_CONTAINER}" \
	      "${BUILDER_CONTAINER}":base \
	      /workspace/._prepare_and_await.sh

cat <<_RUN_BUILD_INST_EOF_
==========================================
Please run your build with this command

docker exec -it ${BUILDER_CONTAINER} /usr/local/bin/gosu detectron bash
==========================================
_RUN_BUILD_INST_EOF_

printf "Wait for a while until things are settled ... "
sleep 7
printf "done.\n"

function docker_exec {
    nvidia-docker exec -it "${BUILDER_CONTAINER}" /usr/local/bin/gosu detectron $@
}

docker_exec pip install --user -U -r requirements.txt
docker_exec python setup.py build_ext --inplace
docker_exec bash
