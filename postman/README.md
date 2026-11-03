# Coleção Postman — API SaaS Multitenant

Este diretório contém a coleção oficial do Postman para testes manuais e automatizados da API SaaS Multitenant desenvolvida para o Projeto Integrador.

## Arquivo
* `SaaS-App.postman_collection.json`: Especificação completa das requisições HTTP da API no formato Postman Collection v2.1.

## Como Importar no Postman
1. Abra o **Postman**.
2. Clique no botão **Import** (canto superior esquerdo).
3. Selecione o arquivo `postman/SaaS-App.postman_collection.json` ou arraste-o para a interface.
4. A coleção **SaaS-App** estará visível na aba *Collections*.

## Variáveis da Coleção
A coleção utiliza variáveis para facilitar a alternância entre ambientes:

| Variável | Valor Padrão Local | Exemplo AWS EC2 | Descrição |
| :--- | :--- | :--- | :--- |
| `baseUrl` | `http://localhost:3000` | `http://<IP_PUBLICO_EC2>:3000` | URL base do serviço |
| `token` | *(preenchido no login)* | *(preenchido no login)* | Token JWT do usuário administrador |
| `memberToken` | *(preenchido no login)* | *(preenchido no login)* | Token JWT do usuário membro |
| `tenantId` | *(preenchido no onboarding)* | *(preenchido no onboarding)* | Identificador do tenant ativo |

## Fluxo de Teste Recomendado
1. **Health Check**: `GET {{baseUrl}}/health`
2. **Consultar Planos**: `GET {{baseUrl}}/plans`
3. **Onboarding de Tenant**: `POST {{baseUrl}}/tenants` (gera o `registrationToken`)
4. **Registro do Primeiro Admin**: `POST {{baseUrl}}/auth/register` (utilizando o token retornado)
5. **Login de Administrador**: `POST {{baseUrl}}/auth/login` (armazena o JWT)
6. **Gerenciamento de Usuários e Isolamento**: requisições protegidas via Bearer Token.
