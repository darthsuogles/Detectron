#!/bin/bash

set -eu -o pipefail

_bsd_="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function on_error {
    cat <<_DIAGNOSTICS_EOF_
=======================================================
1. Please run ${_bsd_}/prepare_dependencies.sh to make
   sure all the dependencies are compiled.
2. Please prepare model config and trained weights
3. Please make sure datasets are available
=======================================================
_DIAGNOSTICS_EOF_
}

trap on_error ERR

PYTHONPATH="${_bsd_}/.." \
          python "${_bsd_}/infer_simple.py" \
          --cfg models/mask_rcnn_R-50-FPN_2x/model.yaml \
          --wts models/mask_rcnn_R-50-FPN_2x/weights.pkl \
          /mnt/storage/datasets
