# H2Pas Converter

A Lazarus GUI tool that converts C header files (.h) into ready-to-use Pascal (FPC) or Python (ctypes) binding units — **in one click**.

## Table of Contents
- [What It Does](#what-it-does)
- [Features](#features)
- [Supported C Constructs](#supported-c-constructs)
- [Prerequisites](#prerequisites)
- [Build from Source](#build-from-source)
- [First Run](#first-run)
- [Usage](#usage)
- [Example](#example)
- [Project Structure](#project-structure)
- [Known Limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)
- [About](#about)

## What It Does

Instead of manually translating each `typedef struct`, `typedef enum`, `#define`, and function prototype from C to Pascal or Python, H2Pas Converter does it **automatically**:

- **Pascal mode** → generates a complete `.pas` unit with external declarations and `cdecl` calling convention
- **Python mode** → generates a `.py` module with `ctypes` CDLL, Structure subclasses, and `argtypes`/`restype` declarations

## Features

✅ **Automatic type mapping** — 26 C types mapped to Pascal / ctypes equivalents  
✅ **Preprocessor** — `#define` integer, float, and string constants converted  
✅ **Structs** — `typedef struct` → Pascal record with `{$PACKRECORDS C}` / Python Structure  
✅ **Enums** — `typedef enum` → Pascal integer type + constants / Python integer constants  
✅ **Opaque handles** — `typedef struct Foo_t* Foo` → Pointer / c_void_p  
✅ **Functions** — full `external … name …` / `argtypes + restype` output  
✅ **Pointer params** — `Circle*` → `PCircle` (Pascal) / `POINTER(Circle)` (Python)  
✅ **const char*** → `PAnsiChar` / `c_char_p`  
✅ **void return** → `procedure` (Pascal) / `restype = None` (Python)  
✅ **Dual output** — switch language with a radio button, no restart needed  
✅ **Save dialog** — pre-fills filename and extension from the Unit field  
✅ **Conversion log** — detailed journal of every element processed

## Supported C Constructs

| C Construct | Pascal Output | Python Output |
|---|---|---|
| `#define FOO 42` | `const FOO = 42;` | `FOO = 42` |
| `typedef struct { … } Name;` | `Name = record … end;` | `class Name(Structure): _fields_ = […]` |
| `typedef enum { A=0 } Name;` | `Name = LongInt; const A=0;` | `A = 0` |
| `typedef struct Foo_t* Foo;` | `Foo = Pointer;` | `Foo = c_void_p` |
| `int32_t __cdecl fn(…);` | `function fn(…): LongInt; cdecl; external …` | `lib.fn.argtypes = […]; lib.fn.fn.restype = c_int32` |
| `void __cdecl fn(…);` | `procedure fn(…); cdecl; external …` | `lib.fn.restype = None` |

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| **Lazarus** | 4.x (tested 4.6) | IDE for development and UI design |
| **Free Pascal Compiler** | 3.2.x | Compiler for Pascal code |
| **Windows** | 64-bit | Target operating system |
| **RAM** | 2GB minimum | For comfortable development |

## Build from Source

1. **Clone or download** this repository:
   ```bash
   git clone https://github.com/axel18bsm/BindingC_Dll_Pascal_Python.git
   cd BindingC_Dll_Pascal_Python
   ```

2. **Open the project** in Lazarus:
   - Open `H2PasConverter\H2PasConverter.lpi` in Lazarus IDE

3. **Build & Run**:
   - Press `F9` or go to **Run → Build & Run**

4. **First Build Notes**:
   - If Lazarus reports a missing `.res` file:
     - Either: uncomment `{$R *.res}` in `H2PasConverter.lpr` after Lazarus generates it
     - Or: leave it commented — the application runs without it

## First Run

1. The application window will open with three main panels:
   - **Left panel**: C header file input (browse or paste code)
   - **Center panel**: Settings (DLL name, Unit name, target language)
   - **Right panel**: Generated output code
   - **Bottom panel**: Conversion log

## Usage

1. **Load a C header file**:
   - Click `[…]` to browse for a `.h` file, or paste C code directly into the Source panel

2. **Configure binding settings**:
   - Verify the **DLL name** (e.g., `raylib.dll`)
   - Verify the **Unit name** (auto-filled from filename)

3. **Select target language**:
   - Choose **Pascal (FPC)** or **Python (ctypes)**

4. **Generate bindings**:
   - Click **CONVERT**

5. **Review output**:
   - Check the result in the right panel
   - Review the log at the bottom for any warnings or errors

6. **Save the file**:
   - Click **Save .pas…** (for Pascal) or **Save .py…** (for Python) to write to disk

## Example

### Input (mylib.h)

```c
#define MYLIB_VERSION 200

typedef struct {
    int32_t x;
    int32_t y;
    float radius;
} Circle;

typedef enum {
    ERR_OK = 0,
    ERR_FAIL = 1
} ErrorCode;

typedef struct MyHandle_t* MyHandle;

int32_t __cdecl mylib_add(int32_t a, int32_t b);
MyHandle __cdecl mylib_open(const char *filename);
ErrorCode __cdecl mylib_process(MyHandle h, Circle c);
void __cdecl mylib_close(MyHandle h);
```

### Pascal Output (uMylibBinding.pas)

```pascal
unit uMylibBinding;

{$mode objfpc}{$H+}
{$PACKRECORDS C}

interface

uses
  SysUtils;

const
  MYLIB_VERSION = 200;

type
  Circle = record
    x: LongInt;
    y: LongInt;
    radius: Single;
  end;
  PCircle = ^Circle;

  ErrorCode = LongInt;
  MyHandle = Pointer;

const
  ERR_OK = 0;
  ERR_FAIL = 1;

function mylib_add(a: LongInt; b: LongInt): LongInt; cdecl;
  external 'mylib.dll' name 'mylib_add';

function mylib_open(filename: PAnsiChar): Pointer; cdecl;
  external 'mylib.dll' name 'mylib_open';

function mylib_process(h: Pointer; c: Circle): LongInt; cdecl;
  external 'mylib.dll' name 'mylib_process';

procedure mylib_close(h: Pointer); cdecl;
  external 'mylib.dll' name 'mylib_close';

implementation

end.
```

### Python Output (mylib.py)

```python
from ctypes import c_int32, c_float, c_char_p, c_void_p, POINTER, Structure, CDLL

lib = CDLL("mylib.dll")

MYLIB_VERSION = 200

class Circle(Structure):
    _fields_ = [("x", c_int32), ("y", c_int32), ("radius", c_float)]

ERR_OK = 0
ERR_FAIL = 1

MyHandle = c_void_p

lib.mylib_add.argtypes = [c_int32, c_int32]
lib.mylib_add.restype = c_int32

lib.mylib_open.argtypes = [c_char_p]
lib.mylib_open.restype = c_void_p

lib.mylib_process.argtypes = [c_void_p, Circle]
lib.mylib_process.restype = c_int32

lib.mylib_close.argtypes = [c_void_p]
lib.mylib_close.restype = None
```

## Project Structure

```
H2PasConverter/
├── H2PasConverter.lpi           # Lazarus project file
├── H2PasConverter.lpr           # Application entry point
├── uMainForm.pas                # GUI form — orchestration
├── uMainForm.lfm                # GUI form design
├── uCHeaderParser.pas           # C header parsing logic
├── uTypeMapper.pas              # C → Pascal/Python type mapping
├── uPascalGenerator.pas         # Pascal code generation
├── uPythonGenerator.pas         # Python code generation
└── README.md                    # This file
```

## Known Limitations

⚠️ **cdecl only** — `stdcall` (Win32 API) functions are not auto-detected; add the keyword manually after generation  
⚠️ **Simple macros only** — function-like macros (`#define MAX(a,b) …`) are ignored  
⚠️ **No C++ templates** — pure C headers only (no C++ templates or namespaces)  
⚠️ **No bitfields** — bitfield structs are not supported  
⚠️ **No GCC extensions** — `__attribute__` and other compiler-specific extensions not supported

## Troubleshooting

### Issue: "Cannot find Lazarus project file"
**Solution**: Ensure you extracted all files correctly and the `.lpi` file exists in the `H2PasConverter` directory.

### Issue: "Missing .res file on first build"
**Solution**: 
- Let Lazarus auto-generate the `.res` file
- Or uncomment `{$R *.res}` in `H2PasConverter.lpr`
- The application works fine without it

### Issue: "DLL not found at runtime"
**Solution**:
- Ensure the DLL file path is correct and the DLL exists
- Copy the DLL to the same directory as your generated binding unit
- Or provide the full path in the binding unit's `external` declaration

### Issue: "Type mapping is incorrect"
**Solution**:
- Check the conversion log in the bottom panel for warnings
- Verify the C header syntax is correct
- Report any issues on GitHub with the problematic C code

### Issue: "Generated code won't compile in Pascal"
**Solution**:
- Check that Free Pascal 3.2.x is installed and in your PATH
- Verify all referenced units (like `SysUtils`) exist
- For linking issues, ensure `{$PACKRECORDS C}` is present

### Issue: "Python module import fails"
**Solution**:
- Ensure `ctypes` is available (included in Python stdlib)
- Check that the DLL path in `CDLL("…")` is correct
- Verify the DLL architecture matches your Python installation (32-bit or 64-bit)

## Documentation

| Document | Language | Contents |
|---|---|---|
| H2PasConverter_Documentation.docx | French | User guide · DLL binding course · Technical reference |
| H2PasConverter_Documentation_EN_Vol1.docx | English | User guide · Technical reference |
| H2PasConverter_Documentation_EN_Vol2.docx | English | DLL binding course (theory, type tables, examples, pitfalls) |
| Etape1_Fondamentaux_Binding_DLL.docx | French | DLL binding fundamentals reference |

## Contributing

We welcome contributions! To contribute:

1. **Fork** the repository
2. **Create a feature branch**: `git checkout -b feature/my-improvement`
3. **Make your changes** and test thoroughly
4. **Commit** with clear messages: `git commit -m "Add support for …"`
5. **Push** to your fork: `git push origin feature/my-improvement`
6. **Open a Pull Request** with a clear description

### Reporting Bugs

If you find a bug:
1. Check if it's already reported in Issues
2. Create a new issue with:
   - Your C header file (or example)
   - Expected vs. actual output
   - Your Lazarus/FPC versions
   - Steps to reproduce

## License

MIT — free to use, modify, and distribute.

## About

Built as a learning tool for the tutorial series **"Learning to Bind a C DLL in Pascal"**.

**Target stack**: Free Pascal 3.2 · Lazarus 4.x · Windows 64-bit · cdecl calling convention
