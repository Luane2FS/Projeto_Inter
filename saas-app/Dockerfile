# ==============================================================================
# Dockerfile Multi-Stage de Produção - SaaS Multitenant API
# Projeto Integrador: Capacita Computação em Nuvem
# ==============================================================================

# Estágio 1: Instalação das dependências de produção
FROM node:22-alpine AS dependencies
WORKDIR /usr/src/app

# Copiar descritores de pacotes para aproveitar cache de camadas
COPY package*.json ./
RUN npm ci --omit=dev --ignore-scripts

# ==============================================================================
# Estágio 2: Runtime Final de Produção (Imagem Mínima e Segura)
FROM node:22-alpine AS runner
WORKDIR /usr/src/app

# Definir variáveis de ambiente seguras para produção
ENV NODE_ENV=production \
    PORT=3000

# Criar grupo e usuário sem privilégios administrativos (least privilege)
# O Node.js na imagem Alpine já traz o usuário 'node' (uid: 1000)
USER node

# Copiar módulos de nó resolvidos do estágio de dependências
COPY --chown=node:node --from=dependencies /usr/src/app/node_modules ./node_modules

# Copiar arquivos de código-fonte da aplicação
COPY --chown=node:node package.json ./
COPY --chown=node:node server.js ./
COPY --chown=node:node config/ ./config/
COPY --chown=node:node controllers/ ./controllers/
COPY --chown=node:node middleware/ ./middleware/
COPY --chown=node:node models/ ./models/
COPY --chown=node:node routes/ ./routes/
COPY --chown=node:node services/ ./services/

# Metadado documental da porta padrão da imagem (a porta em execução é parametrizada em runtime via $PORT)
EXPOSE 3000

# Verificação de integridade (Healthcheck) nativo do container
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider "http://127.0.0.1:${PORT:-3000}/health/live" || exit 1

# Comando de inicialização
CMD ["node", "server.js"]
