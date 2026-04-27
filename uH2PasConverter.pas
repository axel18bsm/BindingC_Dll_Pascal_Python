unit uH2PasConverter;

{
  ============================================================
  H2Pas Converter -- Moteur de conversion .h -> .pas
  Convention d'appel : cdecl (fixe)
  Cible : Free Pascal / Lazarus, Windows 32/64-bit
  ============================================================

  Gere :
    - Typedefs simples  (typedef int MonInt;)
    - Structs           (typedef struct ... MonStruct;)
    - Enums             (typedef enum ... MonEnum;)
    - Handles opaques   (typedef struct Foo_t* FooHandle;)
    - Prototypes        (int CDECL foo(int a, char* b);)
    - #define constants numeriques
    - Commentaires C et C++
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils;

type
  TConversionLog = TStringList;

  TH2PasConverter = class
  private
    FDLLName   : string;
    FUnitName  : string;
    FLog       : TConversionLog;

    { ── Nettoyage source ── }
    function  StripComments(const src: string): string;
    function  StripPreprocessorBlocks(const src: string): string;
    function  NormalizeSpaces(const src: string): string;
    { ── Traduction des types ── }
    function  MapCTypeToPascal(const ctype: string): string;
    function  MapFunctionReturn(const ctype: string): string;

    { ── Parseurs spécialisés ── }
    function  ParseDefines(const src: string): string;
    function  ParseTypedefs(const src: string; structs, enums, handles: TStringList): string;
    function  ParseStructBody(const body: string; const structName: string): string;
    function  ParseEnumBody(const body: string; const enumName: string): string;
    function  ParseFunctions(const src: string): string;
    function  ParseOneFunction(const proto: string): string;
    function  ParseParams(const paramStr: string): string;

    { ── Utilitaires ── }
    function  CleanIdent(const s: string): string;
    function  ExtractBetweenBraces(const src: string; startPos: Integer; out endPos: Integer): string;
    function  SplitParams(const s: string): TStringList;
    procedure Log(const msg: string);

  public
    constructor Create;
    destructor  Destroy; override;

    function Convert(const headerSource: string;
                     const aDllName: string;
                     const aUnitName: string): string;

    property ConversionLog: TConversionLog read FLog;
  end;

implementation

{ ══════════════════════════════════════════════════════════════
  Correspondance des types C → Pascal
  ══════════════════════════════════════════════════════════════ }

{ La table de correspondance C->Pascal est implementee directement
  dans MapCTypeToPascal via une serie de comparaisons. }

{ ══════════════════════════════════════════════════════════════ }

constructor TH2PasConverter.Create;
begin
  inherited Create;
  FLog := TConversionLog.Create;
end;

destructor TH2PasConverter.Destroy;
begin
  FLog.Free;
  inherited Destroy;
end;

procedure TH2PasConverter.Log(const msg: string);
begin
  FLog.Add(msg);
end;

{ ── Nettoyage ──────────────────────────────────────────────── }

function TH2PasConverter.StripComments(const src: string): string;
var
  i, n : Integer;
  res  : TStringBuilder;
  inML : Boolean;  // inside /* */
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
          if src[i] = #10 then res.Append(#10);  // préserver les sauts de ligne
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
          // Sauter jusqu'à fin de ligne
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

function TH2PasConverter.StripPreprocessorBlocks(const src: string): string;
{ Supprime les lignes de préprocesseur (#ifndef, #ifdef, #define guard, etc.)
  mais GARDE les #define de constantes numériques (traités séparément) }
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
        // On garde les #define simples (constantes) - ils seront parses plus tard
        // On ignore tout le reste
        if Copy(trimmed, 1, 7) = '#define' then
          res.Add(line)   // sera parsé dans ParseDefines
        else
          res.Add('');    // supprime #include, #ifndef, #ifdef, #endif, #pragma
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

function TH2PasConverter.NormalizeSpaces(const src: string): string;
{ Réduit les espaces multiples, normalise * et & }
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

{ ── Traduction des types ───────────────────────────────────── }

function TH2PasConverter.MapCTypeToPascal(const ctype: string): string;
{ Traduit un type C vers son equivalent Pascal.
  Gere : const, pointeurs (*), et tous les types de base. }
var
  normalized : string;
  isPtr      : Boolean;
  base       : string;
  pasBase    : string;
begin
  normalized := Trim(LowerCase(ctype));

  // Supprimer 'const'
  if Copy(normalized, 1, 6) = 'const ' then
    normalized := Trim(Copy(normalized, 7, MaxInt));

  // Normaliser les espaces autour de *
  normalized := StringReplace(normalized, ' *', '*', [rfReplaceAll]);
  normalized := StringReplace(normalized, '* ', '*', [rfReplaceAll]);

  // Detecter pointeur (un seul niveau)
  isPtr := (Length(normalized) > 0) and (normalized[Length(normalized)] = '*');
  if isPtr then
    base := Trim(Copy(normalized, 1, Length(normalized) - 1))
  else
    base := normalized;

  // Cas speciaux avec pointeur
  if isPtr then
  begin
    if base = 'char'    then begin Result := 'PAnsiChar'; Exit; end;
    if base = 'wchar_t' then begin Result := 'PWideChar';  Exit; end;
    if (base = 'void') or (base = '') then begin Result := 'Pointer'; Exit; end;
    if base = 'uint8_t' then begin Result := 'PByte';     Exit; end;
    if base = 'int8_t'  then begin Result := 'PShortInt'; Exit; end;
  end;

  // Table de correspondance C -> Pascal (comparaisons directes)
  pasBase := '';
  if      base = 'void'              then pasBase := ''         // traite par MapFunctionReturn
  else if base = 'bool'              then pasBase := 'ByteBool'
  else if base = '_bool'             then pasBase := 'ByteBool'
  else if base = 'bool_t'            then pasBase := 'ByteBool'
  else if base = 'int_bool'          then pasBase := 'LongBool'
  else if base = 'int8_t'            then pasBase := 'ShortInt'
  else if base = 'int16_t'           then pasBase := 'SmallInt'
  else if base = 'int32_t'           then pasBase := 'LongInt'
  else if base = 'int64_t'           then pasBase := 'Int64'
  else if base = 'uint8_t'           then pasBase := 'Byte'
  else if base = 'uint16_t'          then pasBase := 'Word'
  else if base = 'uint32_t'          then pasBase := 'LongWord'
  else if base = 'uint64_t'          then pasBase := 'UInt64'
  else if base = 'signed char'       then pasBase := 'ShortInt'
  else if base = 'unsigned char'     then pasBase := 'Byte'
  else if base = 'char'              then pasBase := 'AnsiChar'
  else if base = 'wchar_t'           then pasBase := 'WideChar'
  else if base = 'short'             then pasBase := 'SmallInt'
  else if base = 'short int'         then pasBase := 'SmallInt'
  else if base = 'unsigned short'    then pasBase := 'Word'
  else if base = 'unsigned short int'then pasBase := 'Word'
  else if base = 'int'               then pasBase := 'LongInt'
  else if base = 'signed int'        then pasBase := 'LongInt'
  else if base = 'signed'            then pasBase := 'LongInt'
  else if base = 'unsigned int'      then pasBase := 'LongWord'
  else if base = 'unsigned'          then pasBase := 'LongWord'
  else if base = 'long'              then pasBase := 'LongInt'
  else if base = 'long int'          then pasBase := 'LongInt'
  else if base = 'signed long'       then pasBase := 'LongInt'
  else if base = 'unsigned long'     then pasBase := 'LongWord'
  else if base = 'unsigned long int' then pasBase := 'LongWord'
  else if base = 'long long'         then pasBase := 'Int64'
  else if base = 'long long int'     then pasBase := 'Int64'
  else if base = 'signed long long'  then pasBase := 'Int64'
  else if base = 'unsigned long long'then pasBase := 'UInt64'
  else if base = 'float'             then pasBase := 'Single'
  else if base = 'double'            then pasBase := 'Double'
  else if base = 'long double'       then pasBase := 'Extended'
  else if base = 'size_t'            then pasBase := 'PtrUInt'
  else if base = 'ssize_t'           then pasBase := 'PtrInt'
  else if base = 'ptrdiff_t'         then pasBase := 'PtrInt'
  else if base = 'intptr_t'          then pasBase := 'PtrInt'
  else if base = 'uintptr_t'         then pasBase := 'PtrUInt'
  else if base = 'off_t'             then pasBase := 'Int64'
  else if base = 'bool'              then pasBase := 'LongBool'
  else if base = 'byte'              then pasBase := 'Byte'
  else if base = 'word'              then pasBase := 'Word'
  else if base = 'dword'             then pasBase := 'LongWord'
  else if base = 'qword'             then pasBase := 'UInt64'
  else if base = 'handle'            then pasBase := 'THandle'
  else if base = 'hwnd'              then pasBase := 'HWND'
  else if base = 'lpvoid'            then pasBase := 'Pointer'
  else if base = 'lpcstr'            then pasBase := 'PAnsiChar'
  else if base = 'lpstr'             then pasBase := 'PAnsiChar'
  else if base = 'lpcwstr'           then pasBase := 'PWideChar'
  else if base = 'lpwstr'            then pasBase := 'PWideChar';

  if pasBase <> '' then
  begin
    if isPtr then
    begin
      // Construire le type pointeur
      if Copy(pasBase, 1, 1) = 'P' then
        Result := 'P' + Copy(pasBase, 2, MaxInt)  // ex: PByte -> PPByte non, garder PByte
      else
        Result := 'P' + pasBase;
    end
    else
      Result := pasBase;
    Exit;
  end;

  // Type vide (void sans pointeur)
  if base = 'void' then
  begin
    Result := '';
    Exit;
  end;

  // Type non reconnu : on fabrique un nom Pascal prefixe T
  Result := 'T' + CleanIdent(ctype);
  if isPtr then
  begin
    if Copy(Result, 1, 1) = 'T' then
      Result := 'P' + Copy(Result, 2, MaxInt)
    else
      Result := 'P' + Result;
  end;
  Log('  [WARN] Type non reconnu : "' + ctype + '" -> ' + Result + ' (verifiez manuellement)');
end;

function TH2PasConverter.MapFunctionReturn(const ctype: string): string;
{ Comme MapCTypeToPascal mais gère void → "procedure" }
begin
  if Trim(LowerCase(ctype)) = 'void' then
    Result := ''   // vide = procedure
  else
    Result := MapCTypeToPascal(ctype);
end;

{ ── Utilitaires ────────────────────────────────────────────── }

function TH2PasConverter.CleanIdent(const s: string): string;
{ Retourne un identifiant Pascal valide depuis un nom C }
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
    // Capitaliser première lettre
    if (Length(Result) > 0) and (Result[1] in ['a'..'z']) then
      Result[1] := UpCase(Result[1]);
  finally
    res.Free;
  end;
end;

function TH2PasConverter.ExtractBetweenBraces(const src: string; startPos: Integer; out endPos: Integer): string;
(* Extrait le contenu entre accolades en tenant compte de l'imbrication *)
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

function TH2PasConverter.SplitParams(const s: string): TStringList;
{ Découpe les paramètres d'une fonction en tenant compte des <> et () imbriqués }
var
  depth  : Integer;
  i      : Integer;
  cur    : TStringBuilder;
  c      : Char;
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

{ ── Parseur #define ────────────────────────────────────────── }

function TH2PasConverter.ParseDefines(const src: string): string;
var
  lines : TStringList;
  line  : string;
  parts : TStringList;
  name  : string;
  value : string;
  res   : TStringList;
  i     : Integer;
  isNum : Boolean;
  c     : Char;
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

      // Supprimer '#define '
      line := Trim(Copy(line, 8, MaxInt));

      // Séparer nom et valeur
      parts.Clear;
      parts.Delimiter       := ' ';
      parts.StrictDelimiter := True;
      parts.DelimitedText   := line;

      if parts.Count < 2 then Continue;
      name  := Trim(parts[0]);
      value := Trim(Copy(line, Length(name) + 2, MaxInt));

      // Vérifier si c'est une constante numérique (ou hex)
      value := StringReplace(value, 'u', '', [rfIgnoreCase]);
      value := StringReplace(value, 'l', '', [rfIgnoreCase]);
      value := StringReplace(value, 'f', '', []);

      isNum := True;
      if Length(value) = 0 then isNum := False;
      for c in value do
        if not (c in ['0'..'9', 'a'..'f', 'A'..'F', 'x', 'X', '-', '+', '.']) then
        begin
          isNum := False;
          Break;
        end;

      if isNum and (Length(name) > 0) then
      begin
        // Convertir 0x en $
        value := StringReplace(value, '0x', '$', [rfIgnoreCase]);
        value := StringReplace(value, '0X', '$', []);
        res.Add('  ' + name + ' = ' + value + ';');
        Log('  #define → const ' + name + ' = ' + value);
      end;
    end;

    if res.Count > 0 then
      Result := res.Text
    else
      Result := '';
  finally
    lines.Free;
    res.Free;
    parts.Free;
  end;
end;

{ ── Parseur structs / enums / typedefs ─────────────────────── }

function TH2PasConverter.ParseStructBody(const body: string; const structName: string): string;
{ Convertit le corps d'une struct C en champs Pascal }
var
  lines    : TStringList;
  line     : string;
  i        : Integer;
  parts    : TStringList;
  ctype    : string;
  fieldName: string;
  pasType  : string;
  res      : TStringList;
  lastField: string;
  isArr    : Boolean;
  arrSize  : string;
  p        : Integer;
begin
  lines := TStringList.Create;
  res   := TStringList.Create;
  parts := TStringList.Create;
  try
    // Découper sur ; et newlines
    lines.Text := StringReplace(body, ';', ';'#10, [rfReplaceAll]);

    for i := 0 to lines.Count - 1 do
    begin
      line := Trim(lines[i]);
      if line = '' then Continue;
      if (Length(line) > 0) and (line[Length(line)] = ';') then
        line := Trim(Copy(line, 1, Length(line) - 1));
      if line = '' then Continue;

      // Détecter tableau : type name[N]
      isArr   := False;
      arrSize := '';
      p := Pos('[', line);
      if p > 0 then
      begin
        isArr   := True;
        arrSize := Trim(Copy(line, p + 1, Pos(']', line) - p - 1));
        line    := Trim(Copy(line, 1, p - 1));
      end;

      // Séparer le dernier mot (nom du champ) du reste (type C)
      parts.Clear;
      parts.Delimiter       := ' ';
      parts.StrictDelimiter := True;
      parts.DelimitedText   := Trim(line);

      if parts.Count < 2 then Continue;

      fieldName := Trim(parts[parts.Count - 1]);
      // Supprimer * du nom si pointeur collé au nom
      if (Length(fieldName) > 0) and (fieldName[1] = '*') then
      begin
        fieldName := Copy(fieldName, 2, MaxInt);
        // Ajouter * au type
        ctype := Trim(Copy(line, 1, Length(line) - Length(fieldName)));
        ctype := ctype + '*';
      end
      else
        ctype := Trim(Copy(line, 1, Length(line) - Length(fieldName)));

      fieldName := CleanIdent(fieldName);
      if fieldName = '' then Continue;

      // Forcer minuscule premiere lettre pour les champs
      if Length(fieldName) > 0 then
        fieldName := LowerCase(Copy(fieldName, 1, 1)) + Copy(fieldName, 2, MaxInt);

      pasType := MapCTypeToPascal(ctype);

      if isArr then
        res.Add('    ' + fieldName + ' : array[0..' + arrSize + '-1] of ' + pasType + ';')
      else
        res.Add('    ' + fieldName + ' : ' + pasType + ';');
    end;

    Result := res.Text;
  finally
    lines.Free;
    res.Free;
    parts.Free;
  end;
end;

function TH2PasConverter.ParseEnumBody(const body: string; const enumName: string): string;
{ Convertit un enum C en constantes Pascal }
var
  items    : TStringList;
  item     : string;
  i        : Integer;
  eqPos    : Integer;
  eName    : string;
  eVal     : string;
  counter  : Integer;
  res      : TStringList;
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
        // Hex
        eVal  := StringReplace(eVal, '0x', '$', [rfIgnoreCase]);
        eVal  := StringReplace(eVal, '0X', '$', []);
        try
          counter := StrToInt(StringReplace(eVal, '$', '0', []));
        except
          { valeur non numérique, on garde telle quelle }
        end;
      end
      else
      begin
        eName := item;
        eVal  := IntToStr(counter);
      end;

      eName := CleanIdent(eName);
      if eName <> '' then
      begin
        res.Add('  ' + eName + ' = ' + eVal + ';');
        Log('  enum ' + enumName + '.' + eName + ' = ' + eVal);
      end;
      Inc(counter);
    end;
    Result := res.Text;
  finally
    items.Free;
    res.Free;
  end;
end;

function TH2PasConverter.ParseTypedefs(const src: string; structs, enums, handles: TStringList): string;
(* Traite typedef struct, typedef enum, handles opaques, et alias de types *)
var
  i        : Integer;
  p        : Integer;
  keyword  : string;
  body     : string;
  afterName: string;
  typeName : string;
  baseType : string;
  endPos   : Integer;
  res      : TStringList;
  line     : string;
  src2     : string;
  lowSrc   : string;
begin
  res  := TStringList.Create;
  src2 := src;
  try
    lowSrc := LowerCase(src2);
    i      := 1;

    while i <= Length(src2) do
    begin
      // Chercher 'typedef'
      p := PosEx('typedef', lowSrc, i);
      if p = 0 then Break;

      // Lire ce qui suit 'typedef '
      keyword := Trim(Copy(src2, p + 7, 30));

      { ── struct ── }
      if (Copy(keyword, 1, 6) = 'struct') or (Copy(keyword, 1, 5) = 'union') then
      begin
        // Chercher le { ou le *
        p := PosEx('{', src2, p);
        if p = 0 then
        begin
          // Peut-être typedef struct Tag* Handle;
          p := PosEx('typedef', lowSrc, i);
          afterName := Trim(Copy(src2, p + 7, 200));
          // Chercher * → handle opaque
          if Pos('*', afterName) > 0 then
          begin
            // Extraire le nom après le *
            typeName := Trim(afterName);
            // Supprimer jusqu'au *
            typeName := Trim(Copy(typeName, Pos('*', typeName) + 1, MaxInt));
            // Supprimer le ;
            p := Pos(';', typeName);
            if p > 0 then typeName := Trim(Copy(typeName, 1, p - 1));
            typeName := CleanIdent(typeName);
            if typeName <> '' then
            begin
              res.Add('  T' + typeName + ' = Pointer;  { handle opaque }');
              res.Add('  P' + typeName + ' = ^T' + typeName + ';');
              handles.Add(typeName);
              Log('  Handle opaque : T' + typeName);
            end;
          end;
          i := PosEx(';', src2, i) + 1;
          if i <= 0 then Break;
          Continue;
        end;

        // Extraire le corps { ... }
        body := ExtractBetweenBraces(src2, p, endPos);

        // Trouver le nom après }
        afterName := Trim(Copy(src2, endPos + 1, 100));
        p         := Pos(';', afterName);
        if p > 0 then afterName := Trim(Copy(afterName, 1, p - 1));
        typeName  := CleanIdent(afterName);

        if typeName <> '' then
        begin
          res.Add('  T' + typeName + ' = packed record');
          res.Add(TrimRight(ParseStructBody(body, typeName)));
          res.Add('  end;');
          res.Add('  P' + typeName + ' = ^T' + typeName + ';');
          res.Add('');
          structs.Add(typeName);
          Log('  struct → T' + typeName);
        end;

        i := endPos + 1;
      end

      { ── enum ── }
      else if Copy(keyword, 1, 4) = 'enum' then
      begin
        p := PosEx('{', src2, p);
        if p = 0 then begin Inc(i); Continue; end;

        body := ExtractBetweenBraces(src2, p, endPos);

        afterName := Trim(Copy(src2, endPos + 1, 100));
        p         := Pos(';', afterName);
        if p > 0 then afterName := Trim(Copy(afterName, 1, p - 1));
        typeName  := CleanIdent(afterName);

        if typeName <> '' then
        begin
          res.Add('  T' + typeName + ' = LongInt;');
          enums.Add(typeName);
          Log('  enum → T' + typeName + ' (LongInt + constantes)');
        end;

        // Les valeurs seront dans la section const
        // Stocker le corps pour plus tard
        handles.Add('__ENUM__' + typeName + '|' + body);

        i := endPos + 1;
      end

      { ── typedef simple ── }
      else
      begin
        // typedef BaseType NewName;
        p := PosEx('typedef', lowSrc, i);
        afterName := Trim(Copy(src2, p + 7, 200));
        endPos    := PosEx(';', src2, p);
        if endPos = 0 then begin Inc(i); Continue; end;

        line := Trim(Copy(src2, p + 7, endPos - p - 7));
        // Dernier mot = nouveau nom
        p := LastDelimiter(' *', line);
        if p > 0 then
        begin
          typeName := Trim(Copy(line, p + 1, MaxInt));
          baseType := Trim(Copy(line, 1, p - 1));
          typeName  := CleanIdent(typeName);
          baseType  := MapCTypeToPascal(baseType);
          if (typeName <> '') and (baseType <> '') then
          begin
            res.Add('  T' + typeName + ' = ' + baseType + ';');
            res.Add('  P' + typeName + ' = ^T' + typeName + ';');
            Log('  typedef → T' + typeName + ' = ' + baseType);
          end;
        end;

        i := endPos + 1;
      end;

      // Mettre à jour lowSrc pour suivre les modifications
      lowSrc := LowerCase(src2);
    end;

    Result := res.Text;
  finally
    res.Free;
  end;
end;

{ ── Parseur des prototypes de fonctions ─────────────────────── }

function TH2PasConverter.ParseParams(const paramStr: string): string;
{
  Convertit une liste de paramètres C en paramètres Pascal.
  Ex: "int a, const char* name, float* out_val"
   → "a: LongInt; name: PAnsiChar; out_val: PSingle"
}
var
  params   : TStringList;
  i        : Integer;
  param    : string;
  parts    : TStringList;
  ctype    : string;
  pname    : string;
  pasType  : string;
  res      : TStringList;
  isOut    : Boolean;
  p        : Integer;
begin
  if Trim(paramStr) = '' then begin Result := ''; Exit; end;
  if LowerCase(Trim(paramStr)) = 'void' then begin Result := ''; Exit; end;

  params := SplitParams(paramStr);
  res    := TStringList.Create;
  parts  := TStringList.Create;
  try
    for i := 0 to params.Count - 1 do
    begin
      param := Trim(params[i]);
      if param = '' then Continue;
      if LowerCase(param) = 'void' then Continue;

      // Cas "..." (varargs) → ignorer
      if param = '...' then
      begin
        res.Add('{varargs}');
        Continue;
      end;

      // Vérifier pointeur (out param) : si * attaché au NOM et non au type
      isOut := False;

      // Séparer dernier mot (nom) du reste (type)
      parts.Clear;
      parts.Delimiter       := ' ';
      parts.StrictDelimiter := True;
      parts.DelimitedText   := param;

      if parts.Count = 0 then Continue;
      if parts.Count = 1 then
      begin
        // Pas de nom → paramètre anonyme, utiliser "p<i>"
        pname  := 'p' + IntToStr(i + 1);
        ctype  := parts[0];
      end
      else
      begin
        pname := Trim(parts[parts.Count - 1]);
        // Gérer * collé au nom
        if (Length(pname) > 0) and (pname[1] = '*') then
        begin
          pname  := Copy(pname, 2, MaxInt);
          ctype  := Trim(Copy(param, 1, Length(param) - Length(pname))) + '*';
        end
        else
          ctype := Trim(Copy(param, 1, Length(param) - Length(pname)));
      end;

      pname   := CleanIdent(pname);
      if pname = '' then pname := 'p' + IntToStr(i + 1);

      // Forcer premiere lettre minuscule
      if Length(pname) > 0 then
        pname := LowerCase(Copy(pname, 1, 1)) + Copy(pname, 2, MaxInt);

      pasType := MapCTypeToPascal(ctype);

      // Si c'est un pointeur vers un type simple (pas PAnsiChar etc.) → var
      if (Copy(pasType, 1, 1) = 'P') and
         (pasType <> 'PAnsiChar') and
         (pasType <> 'PWideChar') and
         (pasType <> 'PByte') and
         (pasType <> 'Pointer') then
      begin
        // Laisser tel quel comme pointeur - l'utilisateur decidera si c'est var
      end;

      res.Add(pname + ': ' + pasType);
    end;

    Result := '';
    for i := 0 to res.Count - 1 do
    begin
      if i > 0 then Result := Result + '; ';
      Result := Result + res[i];
    end;
  finally
    params.Free;
    res.Free;
    parts.Free;
  end;
end;

function TH2PasConverter.ParseOneFunction(const proto: string): string;
{
  Parse un prototype C complet et retourne la déclaration Pascal.
  Ex: "int mylib_add(int a, int b)"
   → "function mylib_add(a: LongInt; b: LongInt): LongInt; cdecl;"
}
var
  p        : Integer;
  retCtype : string;
  funcName : string;
  paramStr : string;
  pasParams: string;
  pasRet   : string;
  cleaned  : string;
  parts    : TStringList;
  lastWord : Integer;
begin
  Result  := '';
  cleaned := Trim(proto);

  // Supprimer macros d'export fréquentes
  cleaned := StringReplace(cleaned, '__declspec(dllexport)', '', [rfIgnoreCase]);
  cleaned := StringReplace(cleaned, '__declspec(dllimport)', '', [rfIgnoreCase]);
  cleaned := StringReplace(cleaned, '__cdecl',   '', [rfReplaceAll, rfIgnoreCase]);
  cleaned := StringReplace(cleaned, 'CDECL',     '', [rfReplaceAll]);
  cleaned := StringReplace(cleaned, '__stdcall', '', [rfReplaceAll, rfIgnoreCase]);
  cleaned := StringReplace(cleaned, 'WINAPI',    '', [rfReplaceAll]);
  cleaned := StringReplace(cleaned, 'APIENTRY',  '', [rfReplaceAll]);
  cleaned := StringReplace(cleaned, 'CALLBACK',  '', [rfReplaceAll]);
  cleaned := StringReplace(cleaned, 'extern',    '', [rfReplaceAll, rfIgnoreCase]);
  cleaned := StringReplace(cleaned, 'MYLIB_API', '', [rfReplaceAll]);
  cleaned := StringReplace(cleaned, 'DLL_API',   '', [rfReplaceAll]);
  cleaned := StringReplace(cleaned, 'API',       '', [rfReplaceAll]);
  cleaned := NormalizeSpaces(Trim(cleaned));

  // Trouver la parenthèse ouvrante
  p := Pos('(', cleaned);
  if p = 0 then Exit;

  // Extraire paramètres
  paramStr := Copy(cleaned, p + 1, Length(cleaned) - p - 1);
  // Supprimer la parenthèse fermante finale
  if (Length(paramStr) > 0) and (paramStr[Length(paramStr)] = ')') then
    paramStr := Copy(paramStr, 1, Length(paramStr) - 1);
  paramStr := Trim(paramStr);

  // Avant la ( : "rettype funcname"
  cleaned := Trim(Copy(cleaned, 1, p - 1));

  // Dernier mot = nom de la fonction
  lastWord := LastDelimiter(' *', cleaned);
  if lastWord = 0 then Exit;

  funcName := Trim(Copy(cleaned, lastWord + 1, MaxInt));
  retCtype := Trim(Copy(cleaned, 1, lastWord - 1));

  if funcName = '' then Exit;

  pasParams := ParseParams(paramStr);
  pasRet    := MapFunctionReturn(retCtype);

  if pasRet = '' then
  begin
    // procedure
    if pasParams <> '' then
      Result := 'procedure ' + funcName + '(' + pasParams + '); cdecl;'
    else
      Result := 'procedure ' + funcName + '; cdecl;';
  end
  else
  begin
    // function
    if pasParams <> '' then
      Result := 'function ' + funcName + '(' + pasParams + '): ' + pasRet + '; cdecl;'
    else
      Result := 'function ' + funcName + ': ' + pasRet + '; cdecl;';
  end;
end;

function TH2PasConverter.ParseFunctions(const src: string): string;
(* Extrait tous les prototypes de fonctions C. Un prototype = parentheses + point-virgule sans accolades *)
var
  i        : Integer;
  p, p2    : Integer;
  proto    : string;
  pasDecl  : string;
  res      : TStringList;
  funcName : string;
  src2     : string;
  lowSrc   : string;
  inStruct : Boolean;
  depth    : Integer;
begin
  res    := TStringList.Create;
  src2   := src;
  lowSrc := LowerCase(src2);
  try
    i := 1;
    while i <= Length(src2) do
    begin
      // Chercher une ( qui pourrait être un prototype de fonction
      p := PosEx('(', src2, i);
      if p = 0 then Break;

      // Vérifier qu'on n'est pas dans une struct/enum (pas de { avant ce ( sans } correspondant)
      // Simple heuristique : chercher le ; précédent ou le début, vérifier pas de { non refermé
      p2 := p;
      depth := 0;
      while p2 > 1 do
      begin
        Dec(p2);
        if src2[p2] = '}' then Inc(depth);
        if src2[p2] = '{' then
        begin
          if depth = 0 then Break;  // On est dans une struct
          Dec(depth);
        end;
        if src2[p2] = ';' then Break;
      end;
      if (p2 > 1) and (src2[p2] = '{') then
      begin
        Inc(i);
        Continue;
      end;

      // Trouver la ) correspondante
      depth := 1;
      p2    := p + 1;
      while (p2 <= Length(src2)) and (depth > 0) do
      begin
        if src2[p2] = '(' then Inc(depth)
        else if src2[p2] = ')' then Dec(depth);
        Inc(p2);
      end;
      Dec(p2);  // position du )

      // Chercher le ; après )
      i := p2 + 1;
      while (i <= Length(src2)) and (src2[i] in [' ', #10, #13, #9]) do Inc(i);

      if (i <= Length(src2)) and (src2[i] = ';') then
      begin
        // C'est bien un prototype (pas de { après)
        // Remonter pour trouver le début de la déclaration (depuis le ; ou { précédent)
        p2 := p - 1;
        while (p2 > 1) and not (src2[p2] in [';', '}', '{', #10]) do Dec(p2);
        Inc(p2);

        proto := Trim(Copy(src2, p2, i - p2));

        // Ignorer typedef
        if LowerCase(proto).Contains('typedef') then
        begin
          Inc(i);
          Continue;
        end;

        // Ignorer les macros #define avec (
        if (Length(proto) > 0) and (proto[1] = '#') then
        begin
          Inc(i);
          Continue;
        end;

        pasDecl := ParseOneFunction(proto);
        if pasDecl <> '' then
        begin
          // Extraire nom de fonction pour le name '...'
          funcName := '';
          p2 := Pos('(', pasDecl);
          if p2 > 0 then
          begin
            funcName := Trim(Copy(pasDecl, 1, p2 - 1));
            // Dernier mot
            p2 := LastDelimiter(' ', funcName);
            if p2 > 0 then funcName := Copy(funcName, p2 + 1, MaxInt);
          end;

          res.Add(pasDecl);
          res.Add('  external ' + QuotedStr(FDLLName) + ' name ' + QuotedStr(funcName) + ';');
          res.Add('');
          Log('  fonction → ' + pasDecl);
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

{ ══════════════════════════════════════════════════════════════
  Point d'entrée principal
  ══════════════════════════════════════════════════════════════ }

function TH2PasConverter.Convert(const headerSource: string;
                                  const aDllName: string;
                                  const aUnitName: string): string;
var
  src      : string;
  structs  : TStringList;
  enums    : TStringList;
  handles  : TStringList;
  defines  : string;
  types    : string;
  funcs    : string;
  enumConst: TStringList;
  i        : Integer;
  tag      : string;
  body     : string;
  p        : Integer;
  res      : TStringList;
  hasConst : Boolean;
begin
  FDLLName  := aDllName;
  FUnitName  := aUnitName;
  FLog.Clear;

  structs   := TStringList.Create;
  enums     := TStringList.Create;
  handles   := TStringList.Create;
  enumConst := TStringList.Create;
  res       := TStringList.Create;

  try
    Log('=== Conversion démarrée ===');
    Log('DLL : ' + aDllName);
    Log('Unite : ' + aUnitName);
    Log('');

    // ── Étape 1 : Nettoyage ──────────────────────────────────
    Log('--- Nettoyage du source ---');
    src := StripComments(headerSource);
    src := StripPreprocessorBlocks(src);
    src := NormalizeSpaces(src);

    // ── Étape 2 : #define constants ──────────────────────────
    Log('--- Analyse des #define ---');
    defines := ParseDefines(headerSource);  // depuis le source original

    // ── Étape 3 : Typedefs / Structs / Enums ─────────────────
    Log('--- Analyse des types ---');
    types := ParseTypedefs(src, structs, enums, handles);

    // ── Étape 4 : Constantes enum (stockées dans handles avec __ENUM__ prefix) ──
    for i := handles.Count - 1 downto 0 do
    begin
      tag := handles[i];
      if Copy(tag, 1, 8) = '__ENUM__' then
      begin
        tag := Copy(tag, 9, MaxInt);
        p   := Pos('|', tag);
        if p > 0 then
        begin
          body := Copy(tag, p + 1, MaxInt);
          tag  := Copy(tag, 1, p - 1);
          enumConst.Add('  { Valeurs de l''enum T' + tag + ' }');
          enumConst.Add(TrimRight(ParseEnumBody(body, tag)));
        end;
        handles.Delete(i);
      end;
    end;

    // ── Étape 5 : Fonctions ───────────────────────────────────
    Log('--- Analyse des fonctions ---');
    funcs := ParseFunctions(src);

    // ── Étape 6 : Assemblage du .pas ─────────────────────────
    Log('--- Génération du .pas ---');

    res.Add('unit ' + aUnitName + ';');
    res.Add('');
    res.Add('{');
    res.Add('  Binding Pascal pour ' + aDllName);
    res.Add('  Généré automatiquement par H2Pas Converter');
    res.Add('  Convention d''appel : cdecl');
    res.Add('  Cible : Free Pascal / Lazarus, Windows 32/64-bit');
    res.Add('  ATTENTION : Vérifiez les types marqués { handle opaque } et { vérifiez }');
    res.Add('}');
    res.Add('');
    res.Add('{$mode objfpc}{$H+}');
    res.Add('{$PACKRECORDS C}');
    res.Add('');
    res.Add('interface');
    res.Add('');
    res.Add('uses');
    res.Add('  ctypes;');
    res.Add('');

    // Section const
    hasConst := (Trim(defines) <> '') or (enumConst.Count > 0);
    if hasConst then
    begin
      res.Add('const');
      res.Add('  ' + UpperCase(StringReplace(aDllName, '.dll', '', [rfIgnoreCase])) + '_DLL = ' + QuotedStr(aDllName) + ';');
      res.Add('');
      if Trim(defines) <> '' then
      begin
        res.Add('  { Constantes #define }');
        res.Add(TrimRight(defines));
        res.Add('');
      end;
      if enumConst.Count > 0 then
      begin
        res.Add(TrimRight(enumConst.Text));
        res.Add('');
      end;
    end
    else
    begin
      res.Add('const');
      res.Add('  ' + UpperCase(StringReplace(aDllName, '.dll', '', [rfIgnoreCase])) + '_DLL = ' + QuotedStr(aDllName) + ';');
      res.Add('');
    end;

    // Section type
    if Trim(types) <> '' then
    begin
      res.Add('type');
      res.Add(TrimRight(types));
      res.Add('');
    end;

    // Section fonctions
    if Trim(funcs) <> '' then
    begin
      res.Add('{ ── Fonctions exportées ───────────────────────────────── }');
      res.Add('');
      res.Add(TrimRight(funcs));
      res.Add('');
    end;

    res.Add('implementation');
    res.Add('');
    res.Add('end.');

    Result := res.Text;
    Log('');
    Log('=== Conversion terminée ===');
    Log(IntToStr(structs.Count) + ' struct(s), ' +
        IntToStr(enums.Count)   + ' enum(s), ' +
        IntToStr(handles.Count) + ' handle(s) opaque(s)');

  finally
    structs.Free;
    enums.Free;
    handles.Free;
    enumConst.Free;
    res.Free;
  end;
end;

end.
