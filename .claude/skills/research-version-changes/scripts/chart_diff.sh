#!/usr/bin/env bash
# Pull a Helm chart at two versions and write the deterministic comparisons into one
# directory: Chart.yaml facts, values.yaml and values.schema.json diffs with comments
# intact, a CRD inventory with per-CRD change flags, the chart README's upgrade
# sections, and normalized render diffs (chart defaults, and optionally supplied values).
#
# Usage:
#   chart_diff.sh --repo <https-url|oci://ref> [--chart <name>] --from <ver> --to <ver> \
#                 --out <dir> [--values <file>]... [--envsubst] [--api-versions <group/version>]... \
#                 [--kube-version <ver>] [--namespace <ns>]
#
# --repo is the HelmRepository URL (then --chart is required) or the full OCI chart ref
# as an OCIRepository spells it. --envsubst passes each values file through
# `flux envsubst` first, so Flux post-build placeholders resolve (unset ones become empty,
# so export them to supply values). --api-versions declares cluster capabilities that a
# chart checks for, e.g. monitoring.coreos.com/v1. Needs helm, yq (mikefarah v4), diff, and flux for --envsubst.
#
# Exit codes are 0 done, 2 bad input, 3 pull failed. Render failures are recorded rather
# than fatal, because a render that fails on the new version with our values is a finding.
set -euo pipefail

repo="" chart="" from="" to="" out="" kube_version="" namespace="default" envsubst=0
values=() api_versions=()
while (($#)); do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --chart) chart="$2"; shift 2 ;;
    --from) from="$2"; shift 2 ;;
    --to) to="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --values) values+=("$2"); shift 2 ;;
    --kube-version) kube_version="$2"; shift 2 ;;
    --namespace) namespace="$2"; shift 2 ;;
    --envsubst) envsubst=1; shift ;;
    --api-versions) api_versions+=(--api-versions "$2"); shift 2 ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "ERROR unknown argument $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$repo" || -z "$from" || -z "$to" || -z "$out" ]] || [[ "$repo" != oci://* && -z "$chart" ]]; then
  echo "ERROR --repo, --from, --to, --out are required, and --chart unless --repo is oci://" >&2
  exit 2
fi
for f in "${values[@]}"; do [[ -r "$f" ]] || { echo "ERROR cannot read values file $f" >&2; exit 2; }; done
for tool in helm yq diff; do command -v "$tool" >/dev/null || { echo "ERROR $tool not found" >&2; exit 2; }; done

mkdir -p "$out"
out="$(cd "$out" && pwd)"
rm -rf "${out:?}/from" "${out:?}/to" "${out:?}/render" "${out:?}/crds"
mkdir -p "$out/render" "$out/crds/from" "$out/crds/to"

pull() {
  local side="$1" version="$2" dest="$out/$1"
  mkdir -p "$dest"
  if [[ "$repo" == oci://* ]]; then
    helm pull "$repo" --version "$version" --untar --untardir "$dest" >/dev/null 2>"$out/pull-$side.err"
  else
    helm pull "$chart" --repo "$repo" --version "$version" --untar --untardir "$dest" >/dev/null 2>"$out/pull-$side.err"
  fi || { echo "ERROR helm pull $side $version failed: $(cat "$out/pull-$side.err")" >&2; exit 3; }
  rm -f "$out/pull-$side.err"
  find "$dest" -mindepth 1 -maxdepth 1 -type d | head -n 1
}
from_dir="$(pull from "$from")"
to_dir="$(pull to "$to")"

udiff() { diff -u --label "from/$3" --label "to/$3" "$1" "$2" >"$out/$4" || true; }
lines() { if [[ -s "$1" ]]; then wc -l <"$1" | tr -d ' '; else echo 0; fi; }

# ---- Chart.yaml facts
chart_facts='{"version": .version, "appVersion": .appVersion, "kubeVersion": .kubeVersion,
  "dependencies": [(.dependencies // [])[] | .name + " " + .version + " " + (.repository // "") + " " + (.condition // "")],
  "sources": (.sources // []), "home": .home,
  "artifacthub_changes": (.annotations["artifacthub.io/changes"] // "")}'
yq -o json "$chart_facts" "$from_dir/Chart.yaml" >"$out/chart-from.json"
yq -o json "$chart_facts" "$to_dir/Chart.yaml" >"$out/chart-to.json"
udiff "$from_dir/Chart.yaml" "$to_dir/Chart.yaml" Chart.yaml chart-yaml.diff

# ---- values surface, comments intact
udiff "$from_dir/values.yaml" "$to_dir/values.yaml" values.yaml values.diff
if [[ -f "$from_dir/values.schema.json" || -f "$to_dir/values.schema.json" ]]; then
  schema_from="$from_dir/values.schema.json" schema_to="$to_dir/values.schema.json"
  [[ -f "$schema_from" ]] || schema_from=/dev/null
  [[ -f "$schema_to" ]] || schema_to=/dev/null
  udiff "$schema_from" "$schema_to" values.schema.json values-schema.diff
fi

# ---- upgrade notes the chart ships inside itself
{
  for f in "$to_dir"/{UPGRADE,UPGRADING,MIGRATION,MIGRATING}*.md; do
    [[ -f "$f" ]] && printf '# %s\n\n%s\n\n' "${f#"$to_dir"/}" "$(cat "$f")"
  done
  if [[ -f "$to_dir/README.md" ]]; then
    # every README section whose heading mentions upgrading, migrating or breaking changes,
    # down to the next heading of the same or higher level
    awk '
      /^#+[ \t]/ {
        level = match($0, /[^#]/) - 1
        if (keep && level <= keep_level) keep = 0
        if (!keep && tolower($0) ~ /upgrad|migrat|breaking/) { keep = 1; keep_level = level }
      }
      keep { print }
    ' "$to_dir/README.md"
  fi
} >"$out/upgrade-notes.md"

# ---- renders, normalized so a diff shows content rather than ordering and checksums.
# CRDs are split out of the render diffs, which they would dominate, into their own inventory.
normalize() {
  yq ea '[.] | map(select(. != null)) | sort_by(.kind + "/" + (.metadata.namespace // "") + "/" + .metadata.name) | .[] | split_doc' "$1" |
    yq '(.. | select(tag == "!!map")) |= with_entries(select(.key | test("^checksum/|^helm.sh/chart$|^app.kubernetes.io/version$") | not)) | sort_keys(..)'
}
render() {
  local side="$1" dir="$2" name="$3"; shift 3
  local base="$out/render/$name-$side"
  local args=(template release "$dir" --include-crds --namespace "$namespace")
  [[ -n "$kube_version" ]] && args+=(--kube-version "$kube_version")
  args+=("${api_versions[@]}")
  if helm "${args[@]}" "$@" >"$base.raw.yaml" 2>"$base.err"; then
    normalize "$base.raw.yaml" >"$base.all.yaml"
    yq 'select(.kind != "CustomResourceDefinition")' "$base.all.yaml" >"$base.yaml"
    rm -f "$base.raw.yaml" "$base.err"
    echo ok
  else
    rm -f "$base.raw.yaml"
    echo "FAILED (see render/$name-$side.err)"
  fi
}
defaults_from="$(render from "$from_dir" defaults)"
defaults_to="$(render to "$to_dir" defaults)"
if [[ "$defaults_from" == ok && "$defaults_to" == ok ]]; then
  udiff "$out/render/defaults-from.yaml" "$out/render/defaults-to.yaml" render-defaults.yaml render-defaults.diff
fi
values_status="not requested" ours_from="" ours_to=""
if ((${#values[@]})); then
  vargs=()
  for f in "${values[@]}"; do
    if ((envsubst)); then
      # resolves Flux post-build placeholders, including ${var:=default}, from the environment
      resolved="$out/render/values-$(basename "$f")"
      # flux envsubst also parses comments, so a literal ${...} in a comment fails here
      flux envsubst <"$f" >"$resolved" 2>"$resolved.err" ||
        { echo "ERROR flux envsubst failed on $f: $(cat "$resolved.err")" >&2; exit 2; }
      rm -f "$resolved.err"
      f="$resolved"
    fi
    vargs+=(-f "$f")
  done
  ours_from="$(render from "$from_dir" ours "${vargs[@]}")"
  ours_to="$(render to "$to_dir" ours "${vargs[@]}")"
  values_status="from $ours_from, to $ours_to"
  if [[ "$ours_from" == ok && "$ours_to" == ok ]]; then
    udiff "$out/render/ours-from.yaml" "$out/render/ours-to.yaml" render-ours.yaml render-ours.diff
  fi
fi

# ---- CRD inventory, from the render with our values when both sides rendered, else defaults.
# Templated CRDs gated behind a value appear or vanish with that value, so the source matters.
crd_source=defaults
[[ "$ours_from" == ok && "$ours_to" == ok ]] && crd_source=ours
crd_split() {
  local src="$1" dest="$2"
  [[ -f "$src" ]] || return 0
  (cd "$dest" && yq 'select(.kind == "CustomResourceDefinition")' "$src" |
    yq -s '.spec.group + "_" + .spec.names.kind' 'select(. != null)' - 2>/dev/null) || true
}
crd_split "$out/render/$crd_source-from.all.yaml" "$out/crds/from"
crd_split "$out/render/$crd_source-to.all.yaml" "$out/crds/to"
served() { yq '[.spec.versions[] | select(.served) | .name] | join(",")' "$1"; }
# schema without prose, since most CRD churn between releases is description text and doc links
schema() { yq 'del(.metadata) | del(.. | .description?)' "$1"; }
{
  echo "# source: $crd_source render. states: schema-changed (see crds/<name>.paths.diff), docs-only (descriptions/metadata), unchanged, added, removed"
  for f in $( (cd "$out/crds" && ls from to) 2>/dev/null | grep '\.yml$' | sort -u); do
    a="$out/crds/from/$f" b="$out/crds/to/$f"
    if [[ -f "$a" && -f "$b" ]]; then
      if cmp -s "$a" "$b"; then state=unchanged
      elif cmp -s <(schema "$a") <(schema "$b"); then state=docs-only
      else
        state=schema-changed
        # one line per changed leaf, keyed by its YAML path, so a field our CRs set can be looked up
        diff <(schema "$a" | yq -o props) <(schema "$b" | yq -o props) | grep '^[<>]' >"$out/crds/${f%.yml}.paths.diff" || true
      fi
      printf '%-15s %s  served: %s -> %s\n' "$state" "${f%.yml}" "$(served "$a")" "$(served "$b")"
    elif [[ -f "$b" ]]; then
      printf '%-15s %s  served: %s\n' added "${f%.yml}" "$(served "$b")"
    else
      printf '%-15s %s  served: %s\n' removed "${f%.yml}" "$(served "$a")"
    fi
  done
} >"$out/crds.txt"

# ---- summary on stdout
fact() { yq -r "$1" "$out/chart-$2.json"; }
echo "chart     $(fact .version from) -> $(fact .version to)"
echo "appVersion $(fact .appVersion from) -> $(fact .appVersion to)"
echo "kubeVersion $(fact .kubeVersion from) -> $(fact .kubeVersion to)"
echo "sources/home $(fact '.sources + [.home] | map(select(. != null)) | unique | join(" ")' to)"
diff <(fact '.dependencies[]' from) <(fact '.dependencies[]' to) | sed -n 's/^[<>]/dependency &/p' || true
[[ -n "$(fact .artifacthub_changes to)" ]] && echo "artifacthub.io/changes present in chart-to.json (TO only)"
echo "diffs     values.diff $(lines "$out/values.diff") lines, chart-yaml.diff $(lines "$out/chart-yaml.diff"), values-schema.diff $(lines "$out/values-schema.diff")"
echo "upgrade-notes.md $(lines "$out/upgrade-notes.md") lines"
echo "render    defaults: from $defaults_from, to $defaults_to ($(lines "$out/render-defaults.diff") diff lines); ours: $values_status ($(lines "$out/render-ours.diff") diff lines)"
echo "crds      ($crd_source render) $(grep -v '^#' "$out/crds.txt" | awk '{print $1}' | sort | uniq -c | awk '{printf "%s %s, ", $2, $1}')see crds.txt"
echo "out       $out"
