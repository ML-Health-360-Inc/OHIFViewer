# Appliance OHIF image: static webpack build + nginx.
# Context must be the repo root.
#
# Two stages:
# 1. Build @ohif/app with PUBLIC_URL=/ohif/
# 2. Serve dist from nginx-unprivileged

FROM node:18.16.1-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends build-essential python3 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

COPY package.json yarn.lock preinstall.js ./
COPY extensions ./extensions
COPY modes ./modes
COPY platform ./platform
# Remaining configs / .docker / root tooling (.dockerignore excludes docs/cli).
COPY . .

# Skip Docusaurus docs + CLI (large, unused). Icons need file-loader, which the
# monorepo previously only pulled in via platform/docs — add it explicitly.
RUN rm -rf ./platform/docs ./platform/cli \
  && yarn config set workspaces-experimental true \
  && yarn install --frozen-lockfile --non-interactive --network-timeout 600000 \
  && yarn add file-loader@6.2.0 -W -D --non-interactive --network-timeout 600000

ENV PATH=/usr/src/app/node_modules/.bin:$PATH
ENV QUICK_BUILD=true
ARG PUBLIC_URL=/ohif/
ENV PUBLIC_URL=${PUBLIC_URL}

RUN yarn run build

FROM nginxinc/nginx-unprivileged:1.25-alpine AS final

ENV PORT=80
RUN rm /etc/nginx/conf.d/default.conf
USER nginx
COPY --chown=nginx:nginx .docker/Viewer-v3.x /usr/src
RUN chmod 777 /usr/src/entrypoint.sh
COPY --from=builder /usr/src/app/platform/app/dist /usr/share/nginx/html
USER root
RUN chmod 666 /usr/share/nginx/html/app-config.js
USER nginx
ENTRYPOINT ["/usr/src/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
