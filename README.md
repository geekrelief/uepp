# Overview
uepp uses the MSVC toolchain with nim to preprocess an Unreal Engine C++ file.

Running the command requires one source file and any include directories need to resolve the headers.

---
## Usage
For example:
```
uepp.exe .\Source\Test\Private\MyActor.cpp .\Source\ .\Intermediate\Build\Win64\UnrealEditor\Inc\Test\
```

Here `MyActor.cpp` will be preprocessed. Its header is in `.\Source\Test\Public\MyActor.h` and the generated.h
is in `.\Intermediate\Build\Win64\UnrealEditor\Inc\Test`.

Note the included directories will be recursively walked and have their sub-directories added to the include path.

The output will appear in a folder named `.\preprocessed` where the command is run.

---
## Configure
Added `uepp`'s directory to your PATH for convenience.

You may need to modify the `ubtflags` to match your paths for the Windows SDK which you can find from
the UBT build log.

You may want the preprocessed file without the `#line` directives or without comments. You can modify the output
in the `preprocesCmd` proc.

`getUEHeadersIncludePaths` may also need to be adjusted if you want to included other Unreal Engine directories.