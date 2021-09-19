unit ResponseFormatterU;

interface

uses
  IdIcmpClient, System.SysUtils;

function FormatPingResponse(ReplyStatus: TReplyStatus; ADateTime: String): String;
function GetReplyStatusStr(ReplyStatus: TReplyStatus): String;

implementation

function FormatPingResponse(ReplyStatus: TReplyStatus; ADateTime: String): String;
Label Echo, Error, Timeout, Default;

begin
  try

    case ReplyStatus.ReplyStatusType of
      rsEcho: goto Echo;
      rsError: goto Error;
      rsTimeOut: goto Timeout;
      else goto Default;;
    end;

    Echo:
      Result:= Format(ADateTime + ': Reply from %s bytes=%d time=%d ms TTl=%d',
                      [ReplyStatus.FromIpAddress,
                      ReplyStatus.BytesReceived,
                      ReplyStatus.MsRoundTripTime,
                      ReplyStatus.TimeToLive]);
      Exit;

    Error:
      Result:= ADateTime + ': Ping failed, error code ' + IntToStr(Ord(ReplyStatus.ReplyStatusType));
      Exit;

    Timeout:
      Result:= ADateTime + ': Request timed out, msg: ' + GetReplyStatusStr(ReplyStatus);
      Exit;

    Default:
      Result:= ADateTime + ': Unknown. Code ' + IntToStr(Ord(ReplyStatus.ReplyStatusType));
      Exit;

  except
    raise Exception.Create('ResponseFormatterU.FormatPingResponse');
  end;
end;

function GetReplyStatusStr(ReplyStatus: TReplyStatus): String;
begin
  try
    case ReplyStatus.MsgType of
      0:  Result:= 'net unreachable';
      1:  Result:= 'host unreachable';
      2:  Result:= 'protocol unreachable';
      3:  Result:= 'port unreachable';
      4:  Result:= 'fragmentation needed';
      5:  Result:= 'source route failed';
    end;
  except
    raise Exception.Create('ResponseFormatterU.GetStrMsg');
  end;
end;

end.
