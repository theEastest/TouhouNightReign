# Build LuaSTG Sub

The engine source is kept next to this project in `../LuaSTG-Sub-master`.
The build was verified with Visual Studio 2022 installed at `D:\vs` and CMake
`3.31.12` installed at `D:\cmake\CMAKE`.

Open an **x64 Native Tools Command Prompt** or run the following commands in
PowerShell:

```powershell
cmd /c "call D:\vs\Common7\Tools\VsDevCmd.bat -arch=amd64 && set PATH=D:\cmake\CMAKE\bin;%PATH% && cd /d E:\gemesmods\stg\LuaSTG-Sub-master && cmake --preset vs2022-amd64 && cmake --build --preset windows-amd64-release --parallel 4"
```

The same steps split across a regular `cmd.exe` window are:

```bat
call D:\vs\Common7\Tools\VsDevCmd.bat -arch=amd64
set PATH=D:\cmake\CMAKE\bin;%PATH%
cd /d E:\gemesmods\stg\LuaSTG-Sub-master
cmake --preset vs2022-amd64
cmake --build --preset windows-amd64-release --parallel 4
```

The executable is generated at:

```text
E:\gemesmods\stg\LuaSTG-Sub-master\build\amd64\LuaSTG\Release\LuaSTGSub.exe
```

To run the bundled example, set the working directory to
`E:\gemesmods\stg\LuaSTG-Sub-master\data\example` before launching the exe.

## Why the source needed preparation

The distributed source directory did not contain its Git submodule contents.
The `imgui`, `implot`, `xmath`, `lua-cjson`, `image.qoi`, `luajit2`, and
`beautiful-win32-api` directories therefore had to be populated before CMake
could create the LuaJIT targets. CMake also had an incomplete cached
`tinyobjloader` checkout; deleting only that cache entry allowed CPM to fetch
it again.

If the build reports a Git `dubious ownership` error for a dependency, add the
exact dependency directory as a safe directory, for example:

```bat
git config --global --add safe.directory E:/gemesmods/stg/LuaSTG-Sub-master/external/luajit2
```

This checkout also uses the Windows SDK `10.0.22621.0`. The engine's optional
feature-reporting code was adjusted to omit diagnostic enums introduced after
that SDK, and the ImGui binding keeps its obsolete style fields enabled for the
bundled ImGui 1.93 WIP headers. These changes do not alter the renderer or game
runtime.
