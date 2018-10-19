#!/bin/bash

set -eu -o pipefail

_bsd_="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PATH="${HOME}/miniconda3/bin:${PATH}"

conda create -y -n pytorch python=3.6 || true
source activate pytorch

conda install -y graphviz
conda install -y -c pytorch pytorch-nightly

pushd "${_bsd_}/.."
pip install -U -r requirements.txt
# Build cython files
python setup.py build_ext --inplace
popd
