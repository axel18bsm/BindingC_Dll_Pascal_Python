program H2PasConverter;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces,  { This line is needed for LCL widgetset }
  Forms,
  uMainForm,
  uH2PasConverter;

{ {$R *.res} }  { Decommenter apres que Lazarus ait genere le .res }

begin
  RequireDerivedFormResource := True;
  Application.Scaled         := True;
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
