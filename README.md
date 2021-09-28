# PingClient
Ping client multithread com resposta salva em relatório.

## Uso
É necessário apenas instanciar um objeto do tipo TPingClient passando diretamente todos os parâmetros, ou adicionando manualmente depois de instanciar, conforme abaixo. Por padrão é executado um ping com 4 respostas, mas é possível alterar o tipo para execução indeterminada (loop) até que seja finaliza.

```pascal
var lClient: TPingClient;
begin
  lClient:= TPingClient.Create;
  
  lClient.AddAddr('google.com');
  lClient.AddAddr('amazon.com');
  lClient.AddAddr('github.com');
  
  lClient.SetFinalizeCallback(onFinalizeCallback);
  lClient.SetResponseCallback(onResponseCallback);
  
  //lClient.SetPingType(ptInfinite);
  
  lClient.Ping;
end;
```

## Callbacks
Foi utilizado callbacks para executar ações em determinados eventos.

#### TUpdateResponseCallback 
É executada a cada resposta de ping recebida.
```pascal
TUpdateCallback = procedure(AStr: String) of object;
```

#### TUpdateCallback
É executada quando o processo de ping é finalizado. 
Internamente também foi inserido um controle de status dos endereços que estão sendo "pingados" e suas respectivas threads, permitindo que os processos sejam finalizados manualmente pelo método <b>Terminate</b>.
```pascal
TUpdateResponseCallback = procedure(AHost, AResponse: String) of object;
```
