# Build from repo root: docker build -f server/Dockerfile .
FROM node:22-alpine AS build
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
WORKDIR /app
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY server/package.json server/
COPY packages/shared-rules/package.json packages/shared-rules/
RUN pnpm install --frozen-lockfile
COPY packages/shared-rules packages/shared-rules
COPY server server
RUN pnpm -C server build

FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /app/node_modules node_modules
COPY --from=build /app/server/node_modules server/node_modules
COPY --from=build /app/server/dist server/dist
COPY --from=build /app/server/package.json server/package.json
COPY --from=build /app/server/drizzle server/drizzle
EXPOSE 8080
CMD ["node", "server/dist/server/src/index.js"]
