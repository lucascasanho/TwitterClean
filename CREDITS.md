# Créditos e referências

O código do TwitterClean foi escrito especificamente para este repositório. Não há bibliotecas externas nem código de terceiros incorporado ao projeto.

## Formato e obtenção do arquivo do X

1. **X Help Center — Como baixar seu arquivo do X**  
   https://help.x.com/pt/managing-your-account/how-to-download-your-x-archive  
   Referência oficial para solicitar e baixar uma cópia dos dados da conta.

2. **seramo/twitter-archive-docs — documentação comunitária do formato do arquivo**  
   https://github.com/seramo/twitter-archive-docs  
   Referência comunitária para a estrutura dos registros following.js, incluindo os campos accountId e userLink. O X não publica esse formato como um esquema formal estável; por isso, o programa valida os campos encontrados e trata informações ausentes como inconclusivas.

## Tecnologias utilizadas

3. **Microsoft — PowerShell documentation**  
   https://learn.microsoft.com/powershell/  
   Documentação oficial da linguagem e dos recursos de execução do PowerShell utilizados pelo projeto.

4. **Microsoft .NET — System.IO.Compression.ZipFile**  
   https://learn.microsoft.com/dotnet/api/system.io.compression.zipfile  
   Documentação oficial da API .NET usada para ler arquivos ZIP localmente.

5. **Microsoft .NET — System.Uri**  
   https://learn.microsoft.com/dotnet/api/system.uri  
   Documentação oficial da API .NET usada para validar esquemas e domínios dos links antes de exibi-los no relatório HTML.

## Escopo de privacidade

O projeto é inteiramente local. Não utiliza a API do X, OAuth, cookies, senhas, tokens ou automação do website. Não realiza requisições de rede e não executa ações de seguir ou deixar de seguir.

Os testes automatizados usam registros fictícios criados temporariamente durante a execução.
