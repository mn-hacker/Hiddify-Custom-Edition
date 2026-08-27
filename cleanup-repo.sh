#!/bin/bash
# watashi repo prune - v12.2.54
# every path is checked for references before it is removed.
# usage:  bash cleanup-repo.sh list | a | b | c | a b
set -u

if [ ! -f install.sh ] || [ ! -f common/utils.sh ]; then
	echo "run me from the repository root (where install.sh lives)"
	exit 1
fi

SELF=$(basename "$0")
freed=0
mode_list=0

GROUP_A=(
	"arm.tar.gz"
	"uv.toml"
	"other/warp_old_beta"
	"hiddify-panel/src/project.inlang"
	"hiddify-panel/src/ABOUT_THIS_TEMPLATE.md"
	"hiddify-panel/src/apply.sh"
	"hiddify-panel/src/hiddifypanel/panel/auth_back.py"
	"hiddify-panel/src/hiddifypanel/panel/node/a.py"
	"hiddify-panel/src/hiddifypanel/panel/node/test_grpc.py"
	"hiddify-panel/src/hiddifypanel/panel/node/test.proto"
	"hiddify-panel/src/hiddifypanel/panel/node/test_pb2.pyi"
	".github/FUNDING.yml"
	".github/dependabot.yml"
	".github/workflows/delete_issue.yml"
	"README_cn.md"
	"README_ru.md"
)

GROUP_B=(
	"Other panel"
	"theme_backup"
)

GROUP_C=(
	"Dockerfile"
	"docker-compose.yml"
	"docker-init.sh"
	"docker.env"
	".dockerignore"
	"other/docker"
	"common/docker-installer.sh"
	".github/workflows/docker.yaml"
	"btn-deploy"
	".kiro"
	"hiddify-panel/src/Makefile"
	"hiddify-panel/src/mkdocs.yml"
)

ws_weigh() { du -sb "$1" 2>/dev/null | awk '{print $1}'; }

ws_refs() {
	grep -rIl -F "$1" . \
		--exclude-dir=.git --exclude-dir=__pycache__ --exclude-dir=.venv \
		--exclude-dir="Other panel" --exclude-dir=theme_backup \
		--exclude-dir=docs --exclude-dir=node_modules \
		--exclude=.gitignore --exclude=uv.lock --exclude=poetry.lock \
		--exclude=HISTORY.md --exclude="*.b[0-9][0-9]" --exclude="$SELF" \
		--exclude=DELETE-LIST.md --exclude=WATASHI-HANDOFF-4.md 2>/dev/null \
		| grep -v "^\./$1" | grep -v "^\./tools/" | head -5
}

ws_kill() {
	local path="$1" force="${2:-no}" size refs
	if [ ! -e "$path" ]; then
		echo "  already gone: $path"
		return
	 fi
	size=$(ws_weigh "$path")
	if [ "$mode_list" = "1" ]; then
		echo "  would delete: $path ($size bytes)"
		freed=$((freed + size))
		return
	fi
	if [ "$force" != "force" ]; then
		refs=$(ws_refs "$path")
		if [ -n "$refs" ]; then
			echo "  kept: $path - still referenced by:"
			echo "$refs" | sed 's/^/      /'
			return
		fi
	fi
	git rm -r -q -f --ignore-unmatch -- "$path" 2>/dev/null || rm -rf "$path"
	rm -rf "$path"
	echo "  deleted: $path ($size bytes)"
	freed=$((freed + size))
}

ws_group_a2() {
	echo "-- group A2: committed round backups (*.bNN)"
	local f
	while IFS= read -r f; do
		[ -n "$f" ] && ws_kill "$f" force
	done < <(git ls-files | grep -E '\.b[0-9][0-9]$')
	if [ "$mode_list" != "1" ] && ! grep -q 'b\[0-9\]\[0-9\]' .gitignore 2>/dev/null; then
		printf '\n# watashi: per-round backups stay on the server, not in git\n*.b[0-9][0-9]\n' >> .gitignore
		echo "  .gitignore: added *.b[0-9][0-9]"
	fi
}

ws_group_a3() {
	echo "-- group A3: tools/ (round patch and check scripts)"
	if [ -d tools ]; then
		if [ -f tools/cleanup54.sh ] || [ -f tools/cleanup53.sh ]; then
			echo "  NOTE: run tools/cleanup53.sh and tools/cleanup54.sh on the server first"
		fi
		ws_kill "tools" force
	else
		echo "  already gone: tools"
	fi
}

if [ "$#" -eq 0 ]; then
	echo "usage: bash $SELF list | a | b | c | a b c"
	exit 1
fi

for arg in "$@"; do
	case "$arg" in
	list) mode_list=1 ;;
	esac
done

for arg in "$@"; do
	case "$arg" in
	a)
		echo "-- group A: verified dead"
		for p in "${GROUP_A[@]}"; do ws_kill "$p"; done
		ws_group_a2
		ws_group_a3
		;;
	b)
		echo "-- group B: dead weight"
		for p in "${GROUP_B[@]}"; do ws_kill "$p"; done
		sed -i '/^Other panel/d;/^theme_backup/d' .gitignore 2>/dev/null
		;;
	c)
		echo "-- group C: your call (docker, oracle deploy, ide specs, poetry leftovers)"
		for p in "${GROUP_C[@]}"; do ws_kill "$p"; done
		;;
	list)
		echo "-- dry run: nothing will be deleted"
		for p in "${GROUP_A[@]}" "${GROUP_B[@]}"; do ws_kill "$p"; done
		;;
	*) echo "unknown group: $arg" ;;
	esac
done

echo "freed $freed bytes in total"
echo "now: git status --short | head -20   then commit and push"
