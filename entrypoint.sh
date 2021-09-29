#!/bin/bash -eu

SRC=/python
DIST=/dist/layer.zip

pip3 install -t ${SRC} $@
rm -f ${DIST}
zip -q -r ${DIST} ${SRC}