# Créditos e referências

O código do TwitterClean foi escrito para este repositório, sem copiar ou incorporar código de terceiros. O projeto não utiliza bibliotecas externas.

Referências utilizadas para definir o formato de entrada e os limites funcionais:

1. **X Help Center — Como baixar seu arquivo do X**  
   https://help.x.com/pt/managing-your-account/how-to-download-your-x-archive  
   Fonte oficial para o procedimento de solicitação e download do arquivo de dados.

2. **X Help Center — Regras de automação**  
   https://help.x.com/en/rules-and-policies/x-automation  
   Fonte oficial sobre automação do website, autorização de ações em contas de usuários e limites para ações automatizadas de seguir/deixar de seguir. A página informa atualização em abril de 2026.

3. **X Help Center — About following on X**  
   https://help.x.com/en/using-x/x-follow-limit  
   Fonte oficial sobre práticas proibidas de follow churn e unfollow indiscriminado ou automatizado.

4. **seramo/twitter-archive-docs — documentação comunitária do formato do arquivo**  
   https://github.com/seramo/twitter-archive-docs  
   Referência comunitária para os campos accountId e userLink de following.js. Essa documentação observa que userLink pode não estar disponível para perfis protegidos ou desativados. Não é um esquema oficial publicado pelo X e, por isso, o TwitterClean trata a ausência desse campo somente como indício para revisão.

A ferramenta foi desenhada para processar o arquivo localmente. Não envia o arquivo, IDs ou relatórios para os autores do projeto ou para terceiros.
