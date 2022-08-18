# Runs the msvc preprocessor on an Unreal cpp response file
# Thanks to https://github.com/TensorWorks/UE-Clang-Format for the ue.clang-format file

import std / [
os, osproc, sequtils, strformat, strutils, terminal
]
import spinny

proc log(msg: string) =
  stdout.styledWrite(styleBright, msg & "\n")

proc logError(msg:string) =
  stderr.styledWrite(styleBright, terminal.fgRed, msg & "\n")

const preprocessedDir = "preprocessed"
const UEEngineSrcDir {.strdefine.}: string = ""
const midl {.intdefine.}: int = 0

static:
  doAssert(UEEngineSrcDir.len > 0, "UEEngineDir is undefined in nim.cfg")
  doAssert(dirExists(UEEngineSrcDir))

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

# adjust response file contents
let rspContents = 
  if withShadow:
    rspPath.lines.toseq().join(" ")
  else:
    rspPath.lines.toseq().filterIt(not it.contains("SharedPCH.Engine.ShadowErrors.h")).join(" ")

let projDir = getCurrentDir()
setCurrentDir(UEEngineSrcDir)

var spinner1 = newSpinny("Preprocessing " & destPath.fgWhite, skHearts)
spinner1.setSymbolColor(spinny.fgBlue)
spinner1.start()

let res = execCmd(&"vccexe.exe --platform:amd64 /P /C /Fi\"{destPath}\" " & rspContents & &" /D__midl={midl}")
setCurrentDir(projDir)

if res == 0:
  spinner1.success(&"Generated: {destPath}")
else:
  spinner1.error(&"Could not generate: {destPath}")
  quit(QuitFailure)

# cleanup and formatting
let cppPath = destPath & ".cpp"

var spinner2 = newSpinny("Formatting " & cppPath.fgWhite, skMonkey)
spinner2.setSymbolColor(spinny.fgBlue)
spinner2.start()

var iFile = open(destPath)
proc filterWhiteSpace(lines: seq[string]): seq[string] =
  if hasClangFormat:
    lines
  else:
    lines.filterIt(not isEmptyOrWhiteSpace(it))

try:
  let content = readAll(iFile).split("\n")
    .filterWhiteSpace()
    .filterIt("#pragma once" notin it and "// Copyright" notin it)
    .join("\n")
  close(iFile)

  let cppFile = open(cppPath, fmWrite)
  write(cppFile, content)
  flushFile(cppFile)
  close(cppFile)
  discard tryRemoveFile(destPath)

  if hasClangFormat:
    let clangFormatPath = getAppDir() / "ue.clang-format"
    let formatCmd = clangFormatExe & " --style=file:\"" & clangFormatPath & "\" -i \"" & cppPath & "\""

    let res = execCmd(formatCmd)
    if res == 0:
      spinner2.success("Formatting " & cppPath.fgWhite & " complete!")
    else:
      spinner2.error("Formatting " & cppPath.fgWhite & " failed!")
  else:
    spinner2.success("Formatting " & cppPath.fgWhite & " complete!")
except IOError as e:
  spinner2.error("Formatting " & cppPath.fgWhite & " failed!\n" & e.msg)