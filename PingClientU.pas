unit PingClientU;

interface

uses
  System.SysUtils, System.Classes, Generics.Collections, IdGlobal, IdBaseComponent, IdComponent,
  IdRawBase, IdRawClient, IdIcmpClient, StrUtils, ResponseFormatterU,
  FileUtilsU;

type
  TUpdateCallback         = procedure(AStr: String)             of object;
  TUpdateResponseCallback = procedure(AHost, AResponse: String) of object;

  PingType   = (ptInfinite, ptTimeout);
  StatusType = (stDone, stInProgress, stNotStarted);

  TPingThread = Class (TThread)
    private
      FHost  : String;
      FClient: TIdIcmpClient;
      FType  : PingType;

      procedure SetDefaults;
    protected
      procedure Execute; override;
      procedure HandledPingResponse(Sender: TComponent; const ReplyStatus: TReplyStatus);
      procedure SynchronizedResponse(ReplyStatus: TReplyStatus; ADateTime: String); virtual; abstract;

    public
      constructor Create(AHost: String; APingType: PingType = ptTimeout);

      destructor Destroy; override;
  End;

  TPingClient = Class
    private
      FAddrList        : TStringList;
      FFormatedAddrList: TStringList;
      FType            : PingType;
      FPath            : String;
      FStatusList      : TDictionary<String, StatusType>;
      FThreadList      : TDictionary<String, TObject>;
      FResponseCallback: TUpdateResponseCallback;   // every ping response //
      FFinalizeCallback: TUpdateCallback;           // when ping ends //

      procedure UpdateStatusCallback(AStr: String); // internal status "setter" //

      function GetFormatedAddrList: TStringList;
      function GetTerminated: boolean;
      function GetStatus: StatusType;

    type
      TPinger = Class(TPingThread)
        private
          FPath            : String;
          FFile            : TFileStream;
          FFilePath        : String;
          FFinalizeCallback: TUpdateCallback;
          FStatusCallback  : TUpdateCallback;
          FResponseCallback: TUpdateResponseCallback;
          procedure AppendLine(AText: String);
          procedure FinalizeCallback;
          procedure StatusCallback;
        protected
          procedure SynchronizedResponse(ReplyStatus: TReplyStatus; ADateTime: String); override;
          destructor Destroy; override;
        public
          constructor Create(AHost, APath: String; APingType: PingType;
                             AFinalizeCallback: TUpdateCallback = nil;
                             AStatusCallback: TUpdateCallback = nil;
                             AResponseCallback: TUpdateResponseCallback = nil);
      end;

    public
      function Ping: boolean;
      function OpenFiles: boolean;
      function OpenZipped(ADeleteSource: boolean = False): boolean;

      procedure SetFinalizeCallback(AFinalizeCallback: TUpdateCallback);
      procedure SetResponseCallback(ACallback: TUpdateResponseCallback);
      procedure SetPingType(APingType: PingType);
      procedure SetAddrs(AAddrs: TStringList);
      procedure SetPath(APath: String); // override def path, if want

      procedure AddAddr(AAddr: String);
      procedure Terminate;

      property Status          : StatusType              read GetStatus; //checar
      property Terminated      : Boolean                 read GetTerminated; //checar
      property Addrs           : TStringList             read FAddrList         write SetAddrs; //checar
      property PingType        : PingType                read FType             write SetPingType; //checar
      property Path            : String                  read FPath             write SetPath;
      property ResponseCallback: TUpdateResponseCallback read FResponseCallback write SetResponseCallback;
      property FinalizeCallback: TUpdateCallback         read FFinalizeCallback write SetFinalizeCallback;

      constructor Create(AHosts: TStringList; APingType: PingType;
                         AFinalizeCallback: TUpdateCallback;
                         AResponseCallback: TUpdateResponseCallback); overload;
      constructor Create; overload;

      destructor Destroy; override;
  End;

implementation

{ TPingThread }

constructor TPingThread.Create(AHost: String; APingType: PingType = ptTimeout);
begin
  inherited Create(False);
  try
    FreeOnTerminate:= True;
    FHost          := AHost;
    FType          := APingType;
    FClient        := TIdIcmpClient.Create(nil);
    SetDefaults;
  except
    raise Exception.Create('PingU.Create');
  end;
end;

destructor TPingThread.Destroy;
begin
  inherited;
  try
    if Assigned(FClient) then
      FreeAndNil(FClient);
  except
    raise Exception.Create('PingU.Destroy');
  end;
end;

procedure TPingThread.Execute;
var
  I: Integer;
  Label Infinite, Timeout;
begin
  try
    case FType of
      ptInfinite: goto Infinite;
      ptTimeout: goto Timeout;
    end;

    Infinite:
      while not (Terminated) do
      begin
        // workaround (indy10) bug? https://stackoverflow.com/questions/12723081/delphi-indy-ping-error-10040
        FClient.Ping(StringOfChar(#0, FClient.PacketSize));
        Sleep(1000);
      end;
    Exit;


    Timeout:
      for I := 0 to 3 do
      begin
        // workaround (indy10) bug? https://stackoverflow.com/questions/12723081/delphi-indy-ping-error-10040
        FClient.Ping(StringOfChar(#0, FClient.PacketSize));
        Sleep(1000);
      end;
    Exit;
  except
    raise Exception.Create('PingU.Execute');
  end;
end;

procedure TPingThread.HandledPingResponse(Sender: TComponent; const ReplyStatus: TReplyStatus);
var
  lDate: String;
begin
  try
    lDate:= EmptyStr;
    DateTimeToString(lDate, 'dd/mm/yyyy hh:nn:ss.zzz', Now);
    SynchronizedResponse(ReplyStatus, lDate);
  except
    raise Exception.Create('PingU.HandlePingresponse');
  end;
end;

procedure TPingThread.SetDefaults;
begin
  try
    FClient.Host   := FHost;
    FClient.OnReply:= HandledPingResponse;
    // defs //
    FClient.IPVersion     := Id_IPv4;
    FClient.PacketSize    := 32;
    FClient.ReceiveTimeout:= 1000;
  except
    raise Exception.Create('PingClientU.TPingThread.SetDefaults');
  end;
end;

{ TPingClient }

constructor TPingClient.Create(AHosts: TStringList; APingType: PingType;
                               AFinalizeCallback: TUpdateCallback;
                               AResponseCallback: TUpdateResponseCallback);
begin
  try
    Create;
    if Assigned(AHosts) then
      FAddrList:= AHosts;
    FType:= APingType;
    if Assigned(AFinalizeCallback) then
      AFinalizeCallback:= AFinalizeCallback;
    if Assigned(AResponseCallback) then
      FResponseCallback:= AResponseCallback;
  except
    raise Exception.Create('PingClientU.CreateArgs');
  end;
end;

constructor TPingClient.Create;
begin
  try
    FAddrList        := TStringList.Create;
    FType            := ptTimeout;
    FStatusList      := TDictionary<String, StatusType>.Create;
    FThreadList      := TDictionary<String, TObject>.Create;
    FPath            := GenerateTempDir;
    FFinalizeCallback:= nil;
    FResponseCallback:= nil;

    if Assigned(FFormatedAddrList) then  // just in case - must be create in GetFormatedAddrList //
      FreeAndNil(FFormatedAddrList);

    FThreadList.Clear;
    FStatusList.Clear;
  except
    raise Exception.Create('PingClientU.Create');
  end;
end;

destructor TPingClient.Destroy;
begin
  try
    if Assigned(FAddrList) then
      FreeAndNil(FAddrList);
    if Assigned(FFormatedAddrList) then
      FreeAndNil(FFormatedAddrList);
    if Assigned(FStatusList) then
      FreeAndNil(FStatusList);
    if Assigned(FThreadList) then
      FreeAndNil(FThreadList);
  except
    raise Exception.Create('PingClientU.Destroy');
  end;
end;

procedure TPingClient.Terminate;
var
  I: Integer;
  nObj: TObject;
  st: StatusType;
begin
  try
    for I := 0 to FAddrList.Count-1 do
    begin
      FStatusList.TryGetValue(FAddrList[i], st);
      if not (st = stDone) then
      begin
        FThreadList.TryGetValue(FAddrList[i], nObj);
        (nObj as TPinger).Terminate;
      end;
    end;
  except
    raise Exception.Create('PingClientU.Terminate');
  end;
end;

function TPingClient.GetFormatedAddrList: TStringList;
var
  I: Integer;
begin
  try
    if not Assigned(FAddrList) then
    begin
      FFormatedAddrList:= TStringList.Create;
      FFormatedAddrList.Add('Addr list empty.');
      Result:= FFormatedAddrList;
      Exit;
    end;

    if Assigned(FFormatedAddrList) and not (FAddrList.Count > 0) then
    begin
      Result:= FFormatedAddrList;
      Exit;
    end;

    FFormatedAddrList:= TStringList.Create;
    FFormatedAddrList.Assign(FAddrList);
    for I := 0 to FFormatedAddrList.Count-1 do
    begin
      FFormatedAddrList[I]:= BuildFilePath(BuildPath, FFormatedAddrList[I], C_DEF_FILE_EXT);
    end;
    Result:= FFormatedAddrList;

  except
    raise Exception.Create('PingClientU.GetFormatedList');
  end;
end;

function TPingClient.OpenFiles: boolean;
begin
  Result:= false;
  try
    if not (Status = stDone) then
      Exit;
    Result:= OpenFolderAndSelectFiles(GetFormatedAddrList);
  except
    raise Exception.Create('PingClientU.OpenFiles');
  end;
end;

procedure TPingClient.AddAddr(AAddr: String);
begin
  try
    if Assigned(FAddrList) and (AAddr <> EmptyStr) then
      FAddrList.Add(AAddr);
    if Assigned(FStatusList) then
      FStatusList.AddOrSetValue(AAddr, stNotStarted);
  except
    raise Exception.Create('PingClientU.Add');
  end;
end;

function TPingClient.Ping: boolean;
var
  I: Integer;
begin
  Result:= False;
  try
    if not (FAddrList.Count > 0) then
      Exit;

    for I := 0 to FAddrList.Count - 1 do
    begin
      FThreadList.AddOrSetValue(FAddrList.Strings[i], TPinger.Create(FAddrList.Strings[I], FPath, FType, FFinalizeCallback, UpdateStatusCallback, FResponseCallback));
      FStatusList.AddOrSetValue(FAddrList.Strings[I], stInProgress);
    end;
    Result:= True;
  except
    raise Exception.Create('PingClientU.Ping');
  end;
end;

procedure TPingClient.SetAddrs(AAddrs: TStringList);
var
  I: Integer;
begin
  if not (AAddrs.Count > 0) then
    Exit;
  try
    FAddrList:= AAddrs;
    for I := 0 to FAddrList.Count-1 do
      FStatusList.AddOrSetValue(FAddrList.Strings[I], stNotStarted);
  except
    raise Exception.Create('PingClientU.SetAddrs');
  end;
end;

procedure TPingClient.SetFinalizeCallback(AFinalizeCallback: TUpdateCallback);
begin
  if not (Assigned(AFinalizeCallback)) then
    Exit;
  try
    FFinalizeCallback:= AFinalizeCallback;
  except
    raise Exception.Create('PingClientU.SetFinalizeCallback');
  end;
end;

procedure TPingClient.SetPath(APath: String);
begin
  if Trim(APath) = EmptyStr then
    Exit;
  try
    FPath:= APath;
  except
    raise Exception.Create('PingClientU.SetPath');
  end;
end;

procedure TPingClient.SetPingType(APingType: PingType);
begin
  try
    FType:= APingType;
  except
    raise Exception.Create('PingClientU.SetPingType');
  end;
end;

procedure TPingClient.SetResponseCallback(ACallback: TUpdateResponseCallback);
begin
  if not Assigned(ACallback) then
    Exit;
  try
    FResponseCallback:= ACallback;
  except
    raise Exception.Create('PingClientU.SetResponseCallback');
  end;
end;

function TPingClient.GetTerminated: boolean;
begin
  try
    Result:= not (FStatusList.ContainsValue(stNotStarted)) and not (FStatusList.ContainsValue(stInProgress));
  except
    raise Exception.Create('PingClientU.GetTerminated');
  end;
end;

function TPingClient.GetStatus: StatusType;
begin
  Result:= stInProgress;
  try
    // if have any in progress, we need wait //
    if FStatusList.ContainsValue(stInProgress) then
    begin
      Result:= stInProgress;
      //Exit;
    end;
    // not started if not in progress and not done //
    if not (FStatusList.ContainsValue(stInProgress)) and not (FStatusList.ContainsValue(stDone)) then
    begin
      Result:= stNotStarted;
      //Exit;
    end;
    // just is done/terminated when nothing is in progress //
    if not (FStatusList.ContainsValue(stInProgress)) and not (FStatusList.ContainsValue(stNotStarted)) then
    begin
      Result:= stDone;
      //Exit;
    end;
  except
    raise Exception.Create('PingClientU.GetStatus');
  end;
end;

procedure TPingClient.UpdateStatusCallback(AStr: String);
begin
  FStatusList.AddOrSetValue(AStr, stDone);
end;

function TPingClient.OpenZipped(ADeleteSource: boolean = False): boolean;
begin
  Result:= false;
  try
    if not (Status = stDone) then
      Exit;
    Result:= OpenFolderAndSelectFile(BuildZipFiles(GetFormatedAddrList, FPath, ADeleteSource));
  except
    raise Exception.Create('PingClientU.OpenZipped');
  end;
end;

{ TPingClient.TPinger }

procedure TPingClient.TPinger.AppendLine(AText: String);
const
  EOL = #13#10;
begin
  try
    FFile.Write(TEncoding.UTF8.GetBytes(AText), Length(AText));
    FFile.Seek(0, soFromEnd);
    FFile.Write(TEncoding.UTF8.GetBytes(EOL), Length(EOL));
    FFile.Seek(0, soFromEnd);
  except
    raise Exception.Create('PingClientU.TPinger.AppendLine');
  end;
end;

procedure TPingClient.TPinger.StatusCallback;
begin
  try
    FStatusCallback(FHost);
  except
    raise Exception.Create('PingClientU.TPinger.StatusCallback');
  end;
end;

procedure TPingClient.TPinger.SynchronizedResponse(
  ReplyStatus: TReplyStatus; ADateTime: String);
var
  lAux: String;
begin
  lAux:= EmptyStr;
  try
    lAux:= FormatPingResponse(ReplyStatus, ADateTime);
    AppendLine(lAux);
    if Assigned(FResponseCallback) then
      FResponseCallback(FHost, lAux);
  except
    raise Exception.Create('PingClientU.TPinger.SynchronizedResponse');
  end;
end;

procedure TPingClient.TPinger.FinalizeCallback;
begin
  try
    if Assigned(FFinalizeCallback) then
      FFinalizeCallback(FHost);
  except
    raise Exception.Create('PingClientU.TPinger.FinalizeCallback');
  end;
end;

constructor TPingClient.TPinger.Create(AHost, APath: String; APingType: PingType;
                                       AFinalizeCallback: TUpdateCallback;
                                       AStatusCallback: TUpdateCallback;
                                       AResponseCallback: TUpdateResponseCallback);
begin
  try
    inherited Create(AHost, APingType);
    Self.FreeOnTerminate:= True;
    FPath               := APath;
    FFinalizeCallback   := AFinalizeCallback;
    FStatusCallback     := AStatusCallback;
    FResponseCallback   := AResponseCallback;
    FFilePath           := BuildFilePath(FPath, FHost, C_DEF_FILE_EXT);
    FFile               := LoadTextFile(FFilePath);
  except
    raise Exception.Create('PingClientU.TPinger.Create');
  end;
end;

destructor TPingClient.TPinger.Destroy;
begin
  try
    if Assigned(FFinalizeCallback) then
      Synchronize(FinalizeCallback);
    if Assigned(FStatusCallback) then
      Synchronize(StatusCallback);
    if Assigned(FFile) then
      FreeAndNil(FFIle);

    inherited Destroy;
  except
    raise Exception.Create('PingClientU.TPinger.Destroy');
  end;
end;

end.
