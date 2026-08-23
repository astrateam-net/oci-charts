#!/usr/bin/env bash
# Validates every apps/*/metadata.yaml against the rules encoded in
# .vscode/metadata-schema.json. Implemented with yq/jq rather than a schema
# validator so it needs nothing beyond the tools already pinned in .mise.
set -euo pipefail

status=0

fail() {
  echo "::error file=${1}::${2}"
  status=1
}

shopt -s nullglob
files=(apps/*/metadata.yaml)
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "::error::No metadata files found under apps/"
  exit 1
fi

for file in "${files[@]}"; do
  if ! doc=$(yq --output-format=json '.' "$file" 2>/dev/null); then
    fail "$file" "Not valid YAML"
    continue
  fi

  # Top-level keys: exactly artifactName + source.
  unknown=$(jq -r 'keys_unsorted[] | select(. != "artifactName" and . != "source")' <<< "$doc")
  [[ -n "$unknown" ]] && fail "$file" "Unknown top-level key(s): ${unknown//$'\n'/, }"

  artifact=$(jq -r '.artifactName // ""' <<< "$doc")
  [[ -z "$artifact" ]] && fail "$file" "Missing 'artifactName'"
  [[ -n "$artifact" && ! "$artifact" =~ ^[a-z0-9-]+$ ]] &&
    fail "$file" "artifactName '${artifact}' must match ^[a-z0-9-]+$"

  # source must carry exactly one of helm / git.
  kinds=$(jq -r '.source // {} | keys_unsorted[]' <<< "$doc")
  count=$(wc -w <<< "$kinds" | tr -d ' ')
  if [[ "$count" != "1" ]]; then
    fail "$file" "source must define exactly one of: helm, git (found: ${kinds//$'\n'/, })"
    continue
  fi

  case "$kinds" in
    helm)
      for key in registry version; do
        [[ "$(jq -r ".source.helm.${key} // \"\"" <<< "$doc")" == "" ]] &&
          fail "$file" "source.helm.${key} is required"
      done
      registry=$(jq -r '.source.helm.registry // ""' <<< "$doc")
      [[ -n "$registry" && ! "$registry" =~ ^https?:// ]] &&
        fail "$file" "source.helm.registry '${registry}' must be an http(s) URL"
      extra=$(jq -r '.source.helm | keys_unsorted[] | select(. != "registry" and . != "version" and . != "chart" and . != "versionSuffix")' <<< "$doc")
      [[ -n "$extra" ]] && fail "$file" "Unknown source.helm key(s): ${extra//$'\n'/, }"
      ;;
    git)
      for key in repository path tag; do
        [[ "$(jq -r ".source.git.${key} // \"\"" <<< "$doc")" == "" ]] &&
          fail "$file" "source.git.${key} is required"
      done
      extra=$(jq -r '.source.git | keys_unsorted[] | select(. != "repository" and . != "path" and . != "tag" and . != "versionSuffix")' <<< "$doc")
      [[ -n "$extra" ]] && fail "$file" "Unknown source.git key(s): ${extra//$'\n'/, }"
      ;;
    *)
      fail "$file" "source must define exactly one of: helm, git (found: ${kinds})"
      ;;
  esac
done

if [[ $status -eq 0 ]]; then
  echo "All ${#files[@]} metadata files are valid"
fi

exit $status
