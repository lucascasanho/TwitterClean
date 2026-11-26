# Créditos e referências

O código do TwitterClean foi escrito para este repositório, sem copiar ou incorporar código de terceiros. O projeto não utiliza bibliotecas externas.

Referências oficiais utilizadas para implementar o modo online:

1. **X API — Get Following**  
   https://docs.x.com/x-api/users/get-following.md  
   Documenta GET /2/users/{id}/following, a paginação, o limite de até 1.000 resultados por página e os métodos de autenticação aceitos. O escopo de leitura é follows.read, com users.read e tweet.read listados na definição OAuth 2.0 do endpoint.

2. **X API — Get My User**  
   https://docs.x.com/x-api/users/get-my-user.md  
   Documenta GET /2/users/me para obter a identidade da conta autenticada.

3. **X — OAuth 2.0 Authorization Code Flow with PKCE**  
   https://docs.x.com/fundamentals/authentication/oauth-2-0/authorization-code  
   Referência para o fluxo OAuth, clientes públicos Native App, Client ID, PKCE e escopos.

4. **X API — Pricing**  
   https://docs.x.com/x-api/getting-started/pricing  
   Referência oficial para tarifas por recurso e Owned Reads. O endpoint GET /2/users/{id}/following é listado entre os endpoints elegíveis a Owned Reads quando o ID corresponde ao usuário autenticado e ele é dono do aplicativo.

5. **X Help Center — Automation Rules**  
   https://help.x.com/en/rules-and-policies/x-automation  
   Referência de política. Proíbe unfollow automatizado em massa, agressivo ou indiscriminado e automação não baseada na API, incluindo scripts que controlam o website.

Referências para o modo offline:

6. **X Help Center — Como baixar seu arquivo do X**  
   https://help.x.com/pt/managing-your-account/how-to-download-your-x-archive  
   Fonte oficial para o procedimento de solicitação e download do arquivo de dados.

7. **seramo/twitter-archive-docs — documentação comunitária do formato do arquivo**  
   https://github.com/seramo/twitter-archive-docs  
   Referência comunitária para os campos accountId e userLink de following.js. Essa documentação não é um esquema oficial publicado pelo X; por isso, a ausência de userLink é tratada somente como indício para revisão.

O modo online usa OAuth PKCE diretamente entre o PowerShell local e os domínios oficiais do X. O token é mantido somente em memória durante a execução. O modo online não solicita nem armazena senha, Client Secret ou refresh token.

A ferramenta não executa ações de follow ou unfollow.
