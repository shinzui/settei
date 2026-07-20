#!/usr/bin/env bash
# Client-side validation of the deploy manifests. No cluster is contacted.
set -euo pipefail
cd "$(dirname "$0")"

fail=0
expect() { # expect <label> <needle>; reads the current value of $render
  if grep -qF -- "$2" <<<"$render"; then
    echo "ok:   $1"
  else
    echo "FAIL: $1 (missing: $2)"
    fail=1
  fi
}

for overlay in dev test production; do
  echo "== overlay: ${overlay}"
  render="$(kubectl kustomize "overlays/${overlay}")"
  expect "namespace stamped" "namespace: ${overlay}"
  expect "downward API namespace" "fieldPath: metadata.namespace"
  expect "secret-backed password" "name: settei-example-service-database"
  expect "mounted Secret option" "--secrets-dir"
  expect "mounted Secret path" "mountPath: /etc/settei/secrets"
  expect "check-config gate" "--check-config"
  expect "no real secret committed" "PLACEHOLDER-REPLACE-VIA-YOUR-SECRET-PIPELINE"
done

render="$(kubectl kustomize overlays/dev)"
expect "dev environment value" "HASKELL_ENV: development"
expect "dev database host" "postgres.dev.internal"
render="$(kubectl kustomize overlays/test)"
expect "test environment value" "HASKELL_ENV: test"
expect "test database host" "postgres.test.internal"
render="$(kubectl kustomize overlays/production)"
expect "production environment value" "HASKELL_ENV: production"
expect "production database host" "postgres.production.internal"

if [[ "${SETTEI_VALIDATE_SCHEMAS:-0}" == "1" ]]; then
  for overlay in dev test production; do
    kubectl kustomize "overlays/${overlay}" | kubeconform -strict -summary || fail=1
  done
else
  echo "note: schema validation skipped; set SETTEI_VALIDATE_SCHEMAS=1 to run kubeconform"
fi

exit "$fail"
