#!/bin/bash

set -e

tests_repo="${1:?"Path to tests repository is needed"}"
docs_dir="${2:?"Path to docs directory is needed"}"
reports_dir="${tests_repo}/.reports"

# use '-k' to keep files used for generating the report (useful when the report should be generated
# from multiple testruns)
if [ "${3:-""}" = "-k" ]; then
  keep_files=1
else
  keep_files=""
fi

get_version() {
  sed -n 's/cardano-node=\(.*\)/\1/p' "$1"
}

get_revision() {
  sed -n 's/cardano-node.rev=\(.*\)/\1/p' "$1"
}

get_coverage() {
  if ! compgen -G "$tests_repo/.cli_coverage/cli_coverage_*" > /dev/null || ! hash curl || ! hash cardano-cli; then
    return
  fi
  oldpwd="$(pwd)"
  cd "$tests_repo"
  url="$(cardano_node_tests/cardano_cli_coverage.py -i .cli_coverage/cli_coverage_* -o .cli_coverage/out.json -b)"
  cd "$oldpwd"
  cp "$tests_repo/.cli_coverage/out.json" "$docs_dir/cli_coverage.json"
  curl "$url" --output "$docs_dir/cli_coverage_badge.svg"
  echo "<a href=\"cli_coverage.json\"><img src=\"cli_coverage_badge.svg\"></a><br/>"
}

get_git_tags() {
  local node_repo="${CARDANO_NODE_SOCKET_PATH%/*/*}"
  if [ -z "$node_repo" ]; then
    echo "Unable to get path to cardano-node repo" >&2
    exit 1
  fi
  local curdir="$PWD"
  cd "$node_repo"
  # prepend number to log lines so the commits can be sorted
  git log --pretty=format:"%H %d" | nl -n rz -s ';' | sed "s/\([a-z0-9]*\)  (.*tag: \([1-9]\.[0-9.]*\).*)/\1 <em>(tag: \2)<\/em>/;s/ (.*//"
  cd "$curdir"
}

get_links() {
  local lsargs="$1"
  local dirpath="$2"
  local prepend="$3"
  local grep_file="$4"
  local report_line
  local report_name
  if [ -n "$prepend" ]; then
    prepend="${prepend}/"
  fi

  ls "$lsargs" "$dirpath" | sort -r | head -n 20 | while read filename; do
    # skip old reports and also *.md files
    if [[ "${filename}" =~ (assets|\.(html|md))$ ]]; then
      continue
    fi
    report_name="${filename#*/}"
    report_line=""
    numbering=""
    if [ -n "$grep_file" ]; then
      report_line="$(grep "$report_name" "$grep_file" || :)"
      numbering="${report_line%%;*};"
      report_line="${report_line#*;}"
    fi
    if [ -z "$report_line" ]; then
      report_line="$report_name"
    fi
    echo "${numbering}<a href=\"${prepend}${report_name}\">$report_line</a><br/>"
  done
}

allure_report_dir="$reports_dir"/allure-report
cardano_version="$(get_version "$reports_dir"/environment.properties)"
cardano_rev="$(get_revision "$reports_dir"/environment.properties)"
destdir="$docs_dir/allure_files/$cardano_version/$cardano_rev"

get_git_tags > "$reports_dir/.git_tags"

if [ -z "$cardano_version" ] || [ -z "$cardano_rev" ]; then
  echo "Unable to get cardano version and/or revision" >&2
  exit 1
fi

mkdir -p "$destdir"
cp -a "$reports_dir/environment.properties" "$reports_dir"/*.json "$reports_dir"/*.txt "$destdir"

rm -rf "$allure_report_dir"
mkdir -p "$allure_report_dir"
cp -a "$destdir/environment.properties" "$allure_report_dir"
allure generate "$destdir" -o "$allure_report_dir" --clean

if [ -z "$keep_files" ]; then
  rm -rf "$destdir"
  rmdir "$docs_dir/allure_files/$cardano_version" || :
  rmdir "$docs_dir/allure_files" || :
fi

mkdir -p "$docs_dir/reports/$cardano_version"
rm -rf "$docs_dir/reports/$cardano_version/$cardano_rev"
cp -a "$allure_report_dir" "$docs_dir/reports/$cardano_version/$cardano_rev"
rm -f "$docs_dir/reports/last.html"

get_coverage > "$docs_dir/index.md"
echo "<h2>Test reports:</h2><p>" >> "$docs_dir/index.md"
get_links -1 "$docs_dir/reports" reports >> "$docs_dir/index.md"

echo "<h2>Reports for $cardano_version:</h2><p>" > "$docs_dir/reports/$cardano_version/index.md"
# sort and get rid of commit numbering before outputting lines to the file
get_links -1t "$docs_dir/reports/$cardano_version" "" "$reports_dir/.git_tags" | sort | sed "s/.*;//" >> "$docs_dir/reports/$cardano_version/index.md"

cat > "$docs_dir/reports/last.html" <<EoF
<head>
  <script>window.location.replace("${cardano_version}/${cardano_rev}");</script>
</head>
<body>
  last -> <a href="${cardano_version}/${cardano_rev}">${cardano_version}/${cardano_rev}</a>
</body>
EoF

remote="$(git remote | grep upstream || echo "origin")"
branch="main"
echo "Commit to ${remote}/${branch}? (Enter to continue, Ctrl+C to abort)"
read -r

git fetch "$remote"
git checkout "$branch"
git pull --no-rebase "$remote" "$branch"
git add "$docs_dir"
git commit --no-verify -m "report for ${cardano_rev}"
echo "Push to ${remote}/${branch}? (Enter to continue, Ctrl+C to abort)"
read -r
git push "$remote" "$branch"
