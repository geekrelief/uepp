# Overview
uepp uses the MSVC toolchain with nim to preprocess an Unreal Engine C++ file.

Running the command requires one response file.

---
## Usage
For example:
```
uepp.exe .\Intermediate\Build\Win64\UnrealEditor\Debug\FP\FP.init.gen.cpp.obj.response
```

Here `FP.init.gen.cpp.obj.response` will be preprocessed.

The output will appear in a folder named `.\preprocessed` where the command is run.

---
## Configure
If you have llvm installed, uepp, will use clang-format to format the output. Based on 
https://github.com/TensorWorks/UE-Clang-Format .clang-format


Modify the nim.cfg for the path to the Unreal Engine's Source folder.

Build with `nimble build`

Added `uepp`'s directory to your PATH for convenience.