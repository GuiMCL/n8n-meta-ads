# Workflow n8n: Instagram Ads com IA

## Artefatos
- `n8n_instagram_ads_ai.json`: importar em Workflows > Import from File
- `ai_ads_schema.sql`: executar previamente no PostgreSQL

## Dependencias
n8n recente, PostgreSQL, conta OpenAI API com acesso a modelos de imagem, fal.ai com credito, app Meta com Marketing API e permissao ads_management, conta de anuncios e pagina vinculada ao Instagram.

## Variaveis do ambiente n8n
```
ADS_WEBHOOK_SECRET=gerar-segredo-longo-aleatorio
OPENAI_API_KEY=...
FAL_KEY=...
META_ACCESS_TOKEN=...
META_AD_ACCOUNT_ID=1234567890
META_PAGE_ID=1234567890
META_INSTAGRAM_ACTOR_ID=1234567890
META_GRAPH_VERSION=v24.0
```
Atencao: n8n pode restringir `$env` em expressoes em instalacoes recentes (`N8N_BLOCK_ENV_ACCESS_IN_NODE`). Nesse caso, use credenciais n8n nos nodes HTTP e um mecanismo seguro de segredo para as validacoes, sem desligar protecoes globais por conveniencia.

## Pos-importacao
1. Execute `ai_ads_schema.sql` no Postgres.
2. Selecione uma credencial PostgreSQL em TODOS os nos `Postgres` (nomes iniciando com `Salvar`, `Buscar`, `Reservar`, `Marcar`).
3. Configure as variaveis/credenciais dos nos HTTP e confirme a versao da Graph API disponivel.
4. Ative o workflow apenas em ambiente de teste.
5. Valide conectividade com API OpenAI, fal.ai e Meta. A Meta pode exigir formatos e campos adicionais em `adsets`, `adcreatives` ou `advideos` conforme o tipo de conta e o posicionamento; ajuste conforme erros concretos.
6. Webhooks estao em `responseMode:onReceived` (aceite HTTP, nao resultado final). Para obter o ID, consulte `SELECT id,status,video_status FROM ai_ads ORDER BY created_at DESC LIMIT 10;`. O workflow tem status de aprovacao separado da ativacao para evitar gastos involuntarios.

## Criar rascunho
```
curl -X POST 'https://SEU-N8N/webhook/ai-ads/briefing' \
  -H 'Content-Type: application/json' -H 'x-ads-secret: SEU_SEGREDO' \
  -d '{"nome":"Campanha Exemplo","produto":"Servico de manutencao","url":"https://exemplo.com.br","orcamento_diario":30,"publico":"clientes interessados em manutencao","tipo_midia":"image"}'
```
A criacao gera imagem e solicita video; o video fica em processamento assincrono via fal.ai. Para `tipo_midia=video`, aguarde `video_status=READY` antes de aprovar. Mesmo para `image`, o workflow solicita video, gerando custo adicional.

## Aprovar/criar na Meta, mas SEM ativar
```
curl -X POST 'https://SEU-N8N/webhook/ai-ads/approve' \
  -H 'Content-Type: application/json' -H 'x-ads-secret: SEU_SEGREDO' \
  -d '{"id":"ads-ID_DA_EXECUCAO","aprovar":true}'
```
Isso cria campanha, adset e anuncio `PAUSED`. Revise os objetos na Meta e as politicas antes de ativar.

## Ativar (GERA GASTOS)
```
curl -X POST 'https://SEU-N8N/webhook/ai-ads/activate' \
  -H 'Content-Type: application/json' -H 'x-ads-secret: SEU_SEGREDO' \
  -d '{"id":"ads-ID_DA_EXECUCAO","ativar":true}'
```
**Ativar veiculacao causa gastos reais na conta Meta.** Limite diario configurado no briefing: R$10 ate R$1.000, mas nao ha teto vitalicio de campanha, nem interruptor automatico baseado em gastos agregados. Comece com valores baixos.

## Monitoramento
- Cron a cada 30min: `insights` dos ultimos 7 dias, atualiza `latest_insights`.
- Cron a cada 5min: consulta fila de video fal.ai e atualiza `video_url`.
- Nao implementa envio de email, dashboard, pause automatico, rollback parcial, renovacao de tokens ou monitoramento de falhas via canal separado. Crie alertas antes do uso em producao.

## Limites e seguranca
- Prototipo tecnico **nao testado com credenciais reais**. Importacao e sintaxe JSON verificadas, nao execucao end-to-end.
- IDs da Meta sao numeros sem prefixo `act_`; API pode demandar diferentes tipos de creative/video e formatos por conta.
- Ao ocorrer falha depois de criar objetos na Meta, `status=PUBLISHING` pode permanecer e objetos pausados podem ficar orfaos. Consulte `Executions` e Meta Ads Manager antes de tentar novamente. Nao altere status para DRAFT e reexecute sem reconciliacao.
- A imagem fica em base64 no PostgreSQL; para producao use S3 com URL assinada/privada e retencao controlada.
- Controle quem pode acessar n8n, o banco e as credenciais; os webhooks usam segredo compartilhado e HTTPS.
- Nao ha segmentacao municipal automatica: `cidade` e `publico` sao usados para briefing IA; a segmentacao real na Meta foi fixada em BR, idade 21-60. Parametrize os IDs de cidade/interesses apos validar com a API.
- O video pode demorar e seu URL pode expirar; armazene em S3 para producao.
- `ads_management` e demais permissoes variam com app e conta; anuncio pode estar sujeito a revisao da Meta.
