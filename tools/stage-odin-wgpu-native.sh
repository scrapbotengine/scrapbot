#!/usr/bin/env sh
set -eu

version="v25.0.2.1"
base_url="https://github.com/gfx-rs/wgpu-native/releases/download/${version}"

os_name="$(uname -s)"
arch_name="$(uname -m)"

case "${os_name}:${arch_name}" in
  Linux:x86_64)
    archive="wgpu-linux-x86_64-release.zip"
    library="libwgpu_native.so"
    expected_sha256="74ea0fed0aadc9b353b56db812081a1620d1d72003d7592c449ca39d5f5b61bb"
    ;;
  Linux:aarch64|Linux:arm64)
    archive="wgpu-linux-aarch64-release.zip"
    library="libwgpu_native.so"
    expected_sha256="ab048ddfcd0274d09c62db793b7dde39f1e8dc8a1135ecfbe2fe102f5cfa9943"
    ;;
  Darwin:arm64|Darwin:aarch64)
    archive="wgpu-macos-aarch64-release.zip"
    library="libwgpu_native.dylib"
    expected_sha256="df4f35417047e0f88ed6facd2cfa42d7a88bdc367bf1c7aa10c462bc8b3a2117"
    ;;
  Darwin:x86_64)
    archive="wgpu-macos-x86_64-release.zip"
    library="libwgpu_native.dylib"
    expected_sha256="64df075f30a7714daf49fa21728e5a3554c5a5254ea6372da5e7b790bc60903c"
    ;;
  *)
    echo "unsupported host for Odin wgpu-native staging: ${os_name}/${arch_name}" >&2
    exit 1
    ;;
esac

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to download wgpu-native" >&2
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "unzip is required to extract wgpu-native" >&2
  exit 1
fi

archive_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d " " -f 1
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d " " -f 1
    return
  fi

  echo "sha256sum or shasum is required to verify wgpu-native" >&2
  exit 1
}

verify_archive() {
  actual_sha256="$(archive_sha256 "$1")"
  if [ "${actual_sha256}" = "${expected_sha256}" ]; then
    return 0
  fi

  echo "wgpu-native archive checksum mismatch for ${archive}" >&2
  echo "expected: ${expected_sha256}" >&2
  echo "actual:   ${actual_sha256}" >&2
  return 1
}

cache_dir="odin-out/wgpu-native-cache"
archive_path="${cache_dir}/${archive}"
extract_dir="${cache_dir}/${archive%.zip}"
output_dir="odin-out/lib"
source_library="${extract_dir}/lib/${library}"
output_library="${output_dir}/${library}"

mkdir -p "${cache_dir}" "${output_dir}"

archive_refreshed=0
if [ ! -f "${archive_path}" ]; then
  curl --fail --location --show-error --output "${archive_path}" "${base_url}/${archive}"
  archive_refreshed=1
elif ! verify_archive "${archive_path}"; then
  rm -f "${archive_path}"
  curl --fail --location --show-error --output "${archive_path}" "${base_url}/${archive}"
  archive_refreshed=1
fi

verify_archive "${archive_path}"

if [ "${archive_refreshed}" -eq 1 ]; then
  rm -rf "${extract_dir}"
fi

if [ ! -f "${source_library}" ]; then
  rm -rf "${extract_dir}"
  mkdir -p "${extract_dir}"
  unzip -q "${archive_path}" -d "${extract_dir}"
fi

if [ ! -f "${source_library}" ]; then
  echo "downloaded wgpu-native archive did not contain lib/${library}" >&2
  exit 1
fi

cp "${source_library}" "${output_library}"
echo "staged ${output_library}"
