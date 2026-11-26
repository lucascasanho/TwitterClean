# TwitterClean

Ferramenta local em PowerShell para consolidar e analisar os registros de contas seguidas encontrados em arquivos de dados do X.

**Versão:** 0.3.0  
**Plataforma:** Windows PowerShell 5.1 ou PowerShell 7+  
**Dependências:** nenhuma biblioteca externa  
**Rede:** nenhuma conexão com o X ou outro serviço

## O que a ferramenta faz

- Lê um ZIP de dados do X, uma pasta extraída ou arquivos following.js.
- Aceita vários backups na mesma execução e reúne os IDs de todas as origens.
- Remove duplicações sem descartar a informação sobre a origem de cada ID.
- Se um ID não tiver userLink em um arquivo, procura um link válido em outras cópias do mesmo registro.
- Marca links ausentes ou que não pertencem aos domínios oficiais x.com e twitter.com.
- Compara a quantidade de IDs encontrados com o número de contas seguidas informado manualmente.
- Mostra quais IDs aparecem exclusivamente em uma das origens.
- Gera relatórios HTML, CSV e JSON para revisão local.

**Não é necessário ter conta de desenvolvedor, criar aplicativo, autorizar OAuth, informar senha ou comprar créditos de API.** O TwitterClean não faz login, não consulta o site do X e não envia os arquivos para lugar algum.

## Limite importante: o que não pode ser descoberto localmente

A ferramenta só consegue trabalhar com informações que estejam presentes nos arquivos fornecidos.

Por exemplo, se o contador atual do X mostrar 50 contas, mas a união de todos os backups contiver apenas 12 IDs, o relatório mostrará uma diferença de 38. Ele **não consegue reconstruir os 38 IDs que não existem nos arquivos**.

Da mesma forma:
- um registro sem userLink não comprova que a conta esteja suspensa;
- um ID que não aparece em um backup não comprova que a conta foi removida;
- uma diferença de contagem não identifica quais contas estão ocultas, suspensas ou indisponíveis;
- um backup antigo pode conter vínculos que já não existem hoje.

Para confirmar o estado de uma conta, é necessário abrir o perfil pelo link gerado e interpretar a informação exibida pelo próprio X. O programa não automatiza essa consulta.

## Como executar no Windows

1. Baixe o projeto por **Code > Download ZIP** no GitHub e extraia a pasta, ou clone com Git:

        git clone https://github.com/lucascasanho/TwitterClean.git
        cd TwitterClean

2. Abra o PowerShell dentro da pasta do projeto.

3. Permita scripts apenas na janela atual:

        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

4. Execute a análise de um backup:

        .\TwitterClean.ps1 -ArchivePath "$HOME\Downloads\twitter-archive.zip" -DisplayedFollowingCount 50

Substitua o caminho pelo local do seu arquivo ZIP. Troque 50 pelo número que aparece atualmente no contador de contas seguidas do seu perfil.

### Usar mais de um backup

Passe todos os arquivos, pastas ou following.js que deseja comparar:

        .\TwitterClean.ps1 -ArchivePath @(
            "$HOME\Downloads\arquivo-antigo.zip",
            "$HOME\Downloads\arquivo-recente.zip",
            "$HOME\Downloads\backup-extra"
        ) -DisplayedFollowingCount 50

Também é possível informar vários arquivos diretamente:

        .\TwitterClean.ps1 -ArchivePath "$HOME\Downloads\backup1.zip","$HOME\Downloads\backup2.zip" -DisplayedFollowingCount 50

O programa reúne os IDs encontrados em todas as origens e indica o que cada backup acrescenta à lista consolidada.

### Usar uma pasta extraída ou um arquivo específico

Pasta extraída:

        .\TwitterClean.ps1 -ArchivePath "$HOME\Downloads\twitter-archive"

Arquivo específico:

        .\TwitterClean.ps1 -ArchivePath "$HOME\Downloads\twitter-archive\data\following.js"

O programa também procura arquivos following.js, following-part*.js e nomes semelhantes quando recebe uma pasta ou um ZIP.

## Relatórios gerados

Por padrão, o programa cria uma pasta TwitterClean-Report-AAAA... no diretório atual.

| Arquivo | Conteúdo |
|---|---|
| following-report.html | Relatório visual com comparação, IDs e links para revisão |
| following-report.csv | Lista consolidada, uma linha por ID, com todas as origens |
| archive-comparison.csv | Quantidade de registros e IDs únicos por origem |
| archive-exclusive-ids.csv | IDs encontrados em apenas uma das origens |
| following-report.json | Dados estruturados, resumo, origens e lista consolidada |

Para gerar os relatórios sem abrir automaticamente o HTML:

        .\TwitterClean.ps1 -ArchivePath "$HOME\Downloads\twitter-archive.zip" -DisplayedFollowingCount 50 -NoOpenReport

Para escolher a pasta de saída:

        .\TwitterClean.ps1 -ArchivePath "$HOME\Downloads\twitter-archive.zip" -OutputDirectory "$HOME\Downloads\relatorio-twitterclean"

## Como interpretar os campos

- **Registros lidos:** quantidade de entradas encontradas nos arquivos, antes da consolidação.
- **IDs únicos reunidos:** quantidade de IDs distintos após juntar as origens.
- **Registros duplicados:** ocorrências repetidas do mesmo ID, inclusive entre backups.
- **Sem link válido:** IDs para os quais nenhum dos arquivos fornecidos contém um userLink reconhecido.
- **Contagem sem ID correspondente:** quanto o contador informado excede os IDs reunidos. Não representa uma lista recuperável de contas.
- **IDs acima do contador:** quanto os backups antigos contêm a mais que o contador atual.
- **IDs exclusivos desta origem:** IDs que só aparecem em um dos arquivos ou locais informados.

Quando o mesmo ID aparece em mais de um backup, a ferramenta mantém todas as origens e prefere um userLink válido encontrado em qualquer uma delas.

## Segurança e privacidade

O processamento é feito localmente. Não há autenticação, solicitação de senha, armazenamento de tokens, conexão de rede ou alteração na conta.

Os relatórios contêm IDs e informações da sua rede de contatos. Não os publique nem os envie ao repositório.

O TwitterClean não executa follow ou unfollow. A revisão dos perfis e qualquer ação na conta permanecem sob controle do usuário.

## Testes

Com Windows PowerShell 5.1 ou PowerShell 7+:

        .\tests\Test-TwitterClean.ps1

Os testes usam dados fictícios temporários e verificam leitura de arquivos JS e ZIP, consolidação de várias origens, tratamento de duplicações, seleção de links válidos, rejeição de links inseguros e cálculo de divergências. Não fazem login nem chamadas de rede.

## Estrutura do projeto

    TwitterClean/
    ├── .github/workflows/powershell-tests.yml
    ├── CREDITS.md
    ├── src/
    │   └── TwitterClean.psm1
    ├── tests/
    │   └── Test-TwitterClean.ps1
    ├── TwitterClean.ps1
    └── README.md
