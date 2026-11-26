# TwitterClean

Ferramenta local em PowerShell para diagnosticar divergências na lista de contas seguidas do X.

**Versão:** 0.2.0  
**Plataforma:** Windows PowerShell 5.1 ou PowerShell 7+  
**Dependências:** nenhuma biblioteca externa

## Escolha o modo

### Modo online (recomendado)

Consulta a lista atual de contas seguidas pela API oficial do X. Não depende de um novo arquivo de dados. Usa OAuth 2.0 com PKCE e permissões de leitura.

O programa:
- autentica no X sem pedir sua senha;
- consulta seu próprio perfil e o contador following_count informado pela API;
- consulta até 100 contas por padrão, com limite configurável;
- pagina os resultados dentro do limite;
- registra erros que a API devolver;
- opcionalmente compara os IDs retornados com um arquivo antigo;
- gera relatórios HTML, CSV e JSON.

**Atenção:** a documentação do X não garante que contas suspensas ou vínculos ocultos apareçam como usuários na resposta de Following. Quando existe uma diferença entre o contador e os perfis retornados, o programa pode medir a divergência, mas não inventa os IDs que a API não forneceu. Um usuário ausente da resposta não é automaticamente classificado como suspenso.

### Modo offline

Lê o ZIP de dados antigo do X, uma pasta extraída ou diretamente following.js. Consolida IDs, encontra duplicidades e gera relatórios locais. É útil como fonte histórica, mas não substitui uma consulta atual.

## Antes de usar o modo online

O acesso à API do X exige uma conta de desenvolvedor e um aplicativo aprovado. A API usa cobrança por uso, com compra antecipada de créditos. Não é uma assinatura mensal, mas consultas podem gerar custos. Veja os valores atuais no [portal oficial de preços](https://docs.x.com/x-api/getting-started/pricing).

O endpoint GET /2/users/{id}/following custa atualmente US$ 0,010 por perfil retornado na tarifa padrão. A tabela oficial lista esse endpoint entre os Owned Reads, que podem custar US$ 0,001 por perfil quando o aplicativo pertence ao mesmo desenvolvedor da conta autenticada. O programa mostra uma estimativa antes de consultar. Confirme as tarifas e o saldo no Developer Console antes de continuar.

## Configurar o aplicativo no X (uma única vez)

1. Abra o [X Developer Console](https://developer.x.com/en/portal/dashboard) e entre com a mesma conta do X que será analisada.
2. Crie um Project e um App, caso ainda não tenha.
3. Nas configurações de autenticação do App, habilite **OAuth 2.0**.
4. Escolha o tipo **Native App** (cliente público). O TwitterClean usa PKCE e não precisa de Client Secret.
5. Configure as permissões do aplicativo como **Read**.
6. Adicione este Callback / Redirect URL exatamente:

        http://127.0.0.1:8787/callback/

7. Salve as configurações e copie o **Client ID** em Keys and Tokens.

O TwitterClean solicita somente os escopos de leitura users.read, follows.read e tweet.read. Ele não solicita follows.write, não solicita offline.access e não precisa do Client Secret.

**Não cole Client Secret, senha, token ou chave privada no chat nem no GitHub.** O Client ID não é uma senha; o programa o solicita no PowerShell. O token de acesso é mantido somente na memória durante a execução e não é gravado em arquivo.

Se o portal do X não aceitar o Redirect URL local, não desative as validações nem use outro endereço por conta própria. Pare e confira as instruções atuais do X antes de continuar.

## Executar o modo online no Windows

1. Baixe o projeto pelo botão **Code > Download ZIP** do GitHub e extraia a pasta. Ou clone com Git:

        git clone https://github.com/lucascasanho/TwitterClean.git
        cd TwitterClean

2. Abra o PowerShell dentro da pasta extraída.

3. Permita scripts somente nesta janela do PowerShell:

        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

4. Execute:

        .\TwitterClean-Online.ps1 -DisplayedFollowingCount 50

Troque 50 pelo número que aparece no contador do seu perfil. O programa pedirá o Client ID se ele não for informado.

5. Leia a estimativa de custo. Para continuar, digite CONTINUAR. Qualquer outra resposta cancela a execução antes da chamada à API.
6. O navegador será aberto na página oficial do X. Confira a conta e autorize as permissões de leitura.
7. Volte ao PowerShell. Ao terminar, o relatório HTML será aberto automaticamente.

O limite padrão é 100 perfis por execução. Para alterar esse limite:

        .\TwitterClean-Online.ps1 -DisplayedFollowingCount 50 -MaxAccounts 250

Quanto maior o limite, maior poderá ser o custo. A consulta para quando atinge o limite ou termina as páginas disponíveis.

### Comparar também com o arquivo antigo

Se ainda tiver o ZIP incompleto, passe seu caminho opcionalmente:

        .\TwitterClean-Online.ps1 -DisplayedFollowingCount 50 -ArchivePath "$HOME\Downloads\twitter-archive.zip"

O relatório separa contas que aparecem no arquivo antigo mas não foram retornadas pela consulta atual. Isso pode significar vínculo removido, conta indisponível ou diferença de datas; não prova suspensão.

### Onde ficam os relatórios

O programa cria uma pasta TwitterClean-Online-AAAA... no diretório atual, com:
- diagnostic.html: relatório para abrir no navegador;
- following-online.csv: perfis e candidatos encontrados;
- diagnostic.json: resposta estruturada;
- api-errors.json: erros fornecidos pela API.

Não publique esses relatórios. Eles contêm IDs e informações da sua rede de contatos.

## Como interpretar o resultado online

- **Contas retornadas:** perfis que o endpoint de Following devolveu.
- **Contador na API:** public_metrics.following_count do seu perfil, quando fornecido.
- **Diferença:** contador do perfil menos perfis únicos retornados.
- **Erros da API:** mensagens que o X retornou junto com a lista. Se houver ID ou código de recurso, ele será preservado no arquivo JSON.
- **Candidatos do arquivo antigo:** IDs do arquivo histórico que não aparecem na consulta atual.
- **Consulta limitada:** indica que o limite configurado foi atingido antes do fim de todas as páginas.

Se o contador indicar 50 e a API retornar zero, o programa registra uma divergência de 50. Isso não significa que saiba quais são as 50 contas: o endpoint não fornece os IDs ausentes nesse caso. O próximo passo é encaminhar o relatório de contagem ao suporte do X ou usar os IDs históricos que ainda existirem no arquivo antigo.

## Limite de automação

O TwitterClean não executa unfollow. As regras oficiais do X proíbem unfollow automatizado em massa, agressivo ou indiscriminado e proíbem automação não baseada na API, como scripts que controlam o site. O programa limita-se a ler dados autorizados e gerar um relatório para revisão humana.

Consulte [Regras de automação do X](https://help.x.com/en/rules-and-policies/x-automation) e [regras sobre seguir contas](https://help.x.com/en/using-x/x-follow-limit).

## Modo offline (arquivo antigo)

Solicitar um novo arquivo do X não é necessário para o modo online. Para analisar um arquivo já existente:

        .\TwitterClean.ps1 -ArchivePath "$HOME\Downloads\twitter-archive.zip" -DisplayedFollowingCount 50

Também aceita pasta extraída:

        .\TwitterClean.ps1 -ArchivePath "$HOME\Downloads\twitter-archive\data"

Ou o próprio arquivo:

        .\TwitterClean.ps1 -ArchivePath "$HOME\Downloads\twitter-archive\data\following.js"

## Testes

Com PowerShell 5.1 ou 7+:

        .\tests\Test-TwitterClean.ps1

Os testes usam dados fictícios locais. Não fazem login nem chamadas à API do X.

## Estrutura do projeto

    TwitterClean/
    ├── .github/workflows/powershell-tests.yml
    ├── src/
    │   ├── TwitterClean.psm1
    │   └── TwitterClean.Api.psm1
    ├── tests/
    │   └── Test-TwitterClean.ps1
    ├── TwitterClean.ps1
    └── TwitterClean-Online.ps1

## Privacidade

O arquivo exportado do X pode conter mensagens diretas e outros dados pessoais. Não o envie ao repositório. O TwitterClean processa arquivos localmente. No modo online, a autenticação e as consultas acontecem diretamente entre o PowerShell e api.x.com; o projeto não opera um servidor intermediário.
