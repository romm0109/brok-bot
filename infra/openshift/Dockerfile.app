# App image (api, worker, web) with Node TLS verification off, for networks whose
# certificates cannot be verified. Prefer NODE_EXTRA_CA_CERTS with your CA.
#   docker build -f infra/openshift/Dockerfile.app --build-arg BASE=<mirrored app image> -t <registry>/rakazo/app:tls .
ARG BASE=ghcr.io/elie222/rakazo/app:edge
FROM ${BASE}
ENV NODE_TLS_REJECT_UNAUTHORIZED=0
