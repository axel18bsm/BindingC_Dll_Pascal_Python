H2Pas Converter
    

A Lazarus GUI tool that converts C header files (.h) into ready-to-use Pascal (FPC) or Python (ctypes) binding units — in one click.

What it does
Instead of manually translating each typedef struct, typedef enum, #define, and function prototype from C to Pascal or Python, H2Pas Converter does it automatically:

Pascal mode → generates a complete .pas unit with external declarations and cdecl calling convention
Python mode → generates a .py module with ctypes CDLL, Structure subclasses, and argtypes/restype declarations
Screenshot
┌────────────────────────────────────────────────────────────────────────────┐ │ H2Pas Converter - .h → .pas / .py (cdecl) │ ├────────────────────────────────────────────────────────────────────────────┤ │ File .h: [ mylib.h ▼ ... ] DLL: [ mylib.dll ] Unit: [ uMylibBinding ] │ │ Language: (●) Pascal (FPC) ( ) Python (ctypes) [ CONVERT ] [Clr]│ ├─────────────────────────────┬──────────────────────────────────────────────┤ │ Source .h │ Generated .pas │ │ │ │ │ typedef struct { │ type │ │ int32_t x; │ Circle = record │ │ float radius; │ x : LongInt; │ │ } Circle; │ radius : Single; │ │ │ end; │ │ int32_t __cdecl │ │ │ mylib_add(int32_t a, │ function mylib_add(a: LongInt; │ │ int32_t b); │ b: LongInt): LongInt; cdecl; │ │ │ external 'mylib.dll' name 'mylib_add'; │ ├─────────────────────────────┴──────────────────────────────────────────────┤ │ Log: 2 defines · 1 struct · 1 enum · 1 handle · 5 functions │ └────────────────────────────────────────────────────────────────────────────┘

Features
Automatic type mapping — 26 C types mapped to Pascal / ctypes equivalents
Preprocessor — #define integer, float, and string constants converted
Structs — typedef struct → Pascal record with {$PACKRECORDS C} / Python Structure
Enums — typedef enum → Pascal integer type + constants / Python integer constants
Opaque handles — typedef struct Foo_t* Foo → Pointer / c_void_p
Functions — full external … name … / argtypes + restype output
Pointer params — Circle* → PCircle (Pascal) / POINTER(Circle) (Python)
const char* → PAnsiChar / c_char_p
void return → procedure (Pascal) / restype = None (Python)
Dual output — switch language with a radio button, no restart needed
Save dialog — pre-fills filename and extension from the Unit field
Conversion log — detailed journal of every element processed
Supported C constructs
C construct	Pascal output	Python output
#define FOO 42	const FOO = 42;	FOO = 42
typedef struct { … } Name;	Name = record … end;	class Name(Structure): _fields_ = […]
typedef enum { A=0 } Name;	Name = LongInt; const A=0;	A = 0
typedef struct Foo_t* Foo;	Foo = Pointer;	Foo = c_void_p
int32_t __cdecl fn(…);	function fn(…): LongInt; cdecl; external …	lib.fn.argtypes = […]; lib.fn.restype = c_int32
void __cdecl fn(…);	procedure fn(…); cdecl; external …	lib.fn.restype = None
Getting started
Prerequisites
Tool	Version
Lazarus	4.x (tested 4.6)
Free Pascal Compiler	3.2.x
Windows	64-bit
Build
Clone or download this repository
Open H2PasConverter\H2PasConverter.lpi in Lazarus
Press F9 (Build & Run)
First build: if Lazarus reports a missing .res file, uncomment {$R *.res} in H2PasConverter.lpr after Lazarus has generated it, or leave it commented — the application runs without it.

Usage
Click […] to select a .h file — or paste C code directly into the Source panel
Verify the DLL name (e.g. raylib.dll) and Unit name — auto-filled from the filename
Select the target language: Pascal (FPC) or Python (ctypes)
Click CONVERT
Review the result in the right panel and the log at the bottom
Click Save .pas… / Save .py… to write the file to disk
Example
Input (mylib.h)

```c

define MYLIB_VERSION 200
typedef struct { int32_t x; int32_t y; float radius; } Circle; typedef enum { ERR_OK = 0, ERR_FAIL = 1 } ErrorCode; typedef struct MyHandle_t* MyHandle;

int32_t __cdecl mylib_add(int32_t a, int32_t b); MyHandle __cdecl mylib_open(const char filename); ErrorCode __cdecl mylib_process(MyHandle h, Circle c); void __cdecl mylib_close(MyHandle h); const char* __cdecl mylib_version(void); ```

Pascal output (uMylibBinding.pas)

```pascal unit uMylibBinding; {$mode objfpc}{$H+} {$PACKRECORDS C} interface uses SysUtils;

const MYLIB_VERSION = 200;

type Circle = record x: LongInt; y: LongInt; radius: Single; end; PCircle = ^Circle; ErrorCode = LongInt; MyHandle = Pointer;

const ERR_OK = 0; ERR_FAIL = 1;

function mylib_add(a: LongInt; b: LongInt): LongInt; cdecl; external 'mylib.dll' name 'mylib_add'; function mylib_open(filename: PAnsiChar): Pointer; cdecl; external 'mylib.dll' name 'mylib_open'; function mylib_process(h: Pointer; c: PCircle): LongInt; cdecl; external 'mylib.dll' name 'mylib_process'; procedure mylib_close(h: Pointer); cdecl; external 'mylib.dll' name 'mylib_close'; function mylib_version(): PAnsiChar; cdecl; external 'mylib.dll' name 'mylib_version';

implementation end. ```

Python output (uMylibBinding.py)

```python from ctypes import c_int32, c_float, c_char_p, c_void_p, POINTER, Structure, CDLL lib = CDLL("mylib.dll")

MYLIB_VERSION = 200

class Circle(Structure): fields = [("x", c_int32), ("y", c_int32), ("radius", c_float)]

ERR_OK = 0; ERR_FAIL = 1 MyHandle = c_void_p

lib.mylib_add.argtypes = [c_int32, c_int32]; lib.mylib_add.restype = c_int32 lib.mylib_open.argtypes = [c_char_p]; lib.mylib_open.restype = c_void_p lib.mylib_process.argtypes = [c_void_p, POINTER(Circle)]; lib.mylib_process.restype = c_int32 lib.mylib_close.argtypes = [c_void_p]; lib.mylib_close.restype = None lib.mylib_version.argtypes = []; lib.mylib_version.restype = c_char_p ```

Project structure
H2PasConverter/ ├── H2PasConverter.lpi # Lazarus project file ├── H2PasConverter.lpr # Application entry point ├── uMainForm.pas # GUI form — orchestration ├── uMainForm.lfm # Form layout (LFM) ├── uH2PasConverter.pas # Pascal conversion engine (TH2PasConverter) └── uH2PyConverter.pas # Python conversion engine (TH2PyConverter)

Known limitations
cdecl only — stdcall (Win32 API) functions are not auto-detected; add the keyword manually after generation
Simple macros only — function-like macros (#define MAX(a,b) …) are ignored
No C++ templates or namespaces — pure C headers only
No bitfields in structs
No __attribute__ GCC extensions
Documentation
Document	Language	Contents
H2PasConverter_Documentation.docx	French	User guide · DLL binding course · Technical reference
H2PasConverter_Documentation_EN_Vol1.docx	English	User guide · Technical reference
H2PasConverter_Documentation_EN_Vol2.docx	English	DLL binding course (theory, type tables, examples, pitfalls)
Etape1_Fondamentaux_Binding_DLL.docx	French	DLL binding fundamentals reference
License
MIT — free to use, modify, and distribute.

About
Built as a learning tool for the tutorial series "Learning to Bind a C DLL in Pascal".
Target stack: Free Pascal 3.2 · Lazarus 4.x · Windows 64-bit · cdecl.
