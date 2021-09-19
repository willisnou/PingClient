unit FileUtilsU;

interface

uses
  Classes, ShlObj, Windows, ShellAPI, System.SysUtils, System.Zip, System.IOUtils;

function OpenFolderAndSelectFile(AFileName: string): boolean;
function OpenFolderAndSelectFiles(AFiles: TStringList): boolean;
function BuildFilePath(APath, AFileName, AExtension: String): String;
function BuildPath: String;
function BuildZipFiles(AFiles: TStringList; APath: String; ADeleteSource: boolean = False): string;
function AddrFromFile(AFile: String): TStringList;
function GenerateTempDir: String;
function LoadTextFile(AFilePath: String): TFileStream;

const
  // dwflags //
  OFASI_EDIT        = $0001;
  OFASI_OPENDESKTOP = $0002;
  // defs //
  C_DEF_DIR_NAME    = 'Temp';
  C_ZIP_FILENAME    = 'PINGs.zip';
  C_DEF_FILE_EXT    = 'log';

implementation

{$IFDEF UNICODE}
function ILCreateFromPath(pszPath: PChar): PItemIDList stdcall; external shell32
  name 'ILCreateFromPathW';
{$ELSE}
function ILCreateFromPath(pszPath: PChar): PItemIDList stdcall; external shell32
  name 'ILCreateFromPathA';
{$ENDIF}
procedure ILFree(pidl: PItemIDList) stdcall; external shell32;
function SHOpenFolderAndSelectItems(pidlFolder: PItemIDList; cidl: Cardinal;
  apidl: pointer; dwFlags: DWORD): HRESULT; stdcall; external shell32;

function OpenFolderAndSelectFile(AFileName: string): boolean;
var
  IIDL: PItemIDList;
begin
  try
    Result:= False;
    IIDL:= ILCreateFromPath(PWideChar(AFileName));
    if IIDL <> nil then
      try
        Result := SHOpenFolderAndSelectItems(IIDL, 0, nil, 0) = S_OK;
      finally
        ILFree(IIDL);
      end;
  except
    raise Exception.Create('FileUtisU.OpenFolderAndSelectFile');
  end;
end;

function OpenFolderAndSelectFiles(AFiles: TStringList): boolean;
var
  IIDLs: array of PItemIDList;
  IIDL: PItemIDList;
  I, J: Integer;
  lPath: String;
begin
  Result:= False;
  if not (AFiles.Count > 0) then
    Exit;
  lPath:= EmptyStr;
  IIDL:= nil;
  try
    SetLength(IIDLs, AFiles.Count);
    try
      // files //
      for I := 0 to AFiles.Count-1 do
        IIDLs[I]:= ILCreateFromPath(PWideChar(AFiles[I]));
      // folders //
      lPath:= ExtractFilePath(AFiles[0]);
      IIDL:= ILCreateFromPath(PWideChar(lPath));
      Result:= SHOpenFolderAndSelectItems(IIDL, Length(IIDLs)+1, IIDLs, 0) = S_OK;
    finally
      ILFree(IIDL);
      for J := 0 to Length(IIDLs)-1 do
        ILFree(IIDLs[J]);
    end;
  except
    raise Exception.Create('FileUtilsU.OpenFolderAndSelectFiles');
  end;
end;

function BuildFilePath(APath, AFileName, AExtension: String): String;
begin
  Result:= EmptyStr;
  try
    Result:= IncludeTrailingPathDelimiter(APath) + AFileName + '.' + AExtension;
  except
    raise Exception.Create('FileUtilsU.BuildFilePath');
  end;
end;

function BuildPath: String;
begin
  Result:= EmptyStr;
  try
    Result:= GetEnvironmentVariable('APPDATA') + IncludeTrailingPathDelimiter(Result) + C_DEF_DIR_NAME;
  except
    raise Exception.Create('FileUtilsU.BuildPath');
  end;
end;

function BuildZipFiles(AFiles: TStringList; APath: String; ADeleteSource: boolean = False): string;
var
  nZip: TZipFile;
  I: Integer;
  lAux: String;
  J: Integer;
begin
  Result:= EmptyStr;
  try
    nZip:= TZipFile.Create;
    try
        lAux:= IncludeTrailingPathDelimiter(APath) + C_ZIP_FILENAME;
        nZip.Open(lAux, zmWrite);
        for I := 0 to AFiles.Count-1 do
          nZip.Add(AFiles[I]);
        Result:= lAux;

        if ADeleteSource then
        begin
          for J := 0 to AFiles.Count-1 do
            TFile.Delete(AFiles[J]);
        end;
      finally
        FreeAndNil(nZip);
      end;
  except
    raise Exception.Create('FileUtilsU.BuildZipFiles');
  end;
end;

function AddrFromFile(AFile: String): TStringList;
var
  lFile: TFileStream;
  slAux: TStringList;
begin
  Result:= nil;
  try
    if AFile = EmptyStr then
      Exit;

    lFile:= TFileStream.Create(AFile, fmOpenRead, fmShareDenyWrite);
    slAux:= TStringList.Create;
    try
      slAux.LoadFromStream(lFile);
      Result:= slAux;
    finally
      freeAndNil(lFile);
    end;
  except
    raise Exception.Create('FileUtilsU.AddrFromFile');
  end;
end;

function GenerateTempDir: String;
var
  lAux: String;
begin
  try
    lAux:= BuildPath;
    if not (TDirectory.Exists(lAux)) then
      ForceDirectories(lAux);
    Result:= lAux;
  except
    raise Exception.Create('FileUtilsU.GenerateTempDir');
  end;
end;

function LoadTextFile(AFilePath: String): TFileStream;
var
  lAux: TFileStream;
begin
  try
    if not TFile.Exists(AFilePath) then
      lAux:= TFile.Create(AFilePath)
    else
      lAux:= TFile.Open(AFilePath, TFileMode.fmOpenOrCreate);
    lAux.Seek(0, soFromEnd);

    Result:= lAux;
  except
    raise Exception.Create('FileUtilsU.LoadTextFile');
  end;
end;

end.
