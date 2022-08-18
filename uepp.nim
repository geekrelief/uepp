# Runs the msvc preprocessor on an Unreal cpp response file
# Thanks to https://github.com/TensorWorks/UE-Clang-Format for the ue.clang-format file

import std / [os, osproc, parseopt, tables, strformat, strutils, times, sequtils, options, terminal, sugar, exitprocs]

proc log(msg: string) =
  stdout.styledWrite(styleBright, msg & "\n")

proc logError(msg:string) =
  stderr.styledWrite(styleBright, fgRed, msg & "\n")

const preprocessedDir = "preprocessed"
const UEEngineSrcDir {.strdefine.}: string = ""
const midl {.intdefine.}: int = 0

static:
  doAssert(UEEngineSrcDir.len > 0, "UEEngineDir is undefined in nim.cfg")
  doAssert(dirExists(UEEngineSrcDir))


let projDir = getCurrentDir()
let clangFormatExe = findExe("clang-format")
let hasClangFormat = clangFormatExe.len > 0

if hasClangFormat:
  log("Found clang-format in " & clangFormatExe)
  doAssert(fileExists(getAppDir() / "ue.clang-format"))

let params = commandLineParams()

proc printUsage() =
  log("""Usage: uepp [-with-shadow] response_file
  The response_file contains the source and flags needed to preprocess the source file.
  If the -with-shadow option is used, includes "SharedPCH.Engine.ShadowErrors.h"
  Example: uepp ./TestActor.rsp
  """)
  quit()

if params.len < 1:
  printUsage()

let (rspPath, withShadow) = 
  if params.len == 1: 
    (params[0], false) 
  elif params.len == 2 and params[0] == "-with-shadow":
    (params[1], true) 
  else:
    printUsage()
    ("", false)

if not fileExists(rspPath):
  logError(&"Response file does not exist: {rspPath}")
  quit()

let (_, filename, _) = rspPath.splitFile
var destDir: string = absolutePath(preprocessedDir)
var destPath: string = destDir / filename & (if withShadow: ".shadow" else: "") & ".i"

createDir(destDir)
doAssert(dirExists(destDir))

let rspContents = 
  if withShadow:
    rspPath.lines.toseq().join(" ")
  else:
    rspPath.lines.toseq().filterIt(not it.contains("SharedPCH.Engine.ShadowErrors.h")).join(" ")

let cmd = &"vccexe.exe --platform:amd64 /P /C /Fi\"{destPath}\" " & rspContents & &" /D__midl={midl}"

setCurrentDir(UEEngineSrcDir)
log(&"--- Preprocessing")
let res = execCmd(cmd)
if res == 0:
  log(&"Generated: {destPath}\n")

setCurrentDir(projDir)

# clean up the file
var iFile = open(destPath)
proc filterWhiteSpace(lines: seq[string]): seq[string] =
  if hasClangFormat:
    lines
  else:
    lines.filterIt(not isEmptyOrWhiteSpace(it))

let content = readAll(iFile).split("\n")
  .filterWhiteSpace()
  .filterIt("#pragma once" notin it and "// Copyright" notin it)
  .join("\n")
close(iFile)

let cppPath = destPath & ".cpp"
let cppFile = open(cppPath, fmWrite)
write(cppFile, content)
flushFile(cppFile)
close(cppFile)
discard tryRemoveFile(destPath)

if hasClangFormat:
  let clangFormatPath = getAppDir() / "ue.clang-format"
  let formatCmd = clangFormatExe & " --style=file:" & clangFormatPath & " -i " & cppPath
  log(formatCmd)
  discard execCmd(formatCmd)