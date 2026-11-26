# TwitterClean

Ferramenta local em PowerShell para analisar a lista de contas seguidas registrada no arquivo oficial de dados do X.

**Versão:** 0.1.0  
**Plataforma:** Windows PowerShell 5.1 ou PowerShell 7+  
**Dependências:** nenhuma dependência externa

## O que faz

- Lê o arquivo ZIP oficial do X, uma pasta extraída ou diretamente o arquivo following.js.
- Consolida os arquivos following*.js encontrados no arquivo.
- Conta registros e IDs únicos e identifica registros duplicados.
- Sinaliza entradas sem userLink como candidatas a revisão manual.
- Gera relatórios locais em HTML, CSV e JSON.
- Compara a quantidade de IDs do arquivo com o contador de seguindo exibido no X, quando informado.

O relatório HTML cria links para abrir cada perfil pelo ID da conta. A conferência do estado do perfil é manual.

## O que não faz

- Não pede nem armazena senha, cookies, token ou chave de API.
- Não acessa o X pela rede e não lê a sessão do navegador.
- Não confirma automaticamente se uma conta está suspensa, desativada, protegida ou se o vínculo de seguimento continua ativo.
- Não executa follow ou unfollow.
- Não automatiza cliques, chamadas internas do X ou ações em massa.

Essa limitação é intencional. As regras oficiais de automação do X proíbem scripts que automatizam o próprio site e proíbem seguir/deixar de seguir contas de maneira em massa, agressiva ou indiscriminada. O X informa que violações podem levar a medidas na conta, inclusive suspensão. Consulte [Regras de automação do X](https://help.x.com/en/rules-and-policies/x-automation) e [Regras sobre seguir](https://help.x.com/en/using-x/x-follow-limit).

## Como obter o arquivo do X

1. Entre no X.
2. Abra **Configurações e privacidade**.
3. Entre em **Sua conta**.
4. Escolha **Baixar um arquivo com seus dados**.
5. Confirme sua identidade e solicite o arquivo.
6. Quando o X disponibilizar o download, baixe o ZIP para o computador.

O X informa que a preparação do arquivo pode levar alguns dias. Consulte o guia oficial: [Como baixar seu arquivo do X](https://help.x.com/pt/managing-your-account/how-to-download-your-x-archive).

**Privacidade:** o arquivo do X pode conter mensagens diretas, dados de conta e outras informações pessoais. Não envie o ZIP, nem os relatórios gerados, para este repositório ou serviços de terceiros. O TwitterClean processa o arquivo localmente.

## Como executar no Windows

1. Baixe o repositório pelo botão **Code > Download ZIP** no GitHub e extraia a pasta. Também é possível cloná-lo com Git:

        git clone https://github.com/lucascasanho/TwitterClean.git
        cd TwitterClean

2. Abra o PowerShell dentro da pasta do projeto.

3. Libere a execução de scripts somente para a janela atual do PowerShell:

        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

4. Execute apontando para o ZIP do arquivo do X. Ajuste o caminho e informe o contador que aparece no seu perfil:

        .\TwitterClean.ps1 -ArchivePath "$HOME\Downloads\twitter-archive.zip" -DisplayedFollowingCount 50

O parâmetro -DisplayedFollowingCount é opcional. Troque 50 pelo número mostrado no seu perfil do X.

Também é possível apontar para a pasta extraída:

        .\TwitterClean.ps1 -ArchivePath "$HOME\Downloads\twitter-archive\data" -DisplayedFollowingCount 50

Ou para o próprio arquivo:

        .\TwitterClean.ps1 -ArchivePath "$HOME\Downloads\twitter-archive\data\following.js"

O relatório HTML será aberto automaticamente. Para não abrir o navegador:

        .\TwitterClean.ps1 -ArchivePath "$HOME\Downloads\twitter-archive.zip" -NoOpenReport

Para escolher uma pasta de saída:

        .\TwitterClean.ps1 -ArchivePath "$HOME\Downloads\twitter-archive.zip" -OutputDirectory "$HOME\Desktop\TwitterClean-Relatorio"

Não é necessário executar o PowerShell como administrador.

## Como interpretar o relatório

- **IDs únicos:** quantidade de contas distintas registradas no arquivo.
- **Registros duplicados:** ocorrências repetidas do mesmo ID dentro dos arquivos lidos.
- **IDs sem userLink:** entradas sem o campo userLink. Isso pode ser um indício de perfil indisponível ou protegido, mas também pode ser dado incompleto. Não prova suspensão ou desativação.
- **Não verificada:** o arquivo contém um userLink, mas isso não comprova que o perfil ou o vínculo ainda estejam ativos hoje.
- **Diferença:** contador informado no X menos IDs únicos registrados no arquivo.

O arquivo exportado é uma fotografia dos dados da conta no momento em que foi preparado. Ele não é uma consulta em tempo real. Para descobrir o estado atual, abra os perfis indicados e confira a mensagem apresentada pelo próprio X.

## Testes

Com PowerShell 5.1 ou 7+:

        .\tests\Test-TwitterClean.ps1

Os testes usam dados fictícios temporários e não acessam sua conta nem a internet.

## Estrutura

    TwitterClean/
    ├── src/
    │   └── TwitterClean.psm1
    ├── tests/
    │   └── Test-TwitterClean.ps1
    └── TwitterClean.ps1

## Estado do projeto

Esta é a primeira versão, focada em leitura e diagnóstico offline. A ferramenta não altera sua conta do X.
