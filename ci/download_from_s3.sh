#!/bin/bash
# Copies the RAPIDS libraries' HTML files from S3 into the "_site" directory of
# the Jekyll build.
set -euo pipefail

export JEKYLL_DIR="_site"

export GENERATED_DIRS="
libs: ${JEKYLL_DIR}/api
deployment: ${JEKYLL_DIR}/deployment
"
export DOCS_BUCKET="rapidsai-docs"

# Checks that the "_site" directory exists from a Jekyll build. Also ensures
# that the directories that are pulled from S3 aren't already present in the
# "_site" directory since that could cause problems.
check_dirs() {
  local DIR

  if [ ! -d "${JEKYLL_DIR}" ]; then
    echo "\"${JEKYLL_DIR}\" directory does not exist."
    echo "Build Jekyll site first."
    exit 1
  fi


  for DIR in $(yq -n 'env(GENERATED_DIRS) | .[]'); do
    if [ -d "${DIR}" ]; then
      echo "The \"${DIR}\" directory is populated at deploy time and should not already exist."
      echo "Ensure the \"${DIR}\" directory is not generated by Jekyll."
      exit 1
    fi
  done
}

# Helper function for the `aws cp` command. Checks to ensure that the source
# directory has contents before attempting the copy.
aws_cp() {
  local SRC DST

  SRC=$1
  DST=$2

  if ! aws s3 ls "${SRC}" > /dev/null; then
    echo "No files found in ${SRC}. Exiting."
    exit 1
  fi

  echo "Copying ${SRC} to ${DST}"
  aws s3 cp \
    --only-show-errors \
    --recursive \
    "${SRC}" \
    "${DST}"
}

# Downloads the RAPIDS libraries' documentation files from S3 and places them
# into the "_site/api" folder. The versions that should be copied are read from
# "_data/releases.json" and the libraries that should be copied are read from
# "_data/docs.yml".
download_lib_docs() {
  local DST PROJECT PROJECT_MAP \
        SRC VERSION_MAP VERSION_NAME \
        VERSION_NUMBER

  VERSION_MAP=$(
    jq '{
      "legacy": .legacy.version,
      "stable": .stable.version,
      "nightly": .nightly.version
    }' _data/releases.json
  )
  export VERSION_MAP

  PROJECT_MAP=$(yq '.apis + .libs' _data/docs.yml)
  export PROJECT_MAP


  for VERSION_NAME in $(jq -nr 'env.VERSION_MAP | fromjson | keys | .[]'); do
    for PROJECT in $(yq -n 'env(PROJECT_MAP) | keys | .[]'); do
      export VERSION_NAME PROJECT
      VERSION_NUMBER=$(jq -nr 'env.VERSION_MAP | fromjson | .[env.VERSION_NAME]')

      if yq -en 'env(PROJECT_MAP) | .[strenv(PROJECT)].versions.[strenv(VERSION_NAME)] == 0' > /dev/null 2>&1; then
        echo "skipping: $PROJECT | $VERSION_NAME | $VERSION_NUMBER"
        continue
      fi

      SRC="s3://${DOCS_BUCKET}/${PROJECT}/html/${VERSION_NUMBER}/"
      DST="$(yq -n 'env(GENERATED_DIRS)|.libs')/${PROJECT}/${VERSION_NUMBER}/"

      aws_cp "${SRC}" "${DST}"
    done
  done
}

# Downloads the deployment docs from S3 and places them in the
# "_site/deployment" directory.
download_deployment_docs() {
  local DST SRC VERSION

  for VERSION in nightly stable; do
    SRC="s3://${DOCS_BUCKET}/deployment/html/${VERSION}/"
    DST="$(yq -n 'env(GENERATED_DIRS)|.deployment')/${VERSION}/"

    aws_cp "${SRC}" "${DST}"
  done
}

check_dirs
download_lib_docs
download_deployment_docs
