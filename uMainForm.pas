unit uMainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Buttons, Menus, LCLType, EditBtn,
  uH2PasConverter, uH2PyConverter;

type

  { TFormMain }

  TFormMain = class(TForm)
    MainMenu1        : TMainMenu;
    MenuFichier      : TMenuItem;
    MenuSauver       : TMenuItem;
    MenuSep1         : TMenuItem;
    MenuQuitter      : TMenuItem;
    MenuAide         : TMenuItem;
    MenuAPropos      : TMenuItem;

    PanelParams      : TPanel;
    LblFichierH      : TLabel;
    FileEditH        : TFileNameEdit;
    LblDLL           : TLabel;
    EditDLL          : TEdit;
    LblUnit          : TLabel;
    EditUnit         : TEdit;
    RGLangage        : TRadioGroup;
    BtnConvertirMain : TBitBtn;
    BtnEffacer       : TBitBtn;

    Splitter2        : TSplitter;
    PanelLog         : TPanel;
    LblLog           : TLabel;
    MemoLog          : TMemo;

    PanelCentral     : TPanel;
    PanelSource      : TPanel;
    LblSource        : TLabel;
    MemoSource       : TMemo;
    Splitter1        : TSplitter;
    PanelResult      : TPanel;
    LblResult        : TLabel;
    BtnSauver        : TBitBtn;
    MemoResult       : TMemo;

    StatusBar1       : TStatusBar;
    SaveDialog1      : TSaveDialog;

    procedure FormCreate(Sender: TObject);
    procedure FileEditHChange(Sender: TObject);
    procedure FileEditHAcceptFileName(Sender: TObject; var Value: string);
    procedure EditDLLChange(Sender: TObject);
    procedure EditUnitChange(Sender: TObject);
    procedure RGLangageClick(Sender: TObject);
    procedure BtnConvertirMainClick(Sender: TObject);
    procedure BtnSauverClick(Sender: TObject);
    procedure BtnEffacerClick(Sender: TObject);
    procedure MenuSauverClick(Sender: TObject);
    procedure MenuQuitterClick(Sender: TObject);
    procedure MenuAProposClick(Sender: TObject);

  private
    procedure DoConvert;
    procedure LoadHFile(const AFileName: string);
    procedure UpdateStatus;
    procedure AutoFillFromFileName(const AFileName: string);
    function  IsPascalMode: Boolean;
    function  OutputExtension: string;
  end;

var
  FormMain: TFormMain;

implementation

{$R *.lfm}

{ TFormMain }

function TFormMain.IsPascalMode: Boolean;
begin
  Result := RGLangage.ItemIndex = 0;
end;

function TFormMain.OutputExtension: string;
begin
  if IsPascalMode then Result := '.pas' else Result := '.py';
end;

procedure TFormMain.FormCreate(Sender: TObject);
begin
  Caption := 'H2Pas Converter  -  .h vers .pas / .py  (cdecl)';

  FileEditH.Filter      := 'Fichiers Header C (*.h)|*.h|Tous les fichiers (*.*)|*.*';
  FileEditH.DialogTitle := 'Selectionner un fichier header C';

  RGLangage.Items.Clear;
  RGLangage.Items.Add('Pascal (FPC)');
  RGLangage.Items.Add('Python (ctypes)');
  RGLangage.ItemIndex := 0;

  EditDLL.Text  := 'malib.dll';
  EditUnit.Text := 'uMaLibBinding';

  MemoSource.Lines.BeginUpdate;
  MemoSource.Lines.Add('#ifndef MYLIB_H');
  MemoSource.Lines.Add('#define MYLIB_H');
  MemoSource.Lines.Add('');
  MemoSource.Lines.Add('#include <stdint.h>');
  MemoSource.Lines.Add('');
  MemoSource.Lines.Add('#define MYLIB_VERSION 200');
  MemoSource.Lines.Add('#define MAX_ITEMS     64');
  MemoSource.Lines.Add('');
  MemoSource.Lines.Add('typedef struct {');
  MemoSource.Lines.Add('  int32_t x;');
  MemoSource.Lines.Add('  int32_t y;');
  MemoSource.Lines.Add('  float   radius;');
  MemoSource.Lines.Add('} Circle;');
  MemoSource.Lines.Add('');
  MemoSource.Lines.Add('typedef enum {');
  MemoSource.Lines.Add('  ERR_OK   = 0,');
  MemoSource.Lines.Add('  ERR_FAIL = 1');
  MemoSource.Lines.Add('} ErrorCode;');
  MemoSource.Lines.Add('');
  MemoSource.Lines.Add('typedef struct MyHandle_t* MyHandle;');
  MemoSource.Lines.Add('');
  MemoSource.Lines.Add('int32_t     __cdecl mylib_add(int32_t a, int32_t b);');
  MemoSource.Lines.Add('MyHandle    __cdecl mylib_open(const char* filename);');
  MemoSource.Lines.Add('ErrorCode   __cdecl mylib_process(MyHandle h, Circle* c);');
  MemoSource.Lines.Add('void        __cdecl mylib_close(MyHandle h);');
  MemoSource.Lines.Add('const char* __cdecl mylib_version(void);');
  MemoSource.Lines.Add('');
  MemoSource.Lines.Add('#endif');
  MemoSource.Lines.EndUpdate;

  MemoLog.Lines.Add('Pret. Selectionnez un .h avec [...] ou collez votre source.');
  MemoLog.Lines.Add('Choisissez le langage cible puis cliquez CONVERTIR.');

  UpdateStatus;
end;

procedure TFormMain.AutoFillFromFileName(const AFileName: string);
var
  baseName: string;
begin
  baseName := ChangeFileExt(ExtractFileName(AFileName), '');
  if (EditDLL.Text = 'malib.dll') or (EditDLL.Text = '') then
    EditDLL.Text := LowerCase(baseName) + '.dll';
  if (EditUnit.Text = 'uMaLibBinding') or (EditUnit.Text = '') then
    EditUnit.Text := 'u' + baseName + 'Binding';
end;

procedure TFormMain.LoadHFile(const AFileName: string);
begin
  if not FileExists(AFileName) then Exit;
  MemoSource.Lines.LoadFromFile(AFileName);
  AutoFillFromFileName(AFileName);
  MemoLog.Clear;
  MemoLog.Lines.Add('Fichier charge : ' + AFileName);
  MemoLog.Lines.Add(IntToStr(MemoSource.Lines.Count) + ' lignes.');
  StatusBar1.Panels[0].Text := ExtractFileName(AFileName);
  UpdateStatus;
end;

procedure TFormMain.FileEditHChange(Sender: TObject);
begin
  if FileExists(FileEditH.FileName) then
    LoadHFile(FileEditH.FileName);
  UpdateStatus;
end;

procedure TFormMain.FileEditHAcceptFileName(Sender: TObject; var Value: string);
begin
  LoadHFile(Value);
end;

procedure TFormMain.UpdateStatus;
var
  hasSource : Boolean;
  hasResult : Boolean;
  modeLbl   : string;
begin
  hasSource := Trim(MemoSource.Text) <> '';
  hasResult := Trim(MemoResult.Text) <> '';

  BtnConvertirMain.Enabled := hasSource
                          and (Trim(EditDLL.Text) <> '')
                          and (Trim(EditUnit.Text) <> '');
  BtnSauver.Enabled  := hasResult;
  MenuSauver.Enabled := hasResult;

  StatusBar1.Panels[1].Text := 'DLL : ' + EditDLL.Text;

  if IsPascalMode then
  begin
    modeLbl := 'Mode : Pascal FPC';
    LblResult.Caption := 'Resultat .pas genere :';
    BtnSauver.Caption := 'Sauver le .pas...';
  end
  else
  begin
    modeLbl := 'Mode : Python ctypes';
    LblResult.Caption := 'Resultat .py genere :';
    BtnSauver.Caption := 'Sauver le .py...';
    // En Python, le nom d'unite devient le nom du module
    if (Length(EditUnit.Text) > 0) and (Copy(EditUnit.Text, 1, 1) = 'u') then
      { laisser tel quel, l utilisateur peut changer };
  end;

  StatusBar1.Panels[2].Text := modeLbl;
end;

procedure TFormMain.DoConvert;
var
  convPas : TH2PasConverter;
  convPy  : TH2PyConverter;
  src     : string;
  output  : string;
  i       : Integer;
  logList : TStringList;
begin
  Screen.Cursor := crHourGlass;
  try
    MemoResult.Clear;
    MemoLog.Clear;
    src := MemoSource.Text;

    if IsPascalMode then
    begin
      // ── Mode Pascal ──────────────────────────────────────────
      convPas := TH2PasConverter.Create;
      try
        output  := convPas.Convert(src, Trim(EditDLL.Text), Trim(EditUnit.Text));
        logList := convPas.ConversionLog;

        MemoResult.Lines.BeginUpdate;
        MemoResult.Text := output;
        MemoResult.Lines.EndUpdate;

        MemoLog.Lines.BeginUpdate;
        MemoLog.Lines.Add('=== Journal Pascal ===');
        for i := 0 to logList.Count - 1 do
          MemoLog.Lines.Add(logList[i]);
        MemoLog.Lines.EndUpdate;
      finally
        convPas.Free;
      end;
    end
    else
    begin
      // ── Mode Python ──────────────────────────────────────────
      convPy := TH2PyConverter.Create;
      try
        output  := convPy.Convert(src, Trim(EditDLL.Text));
        logList := convPy.ConversionLog;

        MemoResult.Lines.BeginUpdate;
        MemoResult.Text := output;
        MemoResult.Lines.EndUpdate;

        MemoLog.Lines.BeginUpdate;
        MemoLog.Lines.Add('=== Journal Python ===');
        for i := 0 to logList.Count - 1 do
          MemoLog.Lines.Add(logList[i]);
        MemoLog.Lines.EndUpdate;
      finally
        convPy.Free;
      end;
    end;

    StatusBar1.Panels[0].Text :=
      'Conversion OK  -  ' + IntToStr(MemoResult.Lines.Count) + ' lignes generees';
    UpdateStatus;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TFormMain.RGLangageClick(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TFormMain.BtnConvertirMainClick(Sender: TObject);
begin
  DoConvert;
end;

procedure TFormMain.BtnSauverClick(Sender: TObject);
begin
  MenuSauverClick(Sender);
end;

procedure TFormMain.BtnEffacerClick(Sender: TObject);
begin
  if MessageDlg('Effacer tout ?',
                'Voulez-vous effacer le source et le resultat ?',
                mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    FileEditH.FileName := '';
    MemoSource.Clear;
    MemoResult.Clear;
    MemoLog.Clear;
    EditDLL.Text  := 'malib.dll';
    EditUnit.Text := 'uMaLibBinding';
    StatusBar1.Panels[0].Text := 'Aucun fichier';
    MemoLog.Lines.Add('Efface. Pret pour une nouvelle conversion.');
    UpdateStatus;
  end;
end;

procedure TFormMain.MenuSauverClick(Sender: TObject);
var
  ext     : string;
  defName : string;
begin
  if Trim(MemoResult.Text) = '' then
  begin
    ShowMessage('Rien a sauvegarder. Convertissez d''abord un fichier .h.');
    Exit;
  end;

  ext     := OutputExtension;
  defName := EditUnit.Text + ext;

  if IsPascalMode then
    SaveDialog1.Filter := 'Fichiers Pascal (*.pas)|*.pas|Tous les fichiers (*.*)|*.*'
  else
    SaveDialog1.Filter := 'Scripts Python (*.py)|*.py|Tous les fichiers (*.*)|*.*';

  SaveDialog1.DefaultExt  := Copy(ext, 2, MaxInt);
  SaveDialog1.FileName    := defName;
  SaveDialog1.InitialDir  := ExtractFilePath(FileEditH.FileName);
  SaveDialog1.Title       := 'Sauvegarder le fichier genere';

  if SaveDialog1.Execute then
  begin
    MemoResult.Lines.SaveToFile(SaveDialog1.FileName);
    StatusBar1.Panels[0].Text := 'Sauvegarde : ' + ExtractFileName(SaveDialog1.FileName);
    MemoLog.Lines.Add('Fichier sauvegarde : ' + SaveDialog1.FileName);
  end;
end;

procedure TFormMain.EditDLLChange(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TFormMain.EditUnitChange(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TFormMain.MenuQuitterClick(Sender: TObject);
begin
  Close;
end;

procedure TFormMain.MenuAProposClick(Sender: TObject);
begin
  ShowMessage(
    'H2Pas Converter v1.1'                                            + LineEnding +
    'Convertisseur de header C (.h) vers binding Pascal ou Python'    + LineEnding +
    LineEnding +
    'Langages cibles :'                                               + LineEnding +
    '  Pascal : Free Pascal 3.2 / Lazarus  ->  unit .pas (external)' + LineEnding +
    '  Python : Python 3.x  ->  module .py (ctypes CDLL)'            + LineEnding +
    LineEnding +
    'Convention d''appel : cdecl'                                     + LineEnding +
    'Tutoriel : "Apprendre a binder une DLL C en Pascal"'
  );
end;

end.
