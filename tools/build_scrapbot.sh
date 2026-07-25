#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
	echo "usage: $0 <output> <optimization-mode>" >&2
	exit 2
fi

output="$1"
optimization_mode="$2"
output_dir=$(dirname "$output")
output_name=$(basename "$output")
staging_dir="$output_dir/.${output_name}-build-$$"
staged_output="$staging_dir/$output_name"

cleanup() {
	rm -rf "$staging_dir"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$staging_dir"

luau_libs="third_party/luau/build/release"
case "$(uname -s)" in
	Darwin)
		luau_link_flags="-Wl,-force_load,$luau_libs/libluaucompiler.a -Wl,-force_load,$luau_libs/libluauast.a -Wl,-force_load,$luau_libs/libluaubytecode.a -Wl,-force_load,$luau_libs/libluauvm.a -Wl,-force_load,$luau_libs/libluaucommon.a -lc++"
		;;
	Linux)
		luau_link_flags="-Wl,--whole-archive $luau_libs/libluaucompiler.a $luau_libs/libluauast.a $luau_libs/libluaubytecode.a $luau_libs/libluauvm.a $luau_libs/libluaucommon.a -Wl,--no-whole-archive -lstdc++ -lpthread"
		;;
	*)
		echo "unsupported Luau link platform: $(uname -s)" >&2
		exit 1
		;;
esac

odin build src/scrapbot_cli \
	-out:"$staged_output" \
	-o:"$optimization_mode" \
	-extra-linker-flags:"$luau_link_flags"

mkdir -p "$output_dir"
mv -f "$staged_output" "$output"
