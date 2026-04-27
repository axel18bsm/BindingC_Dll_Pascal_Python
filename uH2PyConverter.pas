unit uH2PyConverter;

(*
  ============================================================
  H2Py Converter -- Moteur de conversion .h -> binding Python ctypes
  Cible : Python 3.x + ctypes
  Convention d'appel : cdecl (CDLL)
  ============================================================

  Gere :
    - Typedefs simples
    - Structs  (typedef struct ... MonStruct;)  -> class MonStruct(Structure)
    - Enums    (typedef enum  ... MonEnum;)     -> constantes Python
    - Handles opaques                           -> c_void_p
    - Prototypes de fonctions                   -> argtypes + restype
    - #define constants numeriques              -> constantes Python
*)

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils;

type
  TH2PyConverter = class
  private
    FDLLName  : string;
    FLog      : TStringList;

    function  StripComments(const src: string): string;
    function  StripPreprocessorBlocks(const src: string): string;
    function  NormalizeSpaces(const src: string): string;

    function  MapCTypeToPython(const ctype: string): string;
    function  MapCTypeToRestype(const ctype: string): string;

    function  ParseDefines(const src: string): string;
    function  ParseStructsAndEnums(const src: string): string;
    function  ParseStructBody(const body, structName: string): string;
    function  ParseEnumBody(const body: string): string;
    function  ParseFunctions(const src: string): string;
    function  ParseOneFunction(const proto: string): string;
    function  ParseArgTypes(const paramStr: string): string;

    function  ExtractBetweenBraces(const src: string; startPos: Integer; out endPos: Integer): string;
    function  SplitParams(const s: string): TStringList;
    function  CleanIdent(const s: string): string;
    procedure Log(const msg: string);

  public
    constructor Create;
    destructor  Destroy; override;

    function Convert(const headerSource: string;
                     const aDllName: string): string;

    property ConversionLog: TStringList read FLog;
  end;

implementation

constructor TH2PyConverter.Create;
begin
  inherited Create;
  FLog := TStringList.Create;
end;

destructor TH2PyConverter.Destroy;
begin
  FLog.Free;
  inherited Destroy;
end;

procedure TH2PyConverter.Log(const msg: string);
begin
  FLog.Add(msg);
end;

(* ── Correspondance des types C -> Python ctypes ────────────── *)

function TH2PyConverter.MapCTypeToPython(const ctype: string): string;
(* Retourne le type ctypes Python pour un type C donne.
   Utilise pour les champs de Structure et les argtypes. *)
var
  normalized : string;
  isPtr      : Boolean;
  base       : string;
  pyBase     : string;
begin
  normalized := Trim(LowerCase(ctype));

  if Copy(normalized, 1, 6) = 'const ' then
    normalized := Trim(Copy(normalized, 7, MaxInt));

  normalized := StringReplace(normalized, ' *', '*', [rfReplaceAll]);
  normalized := StringReplace(normalized, '* ', '*', [rfReplaceAll]);

  isPtr := (Length(normalized) > 0) and (normalized[Length(normalized)] = '*');
  if isPtr then
    base := Trim(Copy(normalized, 1, Length(normalized) - 1))
  else
    base := normalized;

  // Cas speciaux avec pointeur
  if isPtr then
  begin
    if base = 'char'    then begin Result := 'c_char_p';  Exit; end;
    if base = 'wchar_t' then begin Result := 'c_wchar_p'; Exit; end;
    if (base = 'void') or (base = '') then begin Result := 'c_void_p'; Exit; end;
  end;

  // Table de correspondance
  pyBase := '';
  if      base = 'void'               then pyBase := 'None'
  else if base = 'bool'               then pyBase := 'c_bool'
  else if base = '_bool'              then pyBase := 'c_bool'
  else if base = 'int8_t'             then pyBase := 'c_int8'
  else if base = 'int16_t'            then pyBase := 'c_int16'
  else if base = 'int32_t'            then pyBase := 'c_int32'
  else if base = 'int64_t'            then pyBase := 'c_int64'
  else if base = 'uint8_t'            then pyBase := 'c_uint8'
  else if base = 'uint16_t'           then pyBase := 'c_uint16'
  else if base = 'uint32_t'           then pyBase := 'c_uint32'
  else if base = 'uint64_t'           then pyBase := 'c_uint64'
  else if base = 'signed char'        then pyBase := 'c_int8'
  else if base = 'unsigned char'      then pyBase := 'c_uint8'
  else if base = 'char'               then pyBase := 'c_char'
  else if base = 'wchar_t'            then pyBase := 'c_wchar'
  else if base = 'short'              then pyBase := 'c_short'
  else if base = 'short int'          then pyBase := 'c_short'
  else if base = 'unsigned short'     then pyBase := 'c_ushort'
  else if base = 'unsigned short int' then pyBase := 'c_ushort'
  else if base = 'int'                then pyBase := 'c_int'
  else if base = 'signed int'         then pyBase := 'c_int'
  else if base = 'signed'             then pyBase := 'c_int'
  else if base = 'unsigned int'       then pyBase := 'c_uint'
  else if base = 'unsigned'           then pyBase := 'c_uint'
  else if base = 'long'               then pyBase := 'c_long'
  else if base = 'long int'           then pyBase := 'c_long'
  else if base = 'signed long'        then pyBase := 'c_long'
  else if base = 'unsigned long'      then pyBase := 'c_ulong'
  else if base = 'unsigned long int'  then pyBase := 'c_ulong'
  else if base = 'long long'          then pyBase := 'c_int64'
  else if base = 'long long int'      then pyBase := 'c_int64'
  else if base = 'signed long long'   then pyBase := 'c_int64'
  else if base = 'unsigned long long' then pyBase := 'c_uint64'
  else if base = 'float'              then pyBase := 'c_float'
  else if base = 'double'             then pyBase := 'c_double'
  else if base = 'long double'        then pyBase := 'c_longdouble'
  else if base = 'size_t'             then pyBase := 'c_size_t'
  else if base = 'ssize_t'            then pyBase := 'c_ssize_t'
  else if base = 'ptrdiff_t'          then pyBase := 'c_ssize_t'
  else if base = 'intptr_t'           then pyBase := 'c_ssize_t'
  else if base = 'uintptr_t'          then pyBase := 'c_size_t'
  else if base = 'bool'               then pyBase := 'c_int'
  else if base = 'byte'               then pyBase := 'c_uint8'
  else if base = 'word'               then pyBase := 'c_uint16'
  else if base = 'dword'              then pyBase := 'c_uint32'
  else if base = 'qword'              then pyBase := 'c_uint64'
  else if base = 'handle'             then pyBase := 'c_void_p'
  else if base = 'hwnd'               then pyBase := 'c_void_p'
  else if base = 'lpvoid'             then pyBase := 'c_void_p'
  else if base = 'lpcstr'             then pyBase := 'c_char_p'
  else if base = 'lpstr'              then pyBase := 'c_char_p'
  else if base = 'lpcwstr'            then pyBase := 'c_wchar_p'
  else if base = 'lpwstr'             then pyBase := 'c_wchar_p';

  if pyBase <> '' then
  begin
    if isPtr then
      Result := 'POINTER(' + pyBase + ')'
    else
      Result := pyBase;
    Exit;
  end;

  if base = 'void' then
  begin
    Result := 'None';
    Exit;
  end;

  // Type custom (struct, handle) -> utiliser le nom tel quel
  Result := CleanIdent(base);
  if isPtr then
    Result := 'POINTER(' + Result + ')';

  Log('  [WARN] Type non reconnu : "' + ctype + '" -> ' + Result);
end;

function TH2PyConverter.MapCTypeToRestype(const ctype: string): string;
(* Comme MapCTypeToPython mais void -> None pour restype *)
begin
  if Trim(LowerCase(ctype)) = 'void' then
    Result := 'None'
  else
    Result := MapCTypeToPython(ctype);
end;

(* ── Nettoyage identique au moteur Pascal ───────────────────── *)

function TH2PyConverter.StripComments(const src: string): string;
var
  i, n : Integer;
  res  : TStringBuilder;
  inML : Boolean;
begin
  res  := TStringBuilder.Create;
  n    := Length(src);
  i    := 1;
  inML := False;
  try
    while i <= n do
    begin
      if inML then
      begin
        if (src[i] = '*') and (i < n) and (src[i+1] = '/') then
        begin
          inML := False;
          Inc(i, 2);
        end
        else begin
          if src[i] = #10 then res.Append(#10);
          Inc(i);
        end;
      end
      else begin
        if (src[i] = '/') and (i < n) and (src[i+1] = '*') then
        begin
          inML := True;
          Inc(i, 2);
        end
        else if (src[i] = '/') and (i < n) and (src[i+1] = '/') then
        begin
          while (i <= n) and (src[i] <> #10) do Inc(i);
        end
        else begin
          res.Append(src[i]);
          Inc(i);
        end;
      end;
    end;
    Result := res.ToString;
  finally
    res.Free;
  end;
end;

function TH2PyConverter.StripPreprocessorBlocks(const src: string): string;
var
  lines  : TStringList;
  i      : Integer;
  line   : string;
  trimmed: string;
  res    : TStringList;
begin
  lines := TStringList.Create;
  res   := TStringList.Create;
  try
    lines.Text := src;
    for i := 0 to lines.Count - 1 do
    begin
      line    := lines[i];
      trimmed := Trim(line);
      if (Length(trimmed) > 0) and (trimmed[1] = '#') then
      begin
        if Copy(trimmed, 1, 7) = '#define' then
          res.Add(line)
        else
          res.Add('');
      end
      else
        res.Add(line);
    end;
    Result := res.Text;
  finally
    lines.Free;
    res.Free;
  end;
end;

function TH2PyConverter.NormalizeSpaces(const src: string): string;
var
  i   : Integer;
  res : TStringBuilder;
  c   : Char;
  prev: Char;
begin
  res  := TStringBuilder.Create;
  prev := ' ';
  try
    for i := 1 to Length(src) do
    begin
      c := src[i];
      if c in [#9, #13] then c := ' ';
      if (c = ' ') and (prev = ' ') then Continue;
      res.Append(c);
      prev := c;
    end;
    Result := res.ToString;
  finally
    res.Free;
  end;
end;

(* ── Utilitaires ────────────────────────────────────────────── *)

function TH2PyConverter.CleanIdent(const s: string): string;
var
  i   : Integer;
  res : TStringBuilder;
  c   : Char;
begin
  res := TStringBuilder.Create;
  try
    for i := 1 to Length(s) do
    begin
      c := s[i];
      if c in ['A'..'Z', 'a'..'z', '0'..'9', '_'] then
        res.Append(c)
      else if c = ' ' then
        { skip }
      else
        res.Append('_');
    end;
    Result := res.ToString;
  finally
    res.Free;
  end;
end;

function TH2PyConverter.ExtractBetweenBraces(const src: string; startPos: Integer; out endPos: Integer): string;
var
  i, depth: Integer;
  res     : TStringBuilder;
begin
  res   := TStringBuilder.Create;
  depth := 0;
  i     := startPos;
  try
    while i <= Length(src) do
    begin
      if src[i] = '{' then
      begin
        Inc(depth);
        if depth > 1 then res.Append(src[i]);
      end
      else if src[i] = '}' then
      begin
        Dec(depth);
        if depth = 0 then
        begin
          endPos := i;
          Result := res.ToString;
          Exit;
        end
        else
          res.Append(src[i]);
      end
      else
        res.Append(src[i]);
      Inc(i);
    end;
    endPos := i;
    Result := res.ToString;
  finally
    res.Free;
  end;
end;

function TH2PyConverter.SplitParams(const s: string): TStringList;
var
  depth : Integer;
  i     : Integer;
  cur   : TStringBuilder;
  c     : Char;
begin
  Result := TStringList.Create;
  cur    := TStringBuilder.Create;
  depth  := 0;
  try
    for i := 1 to Length(s) do
    begin
      c := s[i];
      if c in ['(', '<', '['] then Inc(depth)
      else if c in [')', '>', ']'] then Dec(depth);
      if (c = ',') and (depth = 0) then
      begin
        Result.Add(Trim(cur.ToString));
        cur.Clear;
      end
      else
        cur.Append(c);
    end;
    if Trim(cur.ToString) <> '' then
      Result.Add(Trim(cur.ToString));
  finally
    cur.Free;
  end;
end;

(* ── Parseur #define ────────────────────────────────────────── *)

function TH2PyConverter.ParseDefines(const src: string): string;
var
  lines  : TStringList;
  line   : string;
  parts  : TStringList;
  name   : string;
  value  : string;
  res    : TStringList;
  i      : Integer;
  isNum  : Boolean;
  c      : Char;
begin
  lines  := TStringList.Create;
  res    := TStringList.Create;
  parts  := TStringList.Create;
  try
    lines.Text := src;
    for i := 0 to lines.Count - 1 do
    begin
      line := Trim(lines[i]);
      if Copy(line, 1, 7) <> '#define' then Continue;

      line  := Trim(Copy(line, 8, MaxInt));
      parts.Clear;
      parts.Delimiter       := ' ';
      parts.StrictDelimiter := True;
      parts.DelimitedText   := line;

      if parts.Count < 2 then Continue;
      name  := Trim(parts[0]);
      value := Trim(Copy(line, Length(name) + 2, MaxInt));

      // Supprimer suffixes numeriques C
      value := StringReplace(value, 'u', '', [rfIgnoreCase]);
      value := StringReplace(value, 'l', '', [rfIgnoreCase]);
      value := StringReplace(value, 'f', '', []);

      isNum := Length(value) > 0;
      for c in value do
        if not (c in ['0'..'9', 'a'..'f', 'A'..'F', 'x', 'X', '-', '+', '.']) then
        begin
          isNum := False;
          Break;
        end;

      if isNum and (Length(name) > 0) then
      begin
        // Hex : 0x reste 0x en Python
        res.Add(name + ' = ' + value);
        Log('  #define -> ' + name + ' = ' + value);
      end;
    end;
    Result := res.Text;
  finally
    lines.Free;
    res.Free;
    parts.Free;
  end;
end;

(* ── Parseur structs / enums ────────────────────────────────── *)

function TH2PyConverter.ParseStructBody(const body, structName: string): string;
var
  lines    : TStringList;
  line     : string;
  i        : Integer;
  parts    : TStringList;
  ctype    : string;
  fieldName: string;
  pyType   : string;
  res      : TStringList;
  isArr    : Boolean;
  arrSize  : string;
  p        : Integer;
begin
  lines := TStringList.Create;
  res   := TStringList.Create;
  parts := TStringList.Create;
  try
    lines.Text := StringReplace(body, ';', ';'#10, [rfReplaceAll]);

    for i := 0 to lines.Count - 1 do
    begin
      line := Trim(lines[i]);
      if line = '' then Continue;
      if (Length(line) > 0) and (line[Length(line)] = ';') then
        line := Trim(Copy(line, 1, Length(line) - 1));
      if line = '' then Continue;

      isArr   := False;
      arrSize := '';
      p := Pos('[', line);
      if p > 0 then
      begin
        isArr   := True;
        arrSize := Trim(Copy(line, p + 1, Pos(']', line) - p - 1));
        line    := Trim(Copy(line, 1, p - 1));
      end;

      parts.Clear;
      parts.Delimiter       := ' ';
      parts.StrictDelimiter := True;
      parts.DelimitedText   := Trim(line);

      if parts.Count < 2 then Continue;

      fieldName := Trim(parts[parts.Count - 1]);
      if (Length(fieldName) > 0) and (fieldName[1] = '*') then
      begin
        fieldName := Copy(fieldName, 2, MaxInt);
        ctype     := Trim(Copy(line, 1, Length(line) - Length(fieldName))) + '*';
      end
      else
        ctype := Trim(Copy(line, 1, Length(line) - Length(fieldName)));

      fieldName := CleanIdent(fieldName);
      if fieldName = '' then Continue;

      pyType := MapCTypeToPython(ctype);

      if isArr then
        res.Add('        ("' + fieldName + '", ' + pyType + ' * ' + arrSize + '),')
      else
        res.Add('        ("' + fieldName + '", ' + pyType + '),');
    end;
    Result := res.Text;
  finally
    lines.Free;
    res.Free;
    parts.Free;
  end;
end;

function TH2PyConverter.ParseEnumBody(const body: string): string;
var
  items   : TStringList;
  item    : string;
  i       : Integer;
  eqPos   : Integer;
  eName   : string;
  eVal    : string;
  counter : Integer;
  res     : TStringList;
begin
  items   := SplitParams(body);
  res     := TStringList.Create;
  counter := 0;
  try
    for i := 0 to items.Count - 1 do
    begin
      item := Trim(items[i]);
      if item = '' then Continue;

      eqPos := Pos('=', item);
      if eqPos > 0 then
      begin
        eName := Trim(Copy(item, 1, eqPos - 1));
        eVal  := Trim(Copy(item, eqPos + 1, MaxInt));
        eVal  := StringReplace(eVal, '0x', '0x', [rfIgnoreCase]);
        try
          counter := StrToInt(eVal);
        except
        end;
      end
      else
      begin
        eName := item;
        eVal  := IntToStr(counter);
      end;

      eName := CleanIdent(eName);
      if eName <> '' then
        res.Add(eName + ' = ' + eVal);
      Inc(counter);
    end;
    Result := res.Text;
  finally
    items.Free;
    res.Free;
  end;
end;

function TH2PyConverter.ParseStructsAndEnums(const src: string): string;
var
  i        : Integer;
  p        : Integer;
  keyword  : string;
  body     : string;
  afterName: string;
  typeName : string;
  endPos   : Integer;
  res      : TStringList;
  lowSrc   : string;
  isOpaque : Boolean;
begin
  res    := TStringList.Create;
  lowSrc := LowerCase(src);
  try
    i := 1;
    while i <= Length(src) do
    begin
      p := PosEx('typedef', lowSrc, i);
      if p = 0 then Break;

      keyword := Trim(Copy(src, p + 7, 30));

      // struct
      if (Copy(keyword, 1, 6) = 'struct') or (Copy(keyword, 1, 5) = 'union') then
      begin
        // Handle opaque : typedef struct Foo_t* FooHandle;
        isOpaque := False;
        if Pos('{', Copy(src, p, 80)) = 0 then
        begin
          afterName := Trim(Copy(src, p + 7, 200));
          if Pos('*', afterName) > 0 then
          begin
            typeName := Trim(afterName);
            typeName := Trim(Copy(typeName, Pos('*', typeName) + 1, MaxInt));
            endPos   := Pos(';', typeName);
            if endPos > 0 then typeName := Trim(Copy(typeName, 1, endPos - 1));
            typeName := CleanIdent(typeName);
            if typeName <> '' then
            begin
              res.Add('# Handle opaque');
              res.Add(typeName + ' = c_void_p');
              res.Add('');
              Log('  Handle opaque : ' + typeName + ' = c_void_p');
              isOpaque := True;
            end;
          end;
          i := PosEx(';', src, p) + 1;
          if i <= 0 then Break;
          Continue;
        end;

        p := PosEx('{', src, p);
        if p = 0 then begin Inc(i); Continue; end;

        body := ExtractBetweenBraces(src, p, endPos);

        afterName := Trim(Copy(src, endPos + 1, 100));
        p         := Pos(';', afterName);
        if p > 0 then afterName := Trim(Copy(afterName, 1, p - 1));
        typeName  := CleanIdent(afterName);

        if typeName <> '' then
        begin
          res.Add('class ' + typeName + '(Structure):');
          res.Add('    _fields_ = [');
          res.Add(TrimRight(ParseStructBody(body, typeName)));
          res.Add('    ]');
          res.Add('');
          Log('  struct -> class ' + typeName + '(Structure)');
        end;

        i := endPos + 1;
      end

      // enum
      else if Copy(keyword, 1, 4) = 'enum' then
      begin
        p := PosEx('{', src, p);
        if p = 0 then begin Inc(i); Continue; end;

        body := ExtractBetweenBraces(src, p, endPos);

        afterName := Trim(Copy(src, endPos + 1, 100));
        p         := Pos(';', afterName);
        if p > 0 then afterName := Trim(Copy(afterName, 1, p - 1));
        typeName  := CleanIdent(afterName);

        if typeName <> '' then
        begin
          res.Add('# Enum ' + typeName);
          res.Add(TrimRight(ParseEnumBody(body)));
          res.Add('');
          Log('  enum -> constantes Python');
        end;

        i := endPos + 1;
      end

      // typedef simple
      else
      begin
        endPos := PosEx(';', src, p);
        if endPos = 0 then begin Inc(i); Continue; end;
        i := endPos + 1;
      end;

      lowSrc := LowerCase(src);
    end;
    Result := res.Text;
  finally
    res.Free;
  end;
end;

(* ── Parseur fonctions ──────────────────────────────────────── *)

function TH2PyConverter.ParseArgTypes(const paramStr: string): string;
var
  params  : TStringList;
  i       : Integer;
  param   : string;
  parts   : TStringList;
  ctype   : string;
  pname   : string;
  pyType  : string;
  res     : TStringList;
begin
  Result := '';
  if Trim(paramStr) = '' then Exit;
  if LowerCase(Trim(paramStr)) = 'void' then Exit;

  params := SplitParams(paramStr);
  res    := TStringList.Create;
  parts  := TStringList.Create;
  try
    for i := 0 to params.Count - 1 do
    begin
      param := Trim(params[i]);
      if (param = '') or (param = '...') then Continue;
      if LowerCase(param) = 'void' then Continue;

      parts.Clear;
      parts.Delimiter       := ' ';
      parts.StrictDelimiter := True;
      parts.DelimitedText   := param;

      if parts.Count = 0 then Continue;
      if parts.Count = 1 then
        ctype := parts[0]
      else
      begin
        pname := Trim(parts[parts.Count - 1]);
        if (Length(pname) > 0) and (pname[1] = '*') then
        begin
          pname := Copy(pname, 2, MaxInt);
          ctype := Trim(Copy(param, 1, Length(param) - Length(pname))) + '*';
        end
        else
          ctype := Trim(Copy(param, 1, Length(param) - Length(pname)));
      end;

      pyType := MapCTypeToPython(ctype);
      res.Add(pyType);
    end;

    Result := '';
    for i := 0 to res.Count - 1 do
    begin
      if i > 0 then Result := Result + ', ';
      Result := Result + res[i];
    end;
  finally
    params.Free;
    res.Free;
    parts.Free;
  end;
end;

function TH2PyConverter.ParseOneFunction(const proto: string): string;
var
  p        : Integer;
  retCtype : string;
  funcName : string;
  paramStr : string;
  argTypes : string;
  resType  : string;
  cleaned  : string;
  lastWord : Integer;
begin
  Result  := '';
  cleaned := Trim(proto);

  cleaned := StringReplace(cleaned, '__declspec(dllexport)', '', [rfIgnoreCase]);
  cleaned := StringReplace(cleaned, '__declspec(dllimport)', '', [rfIgnoreCase]);
  cleaned := StringReplace(cleaned, '__cdecl',   '', [rfReplaceAll, rfIgnoreCase]);
  cleaned := StringReplace(cleaned, 'CDECL',     '', [rfReplaceAll]);
  cleaned := StringReplace(cleaned, '__stdcall', '', [rfReplaceAll, rfIgnoreCase]);
  cleaned := StringReplace(cleaned, 'WINAPI',    '', [rfReplaceAll]);
  cleaned := StringReplace(cleaned, 'APIENTRY',  '', [rfReplaceAll]);
  cleaned := StringReplace(cleaned, 'CALLBACK',  '', [rfReplaceAll]);
  cleaned := StringReplace(cleaned, 'extern',    '', [rfReplaceAll, rfIgnoreCase]);
  cleaned := StringReplace(cleaned, 'DLL_API',   '', [rfReplaceAll]);
  cleaned := StringReplace(cleaned, 'API',       '', [rfReplaceAll]);
  cleaned := NormalizeSpaces(Trim(cleaned));

  p := Pos('(', cleaned);
  if p = 0 then Exit;

  paramStr := Copy(cleaned, p + 1, Length(cleaned) - p - 1);
  if (Length(paramStr) > 0) and (paramStr[Length(paramStr)] = ')') then
    paramStr := Copy(paramStr, 1, Length(paramStr) - 1);
  paramStr := Trim(paramStr);

  cleaned  := Trim(Copy(cleaned, 1, p - 1));
  lastWord := LastDelimiter(' *', cleaned);
  if lastWord = 0 then Exit;

  funcName := Trim(Copy(cleaned, lastWord + 1, MaxInt));
  retCtype := Trim(Copy(cleaned, 1, lastWord - 1));

  if funcName = '' then Exit;

  argTypes := ParseArgTypes(paramStr);
  resType  := MapCTypeToRestype(retCtype);

  // Generer les 2 lignes Python
  if argTypes <> '' then
    Result := 'lib.' + funcName + '.argtypes = [' + argTypes + ']' + #10 +
              'lib.' + funcName + '.restype  = ' + resType
  else
    Result := 'lib.' + funcName + '.argtypes = []' + #10 +
              'lib.' + funcName + '.restype  = ' + resType;

  Log('  fonction -> lib.' + funcName);
end;

function TH2PyConverter.ParseFunctions(const src: string): string;
var
  i        : Integer;
  p, p2    : Integer;
  proto    : string;
  pyDecl   : string;
  res      : TStringList;
  funcName : string;
  depth    : Integer;
  lowSrc   : string;
begin
  res    := TStringList.Create;
  lowSrc := LowerCase(src);
  try
    i := 1;
    while i <= Length(src) do
    begin
      p := PosEx('(', src, i);
      if p = 0 then Break;

      p2    := p;
      depth := 0;
      while p2 > 1 do
      begin
        Dec(p2);
        if src[p2] = '}' then Inc(depth);
        if src[p2] = '{' then
        begin
          if depth = 0 then Break;
          Dec(depth);
        end;
        if src[p2] = ';' then Break;
      end;
      if (p2 > 1) and (src[p2] = '{') then
      begin
        Inc(i);
        Continue;
      end;

      depth := 1;
      p2    := p + 1;
      while (p2 <= Length(src)) and (depth > 0) do
      begin
        if src[p2] = '(' then Inc(depth)
        else if src[p2] = ')' then Dec(depth);
        Inc(p2);
      end;
      Dec(p2);

      i := p2 + 1;
      while (i <= Length(src)) and (src[i] in [' ', #10, #13, #9]) do Inc(i);

      if (i <= Length(src)) and (src[i] = ';') then
      begin
        p2 := p - 1;
        while (p2 > 1) and not (src[p2] in [';', '}', '{', #10]) do Dec(p2);
        Inc(p2);

        proto := Trim(Copy(src, p2, i - p2));

        if Copy(LowerCase(proto), 1, 7) = 'typedef' then begin Inc(i); Continue; end;
        if (Length(proto) > 0) and (proto[1] = '#') then begin Inc(i); Continue; end;

        pyDecl := ParseOneFunction(proto);
        if pyDecl <> '' then
        begin
          res.Add(pyDecl);
          res.Add('');
        end;
        Inc(i);
      end
      else
        Inc(i);
    end;
    Result := res.Text;
  finally
    res.Free;
  end;
end;

(* ── Point d entree ─────────────────────────────────────────── *)

function TH2PyConverter.Convert(const headerSource: string;
                                 const aDllName: string): string;
var
  src      : string;
  defines  : string;
  types    : string;
  funcs    : string;
  res      : TStringList;
  baseName : string;
begin
  FDLLName := aDllName;
  FLog.Clear;

  res := TStringList.Create;
  try
    Log('=== Conversion Python demarree ===');
    Log('DLL : ' + aDllName);

    src := StripComments(headerSource);
    src := StripPreprocessorBlocks(src);
    src := NormalizeSpaces(src);

    Log('--- Analyse des #define ---');
    defines := ParseDefines(headerSource);

    Log('--- Analyse des types ---');
    types := ParseStructsAndEnums(src);

    Log('--- Analyse des fonctions ---');
    funcs := ParseFunctions(src);

    // En-tete du fichier Python
    baseName := ChangeFileExt(ExtractFileName(aDllName), '');

    res.Add('"""');
    res.Add('Binding Python (ctypes) pour ' + aDllName);
    res.Add('Genere automatiquement par H2Pas Converter');
    res.Add('Convention : cdecl (CDLL)');
    res.Add('Python 3.x + ctypes');
    res.Add('');
    res.Add('Usage :');
    res.Add('    from ' + LowerCase(baseName) + '_binding import *');
    res.Add('"""');
    res.Add('');
    res.Add('import ctypes');
    res.Add('from ctypes import (');
    res.Add('    CDLL, Structure, POINTER,');
    res.Add('    c_bool, c_char, c_wchar, c_char_p, c_wchar_p,');
    res.Add('    c_int8, c_int16, c_int32, c_int64,');
    res.Add('    c_uint8, c_uint16, c_uint32, c_uint64,');
    res.Add('    c_short, c_ushort, c_int, c_uint,');
    res.Add('    c_long, c_ulong, c_longlong, c_ulonglong,');
    res.Add('    c_float, c_double, c_longdouble,');
    res.Add('    c_size_t, c_ssize_t, c_void_p');
    res.Add(')');
    res.Add('');
    res.Add('# Chargement de la DLL');
    res.Add('lib = CDLL("' + aDllName + '")');
    res.Add('');

    // Constantes #define
    if Trim(defines) <> '' then
    begin
      res.Add('# ── Constantes ─────────────────────────────────────────────');
      res.Add(TrimRight(defines));
      res.Add('');
    end;

    // Types (structs, enums, handles)
    if Trim(types) <> '' then
    begin
      res.Add('# ── Types (structs, enums, handles) ────────────────────────');
      res.Add(TrimRight(types));
      res.Add('');
    end;

    // Fonctions
    if Trim(funcs) <> '' then
    begin
      res.Add('# ── Fonctions exportees ────────────────────────────────────');
      res.Add(TrimRight(funcs));
    end;

    Result := res.Text;
    Log('');
    Log('=== Conversion Python terminee ===');
  finally
    res.Free;
  end;
end;

end.
