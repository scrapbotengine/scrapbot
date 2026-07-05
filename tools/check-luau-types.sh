#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

find_luau_lsp() {
  if [[ -n "${LUAU_LSP_BIN:-}" && -x "${LUAU_LSP_BIN}" ]]; then
    printf '%s\n' "${LUAU_LSP_BIN}"
    return
  fi

  if command -v luau-lsp >/dev/null 2>&1; then
    command -v luau-lsp
    return
  fi

  local extension_dir="${HOME}/.vscode/extensions"
  if [[ -d "${extension_dir}" ]]; then
    local candidate
    candidate="$(find "${extension_dir}" -path '*/johnnymorganz.luau-lsp-*/bin/server' -type f 2>/dev/null | sort | tail -n 1 || true)"
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return
    fi
  fi

  printf 'error: luau-lsp not found; set LUAU_LSP_BIN to the Luau Language Server binary\n' >&2
  exit 1
}

luau_lsp="$(find_luau_lsp)"
definitions="${repo_root}/types/scrapbot.d.luau"
luaurc="${repo_root}/.luaurc"

analyze() {
  "${luau_lsp}" analyze \
    --platform=standard \
    --flag:LuauSolverV2=true \
    "--definitions:scrapbot=${definitions}" \
    --base-luaurc "${luaurc}" \
    "$@"
}

cd "${repo_root}"

while IFS= read -r script; do
  analyze "${script}"
done < <(find examples tests/projects -path '*/scripts/*.luau' -type f | sort)

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

valid_script="${tmpdir}/typed-query-valid.luau"
cat > "${valid_script}" <<'LUA'
local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
local Spin = ecs.component("spin", {
  fields = ecs.fields({
    angular_velocity = "vec3",
    label = "string",
    enabled = "boolean",
    speed = "f32",
  }),
})
local RotatingCubes = ecs.query(Transform, Spin)

ecs.system("typed_query", {
  phase = "update",
  query = RotatingCubes,
  writes = ecs.refs(Transform),
  run = function(world, dt)
    for _entity, transform, spin in RotatingCubes:iter(world) do
      local _rotation: ScrapbotVec3 = transform.rotation
      local _angular_speed: number = spin.angular_velocity[1] * dt
      local _label: string = spin.label
      local _enabled: boolean = spin.enabled
      local _speed: number = spin.speed
      transform.rotation = {
        transform.rotation[1] + spin.angular_velocity[1] * dt,
        transform.rotation[2],
        transform.rotation[3],
      }
    end
  end,
})
LUA

analyze "${valid_script}"

invalid_script="${tmpdir}/typed-query-invalid.luau"
cat > "${invalid_script}" <<'LUA'
local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
local Spin = ecs.component("spin", {
  fields = ecs.fields({
    angular_velocity = "vec3",
  }),
})
local RotatingCubes = ecs.query(Transform, Spin)

ecs.system("typed_query", {
  query = RotatingCubes,
  writes = ecs.refs(Transform),
  run = function(world, dt)
    for _entity, transform, _spin in RotatingCubes:iter(world) do
      local _bad: string = transform.rotation
    end
  end,
})
LUA

invalid_output="${tmpdir}/typed-query-invalid.out"
if analyze "${invalid_script}" >"${invalid_output}" 2>&1; then
  printf 'error: expected invalid typed query fixture to fail Luau analysis\n' >&2
  exit 1
fi

if ! grep -q "Expected this to be 'string'" "${invalid_output}"; then
  printf 'error: invalid typed query fixture failed for an unexpected reason\n' >&2
  cat "${invalid_output}" >&2
  exit 1
fi

invalid_schema_script="${tmpdir}/typed-schema-invalid.luau"
cat > "${invalid_schema_script}" <<'LUA'
local _Spin = ecs.component("spin", {
  fields = ecs.fields({
    angular_velocity = "vec4",
  }),
})
LUA

invalid_schema_output="${tmpdir}/typed-schema-invalid.out"
if analyze "${invalid_schema_script}" >"${invalid_schema_output}" 2>&1; then
  printf 'error: expected invalid schema fixture to fail Luau analysis\n' >&2
  exit 1
fi

if ! grep -q "vec4" "${invalid_schema_output}"; then
  printf 'error: invalid inferred field fixture failed for an unexpected reason\n' >&2
  cat "${invalid_schema_output}" >&2
  exit 1
fi

valid_schema_script="${tmpdir}/typed-schema-compat-valid.luau"
cat > "${valid_schema_script}" <<'LUA'
local Spin = ecs.component("spin", {
  fields = ecs.schema({
    angular_velocity = ecs.vec3(),
  }),
})

local spin = Spin.__scrapbot_component_type()
local _angular_velocity: ScrapbotVec3 = spin.angular_velocity
LUA

analyze "${valid_schema_script}"

invalid_fields_script="${tmpdir}/typed-fields-invalid.luau"
cat > "${invalid_fields_script}" <<'LUA'
type Spin = {
  angular_velocity: ScrapbotVec3,
}

local _Spin = ecs.component<<Spin>>("spin", {
  fields = ecs.fields({
    angular_velocity = "vec4",
  }),
})
LUA

invalid_fields_output="${tmpdir}/typed-fields-invalid.out"
if analyze "${invalid_fields_script}" >"${invalid_fields_output}" 2>&1; then
  printf 'error: expected invalid field fixture to fail Luau analysis\n' >&2
  exit 1
fi

if ! grep -q "vec4" "${invalid_fields_output}"; then
  printf 'error: invalid field fixture failed for an unexpected reason\n' >&2
  cat "${invalid_fields_output}" >&2
  exit 1
fi
