$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")
$OutDir = Join-Path $RootDir "odin-out\luau-bridge"
$ObjDir = Join-Path $OutDir "obj"
$LibPath = Join-Path $OutDir "scrapbot_luau_bridge.lib"

New-Item -ItemType Directory -Force -Path $ObjDir | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue $LibPath

$Cxx = if ($env:CXX) { $env:CXX } else { "cl.exe" }
$LibTool = if ($env:LIB_TOOL) { $env:LIB_TOOL } else { "lib.exe" }

$IncludeFlags = @(
  "/std:c++17",
  "/EHsc",
  "/Isrc",
  "/Ithird_party/luau/Common/include",
  "/Ithird_party/luau/Ast/include",
  "/Ithird_party/luau/Bytecode/include",
  "/Ithird_party/luau/Compiler/include",
  "/Ithird_party/luau/VM/include"
)

$Sources = @(
  "src/luau_bridge.cpp",
  "third_party/luau/Common/src/BytecodeWire.cpp",
  "third_party/luau/Common/src/StringUtils.cpp",
  "third_party/luau/Common/src/TimeTrace.cpp",
  "third_party/luau/Ast/src/Allocator.cpp",
  "third_party/luau/Ast/src/Ast.cpp",
  "third_party/luau/Ast/src/Confusables.cpp",
  "third_party/luau/Ast/src/Cst.cpp",
  "third_party/luau/Ast/src/Lexer.cpp",
  "third_party/luau/Ast/src/Location.cpp",
  "third_party/luau/Ast/src/Parser.cpp",
  "third_party/luau/Ast/src/PrettyPrinter.cpp",
  "third_party/luau/Bytecode/src/BytecodeBuilder.cpp",
  "third_party/luau/Bytecode/src/BytecodeGraph.cpp",
  "third_party/luau/Compiler/src/Compiler.cpp",
  "third_party/luau/Compiler/src/Builtins.cpp",
  "third_party/luau/Compiler/src/BuiltinFolding.cpp",
  "third_party/luau/Compiler/src/ConstantFolding.cpp",
  "third_party/luau/Compiler/src/CostModel.cpp",
  "third_party/luau/Compiler/src/TableShape.cpp",
  "third_party/luau/Compiler/src/Types.cpp",
  "third_party/luau/Compiler/src/ValueTracking.cpp",
  "third_party/luau/Compiler/src/lcode.cpp",
  "third_party/luau/VM/src/lapi.cpp",
  "third_party/luau/VM/src/laux.cpp",
  "third_party/luau/VM/src/lbaselib.cpp",
  "third_party/luau/VM/src/lbitlib.cpp",
  "third_party/luau/VM/src/lbuffer.cpp",
  "third_party/luau/VM/src/lbuflib.cpp",
  "third_party/luau/VM/src/lbuiltins.cpp",
  "third_party/luau/VM/src/lcorolib.cpp",
  "third_party/luau/VM/src/ldblib.cpp",
  "third_party/luau/VM/src/ldebug.cpp",
  "third_party/luau/VM/src/ldo.cpp",
  "third_party/luau/VM/src/lfunc.cpp",
  "third_party/luau/VM/src/lgc.cpp",
  "third_party/luau/VM/src/lgcdebug.cpp",
  "third_party/luau/VM/src/linit.cpp",
  "third_party/luau/VM/src/lmathlib.cpp",
  "third_party/luau/VM/src/lmem.cpp",
  "third_party/luau/VM/src/lnumprint.cpp",
  "third_party/luau/VM/src/lobject.cpp",
  "third_party/luau/VM/src/loslib.cpp",
  "third_party/luau/VM/src/lperf.cpp",
  "third_party/luau/VM/src/lstate.cpp",
  "third_party/luau/VM/src/lstring.cpp",
  "third_party/luau/VM/src/lstrlib.cpp",
  "third_party/luau/VM/src/ltable.cpp",
  "third_party/luau/VM/src/ltablib.cpp",
  "third_party/luau/VM/src/ltm.cpp",
  "third_party/luau/VM/src/ludata.cpp",
  "third_party/luau/VM/src/lutf8lib.cpp",
  "third_party/luau/VM/src/lveclib.cpp",
  "third_party/luau/VM/src/lintlib.cpp",
  "third_party/luau/VM/src/lvmexecute.cpp",
  "third_party/luau/VM/src/lclass.cpp",
  "third_party/luau/VM/src/lclasslib.cpp",
  "third_party/luau/VM/src/lvmload.cpp",
  "third_party/luau/VM/src/lvmutils.cpp"
)

$Objects = @()
Push-Location $RootDir
try {
  foreach ($Source in $Sources) {
    $ObjectName = ($Source -replace "[\\/\.]", "_") + ".obj"
    $ObjectPath = Join-Path $ObjDir $ObjectName
    & $Cxx /nologo @IncludeFlags /c $Source /Fo$ObjectPath
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $Objects += $ObjectPath
  }

  & $LibTool /NOLOGO /OUT:$LibPath @Objects
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Pop-Location
}
