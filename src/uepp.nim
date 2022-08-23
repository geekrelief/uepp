# Runs the msvc preprocessor on an Unreal cpp response file
# Thanks to https://github.com/TensorWorks/UE-Clang-Format for the ue.clang-format file

import std / [
os, osproc, sequtils, strformat, strscans, strutils, terminal
]
import spinny
import enums

enableTrueColors()

proc log(msg: string, fgColor: terminal.ForegroundColor = fgWhite) =
  stdout.styledWrite(fgColor, msg & "\n")

proc logError(msg:string) =
  stderr.styledWrite(terminal.fgRed, styleBright, msg & "\n")

const preprocessedDir = "preprocessed"
const UEEngineSrcDir {.strdefine.}: string = ""
const midl {.intdefine.}: int = 0

const ClangMinimumVersion = 14

static:
  doAssert(UEEngineSrcDir.len > 0, "UEEngineDir is undefined in nim.cfg")
  doAssert(dirExists(UEEngineSrcDir))
  doAssert(UEEngineSrcDir.lastPathPart() == "Source", "UEEngineDir path must contain the Source folder.")



let clangFormatExe = findExe("clang-format")
let (hasClangFormat, clangVersion) =
  if clangFormatExe.len > 0:
    # version check
    let verOutStr = execProcess(clangFormatExe & " --version")
    var
      major: int
      minor: int
      revision: int
    var res = verOutStr.scanf("clang-format version $i.$i.$i", major, minor, revision)
    if res:
      (major >= ClangMinimumVersion, &"{major}.{minor}.{revision}")
    else:
      (false, "")
  else:
    (false, "")

if hasClangFormat:
  log(&"Found clang-format version {clangVersion} in {clangFormatExe}", terminal.fgGreen)
  doAssert(fileExists(getAppDir() / "ue.clang-format"))
else:
  if clangVersion.len > 0:
    logError(&"Old clang-format version {clangVersion} in {clangFormatExe}, but needs updating to {ClangMinimumVersion}.")
  else:
    logError(&"clang-format not found or version too old. Using basic cleanup mode.")

let params = commandLineParams()

proc printUsage() =
  log("""Usage: uepp [-with-shadow] response_file
  The response_file contains the source and flags needed to preprocess the source file.
  If the -with-shadow option is used, includes "SharedPCH.Engine.ShadowErrors.h"
  Example: uepp ./TestActor.response
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


# annotate the enums
var spinner3 = newSpinny("Annotating enums" & cppPath.fgWhite, skRunner)
spinner3.start()

var lines: seq[string]
var i:int
for line in cppPath.lines:
  inc i
  lines.add line
  var flagType:string
  var flagValue:int
  if line.strip().scanf("($*)0x$h", flagType, flagValue):
    var flags: Flags = decodeEnumValue(flagType, flagValue)
    if flags.len > 0:
      var names: string = flags.mapIt(it.name).join(" | ")
      var desc: string = flags.mapIt(it.name & ": " & it.description).join("\n")
      lines.add &"/*\n({flagType}){flagValue:#X} = {names}\n{desc}\n*/"
      i = i + 4 + flags.len
    else:
      logError(&"Unable to decode: {line} {i} {flagType} {flagValue}")

let cppFile = open(cppPath, fmWrite)
write(cppFile, lines.join("\n"))
flushFile(cppFile)
close(cppFile)
spinner3.success("Annotating complete!")