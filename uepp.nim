# Runs the msvc preprocessor on an Unreal cpp
# Pass a relative path to the file as an argument. 
# The root directory will be walked and all directories will be included for the compiler.

import std / [os, osproc, parseopt, tables, strformat, strutils, times, sequtils, options, terminal, sugar, exitprocs]

const preprocessedDir = "preprocessed"
# ubtflags may need to be edited for your platform and project
# pulled from AppData/Local/UnrealBuildTool/Log.txt
const ubtflags = "/D_WIN64 /I \"C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\VC\\Tools\\MSVC\\14.32.31326\\INCLUDE\" /I \"C:\\Program Files (x86)\\Windows Kits\\NETFXSDK\\4.8\\include\\um\" /I \"C:\\Program Files (x86)\\Windows Kits\\10\\include\\10.0.18362.0\\ucrt\" /I \"C:\\Program Files (x86)\\Windows Kits\\10\\include\\10.0.18362.0\\shared\" /I \"C:\\Program Files (x86)\\Windows Kits\\10\\include\\10.0.18362.0\\um\" /I \"C:\\Program Files (x86)\\Windows Kits\\10\\include\\10.0.18362.0\\winrt\" /DIS_PROGRAM=0 /DUE_EDITOR=1 /DENABLE_PGO_PROFILE=0 /DUSE_VORBIS_FOR_STREAMING=1 /DUSE_XMA2_FOR_STREAMING=1 /DWITH_DEV_AUTOMATION_TESTS=1 /DWITH_PERF_AUTOMATION_TESTS=1 /DUNICODE /D_UNICODE /D__UNREAL__ /DIS_MONOLITHIC=0 /DWITH_ENGINE=1 /DWITH_UNREAL_DEVELOPER_TOOLS=1 /DWITH_UNREAL_TARGET_DEVELOPER_TOOLS=1 /DWITH_APPLICATION_CORE=1 /DWITH_COREUOBJECT=1 /DWITH_VERSE=0 /DUSE_STATS_WITHOUT_ENGINE=0 /DWITH_PLUGIN_SUPPORT=0 /DWITH_ACCESSIBILITY=1 /DWITH_PERFCOUNTERS=1 /DUSE_LOGGING_IN_SHIPPING=0 /DWITH_LOGGING_TO_MEMORY=0 /DUSE_CACHE_FREED_OS_ALLOCS=1 /DUSE_CHECKS_IN_SHIPPING=0 /DUSE_ESTIMATED_UTCNOW=0 /DWITH_EDITOR=1 /DWITH_IOSTORE_IN_EDITOR=1 /DWITH_SERVER_CODE=1 /DWITH_PUSH_MODEL=1 /DWITH_CEF3=1 /DWITH_LIVE_CODING=1 /DWITH_CPP_MODULES=0 /DWITH_CPP_COROUTINES=0 /DUBT_MODULE_MANIFEST=\"UnrealEditor.modules\" /DUBT_MODULE_MANIFEST_DEBUGGAME=\"UnrealEditor-Win64-DebugGame.modules\" /DUBT_COMPILED_PLATFORM=Win64 /DUBT_COMPILED_TARGET=Editor /DUE_APP_NAME=\"UnrealEditor\" /DNDIS_MINIPORT_MAJOR_VERSION=0 /DWIN32=1 /D_WIN32_WINNT=0x0601 /DWINVER=0x0601 /DPLATFORM_WINDOWS=1 /DPLATFORM_MICROSOFT=1 /DOVERRIDE_PLATFORM_HEADER_NAME=Windows /DRHI_RAYTRACING=1 /DNDEBUG=1 /DUE_BUILD_DEVELOPMENT=1 /DORIGINAL_FILE_NAME=\"UEPP.dll\" /DBUILT_FROM_CHANGELIST=20979098 /DBUILD_VERSION=++UE5+Release-5.0-CL-20979098 /DBUILD_ICON_FILE_NAME=\"\\\"..\\Build\\Windows\\Resources\\Default.ico\\\"\" /DPROJECT_COPYRIGHT_STRING=\"Fill out your copyright notice in the Description page of Project Settings.\" /DPROJECT_PRODUCT_NAME=\"UEPP\" /DPROJECT_PRODUCT_IDENTIFIER=UEPP"
const winsdkflags = "/D__midl=0 /DUE_ENABLE_ICU=0 /DWITH_DIRECTXMATH=0"

addExitProc(() => resetAttributes()) # for terminal

proc log(msg: string) =
  stdout.styledWrite(styleBright, msg & "\n")

proc logError(msg:string) =
  stderr.styledWrite(styleBright, fgRed, msg & "\n")

if commandLineParams().len < 1:
  log("""Usage: uepp filepath [IncludeDir, ...]
  The filepath is the cpp file to preprocess.
  Zero or more include directories where it and its sub-directories will be included for the compiler.
  Example: uepp ./Source/NimForUE/Private/TestActor.cpp ./Source
  The ./Source directory and its subdirectories will be included for preprocessing. The output will be in ./preprocessed/TestActor""")
  quit()


template quotes(path: string): untyped =
  "\"" & path & "\""

proc getUEHeadersIncludePaths*() : seq[string] =
  let engineDir = r"D:\UE_5.0\Engine"
  proc getEngineIncludePathFor(engineFolder, moduleName:string) : string = 
    quotes(engineDir/"Source"/engineFolder/moduleName/"Public")
  proc getEngineIntermediateIncludePathFor(moduleName:string) : string = 
    quotes(engineDir/"Intermediate/Build/Win64/UnrealEditor/Inc"/moduleName)
  
  let essentialHeaders = @[
    quotes(engineDir/"Source/Runtime/Engine/Classes"),
    quotes(engineDir/"Source/Runtime/Engine/Classes/Engine"),
    quotes(engineDir/"Source/Runtime/Net/Core/Public"),
    quotes(engineDir/"Source/Runtime/Net/Core/Classes"),
    quotes(engineDir/"Source/Runtime/InputCore/Classes")
  ]

  let
    runtimeModules = @["CoreUObject", "Core", "Engine", "TraceLog", "Launch", "ApplicationCore", 
      "Projects", "Json", "PakFile", "RSA", "Engine", "RenderCore",
      "NetCore", "CoreOnline", "PhysicsCore", "Experimental/Chaos", 
      "Experimental/ChaosCore", "InputCore", "RHI", "AudioMixerCore", "AssetRegistry", "DeveloperSettings"]
    developerModules = @["DesktopPlatform", "ToolMenus", "TargetPlatform", "SourceControl"]
    intermediateGenModules = @["NetCore", "Engine", "PhysicsCore", "AssetRegistry", "InputCore", "DeveloperSettings"]

  let moduleHeaders = 
    runtimeModules.map(module=>getEngineIncludePathFor("Runtime", module)) &
    developerModules.map(module=>getEngineIncludePathFor("Developer", module)) &
    intermediateGenModules.map(module=>getEngineIntermediateIncludePathFor(module))

  essentialHeaders & moduleHeaders

# Find the definitions here:
# https://docs.microsoft.com/en-us/cpp/build/reference/compiler-options-listed-alphabetically?view=msvc-170
# These flags are from the .response in the Intermediate folder for the UE Modules
# TODO?: get the flags from the PCH response file in Intermediate instead of hardcoding
const CompileFlags = [
#"/c", # not compiling
#(if isDebug: "/Od /Z7" else: "/O2"), # preprocessing doesn't need this
"--platform:amd64",
"/nologo",
"/EHsc",
"-DWIN32_LEAN_AND_MEAN",
"/D_CRT_STDIO_LEGACY_WIDE_SPECIFIERS=1",
"/D_SILENCE_STDEXT_HASH_DEPRECATION_WARNINGS=1",
"/D_WINDLL",
"/D_DISABLE_EXTENDED_ALIGNED_STORAGE",
"/DPLATFORM_EXCEPTIONS_DISABLED=0",
"/FS",
"/Zc:inline", #Remove unreferenced functions or data if they're COMDAT or have internal linkage only (off by default).
"/Oi", # generate intrinsics
"/Gw", # Enables whole-program global data optimization.
"/Gy", # Enables function-level linking.
"/Ob2", # /Ob<n>	Controls inline expansion. 2 The default value under /O1 and /O2. Allows the compiler to expand any function not explicitly marked for no inlining.
#"/Ox", # A subset of /O2 that doesn't include /GF or /Gy. Enable Most Speed Optimizations
"/Ot", # Favors fast code.
"/GF", # Enables string pooling.
"/bigobj", # Increases the number of addressable sections in an .obj file.
"/GR-", # /GR[-]	Enables run-time type information (RTTI).
"/std:c++17",
"/Zp8",
"/source-charset:utf-8" ,
"/execution-charset:utf-8",
"/MD",
"/fp:fast", # "fast" floating-point model; results are less predictable.
#"/W4", # Set output warning level.
# /we<n>	Treat the specified warning as an error.
"/we4456",
"/we4458",
"/we4459",
"/we4668",
# /wd<n>  Disable the specified warning.
"/wd4819", 
"/wd4463",
"/wd4244",
"/wd4838"
]

proc preprocessCmd(cpppath: string, includes: seq[string], destPath: string): string =

  var includeDirs:seq[string]
  for rootDir in includes:
    includeDirs &= rootDir
    var baseDir:string = rootDir
    if not isAbsolute(rootDir):
      baseDir = absolutePath(rootDir.parentDirs(fromRoot = true).toSeq()[1])
    
    let dirs = collect:
        for path in baseDir.walkDirRec(yieldFilter = {pcDir}):
          quotes(path)

    includeDirs &= dirs

  let (dir, filename, ext) = cpppath.splitFile
  # if you want to remove the #line directives add the /EP flag
  "vccexe.exe " &
    &"/P /C /Fi\"{destPath}\" {ubtflags} {winsdkflags} " &
    CompileFlags.join(" ") & " " &
    getUEHeadersIncludePaths().foldl(a & " -I" & b, " ") & " " &
    includeDirs.foldl(a & " -I" & b, " ") & " " &
    " " & cppPath

proc preprocess*(srcPath: string, includes: seq[string]) =

  if not fileExists(srcPath):
    logError(&"File does not exist: {srcPath}")
    quit()

  let (dir, filename, ext) = srcPath.splitFile
  var destDir: string = preprocessedDir / filename
  var destPath: string = destDir / filename & ".i"

  createDir(destDir)
  let cmd = preprocessCmd(srcPath, includes, destPath)

  log(&"--- Preprocessing\n")
  let res = execCmd(cmd)
  if res == 0:
    let (dir, filename, ext) = srcPath.splitFile
    log(&"Generated: {destPath}\n")

let params = commandLineParams()
let includes:seq[string] = if params.len > 1: params[1..^1] else: @[]
preprocess(params[0], includes)