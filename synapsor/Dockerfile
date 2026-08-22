FROM node:22-bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client \
    && rm -rf /var/lib/apt/lists/*

RUN npm install --global \
    @synapsor/runner@1.7.11 \
    @synapsor/spec@1.10.0 \
    @synapsor/dsl@1.10.0 \
    && npm cache clean --force

USER node
