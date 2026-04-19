# angzarr-project: docs site (Astro/Starlight) + proto definitions + features

SITE := "site-next"

# Run dev server for the docs site
dev:
    cd {{SITE}} && npm run dev

# Build the docs site to site-next/dist
build:
    cd {{SITE}} && npm run build

# Preview the built site locally
preview:
    cd {{SITE}} && npm run preview

# Install site dependencies
install:
    cd {{SITE}} && npm install

# Vendor sibling repos used by remark-code-region (Python only for now)
vendor:
    mkdir -p vendor/examples vendor/client
    [ -d vendor/examples/python ] || git clone --depth=1 git@github.com:angzarr-io/angzarr-examples-python.git vendor/examples/python
    [ -d vendor/client/python ]   || git clone --depth=1 git@github.com:angzarr-io/angzarr-client-python.git   vendor/client/python

# Clean build artifacts
clean:
    rm -rf {{SITE}}/dist {{SITE}}/.astro
