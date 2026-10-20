# ---------- Stage 1: build ----------
# Node image with npm, used to install packages and run "ng build"
FROM node:24-alpine AS build
WORKDIR /app

# Copy only package files first and install packages.
# Docker caches this step, so npm install re-runs only when package*.json changes.
COPY package.json package-lock.json ./
RUN npm ci

# Copy the rest of the source code and build the app into /app/dist
COPY . .
RUN npm run build

# ---------- Stage 2: run ----------
FROM node:24-alpine
WORKDIR /app

# The SSR server (dist/.../server/server.mjs) needs the built app and its runtime packages
COPY --from=build /app/package.json /app/package-lock.json ./
RUN npm ci --omit=dev
COPY --from=build /app/dist ./dist

# The Angular SSR server listens on PORT (default 4000)
ENV PORT=4000
EXPOSE 4000
CMD ["node", "dist/English_FrontEnd/server/server.mjs"]
