#!/bin/sh
# shellcheck disable=SC1117

set -eu

upload_new_docker_image()
{
  if [ -n "${CHANGES}" ]; then
    echo "The following Docker-related files have changed:"
    echo "${CHANGES}"
    docker build --rm -t "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}" .
    if ! docker run --rm --privileged -e "ARM_EMU_BIN=${ARM_EMU_BIN}" -v "${ARM_EMU_BIN}:${ARM_EMU_BIN}:ro" "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}" "/test/buildenv_check.sh"; then
      echo "Something is wrong with the build environment, please check your Dockerfile."
      exit 1
    fi
    if [ "${CI_COMMIT_REF_NAME}" = "master" ] || [ "${CI_COMMIT_REF_NAME}" = "master-next_som" ]; then
      echo "Uploading new Docker image to the Gitlab registry"
      docker login -u gitlab-ci-token -p "${CI_JOB_TOKEN}" "${CI_REGISTRY}"
      docker tag  "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}" "${CI_REGISTRY_IMAGE}:latest"
      docker push "${CI_REGISTRY_IMAGE}:latest"
    fi
    exit 0
  fi
}

if [ "${CI_COMMIT_REF_NAME}" = "master" ]; then
  echo "Running on 'master' branch, comparing against previous commit..."
  CHANGES=$(git log --name-only --pretty="" origin/master...HEAD~ -- | grep "Dockerfile\|.dockerignore\|docker_env" | sort -u)
  upload_new_docker_image
elif [ "${CI_COMMIT_REF_NAME}" = "master-next_som" ]; then
  echo "Running on 'master-next_som' branch, comparing against previous commit..."
  CHANGES=$(git log --name-only --pretty="" origin/master-next_som...HEAD~ -- | grep "Dockerfile\|.dockerignore\|docker_env" | sort -u)
  upload_new_docker_image
else
  echo "NOT running on 'master' or 'master-next_som' branch, comparing against 'master' and 'master-next_som'"
  CHANGES=$(git log --name-only --pretty="" origin/master...HEAD -- | grep "Dockerfile\|.dockerignore\|docker_env" | sort -u)
  upload_new_docker_image
  CHANGES=$(git log --name-only --pretty="" origin/master-next_som...HEAD -- | grep "Dockerfile\|.dockerignore\|docker_env" | sort -u)
  upload_new_docker_image
fi

echo "No Dockerfile changes..."
docker tag "${CI_REGISTRY_IMAGE}:latest" "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}"

exit 0
