#!/bin/bash
set -e

# Configurações - usar variáveis de ambiente com valores padrão
WAIT_TIME=${WAIT_TIME:-60}
MAX_RETRIES=${MAX_RETRIES:-30}
KIBANA_URL=http://localhost:5601
ELASTIC_URL="${ELASTICSEARCH_HOSTS:-http://localhost:9200}"
ELASTIC_PASSWORD="${ELASTIC_PASSWORD:-Elastic123!}"
KIBANA_SYSTEM_PASSWORD="${KIBANA_SYSTEM_PASSWORD:-Kibana123!}"

echo "🚀 Iniciando configuração pós-inicialização do Kibana..."
echo "=========================================================="
echo "ELASTIC_URL: $ELASTIC_URL"
echo "KIBANA_URL: $KIBANA_URL"
echo "WAIT_TIME: $WAIT_TIME segundos"
echo "MAX_RETRIES: $MAX_RETRIES tentativas"
echo "ELASTIC_PASSWORD: $ELASTIC_PASSWORD"
echo "KIBANA_SYSTEM_PASSWORD: $KIBANA_SYSTEM_PASSWORD"

# Função para log com timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Função para verificar se variáveis estão definidas
check_env_vars() {
    if [ -z "$ELASTIC_PASSWORD" ] || [ "$ELASTIC_PASSWORD" = "changeme" ]; then
        log "⚠️  ELASTIC_PASSWORD não definida ou é o valor padrão"
        return 1
    fi
    
    if [ -z "$KIBANA_SYSTEM_PASSWORD" ] || [ "$KIBANA_SYSTEM_PASSWORD" = "changeme" ]; then
        log "⚠️  KIBANA_SYSTEM_PASSWORD não definida ou é o valor padrão"
        return 1
    fi
    
    return 0
}

# Função para verificar comando com retry
retry_command() {
    local cmd="$1"
    local description="$2"
    local max_retries=${3:-$MAX_RETRIES}
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if eval "$cmd"; then
            log "✅ $description"
            return 0
        else
            retry_count=$((retry_count + 1))
            log "⚠️  Falha em $description (tentativa $retry_count/$max_retries)"
            sleep 10
        fi
    done
    
    log "❌ Falha após $max_retries tentativas: $description"
    return 1
}

# Função para fazer requests autenticadas para a API do Kibana (SEM JQ)
kibana_request() {
    local method=$1
    local path=$2
    local data=$3
    local retry_count=0
    local full_url="${KIBANA_URL}${path}"
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        response=$(curl -s -u "elastic:${ELASTIC_PASSWORD}" \
            -X "$method" \
            -H "Content-Type: application/json" \
            -H "kbn-xsrf: true" \
            ${data:+--data "$data"} \
            -w "%{http_code}" \
            "$full_url" 2>/dev/null)
        
        http_code=${response: -3}
        
        if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ] || [ "$http_code" -eq 409 ]; then
            echo "$response"
            return 0
        elif [ "$http_code" -eq 401 ] || [ "$http_code" -eq 403 ]; then
            log "❌ Erro de autenticação (HTTP $http_code) em $full_url"
            return 1
        else
            retry_count=$((retry_count + 1))
            log "⚠️  HTTP $http_code em $method $full_url (tentativa $retry_count/$MAX_RETRIES)"
            sleep 5
        fi
    done
    
    log "❌ Falha após $MAX_RETRIES tentativas: $method $full_url"
    return 1
}

# Função alternativa para extrair valores JSON (SEM JQ)
extract_json_value() {
    local json="$1"
    local key="$2"
    echo "$json" | grep -o "\"$key\":\"[^\"]*\"" | cut -d'"' -f4 || \
    echo "$json" | grep -o "\"$key\":[^,}]*" | cut -d':' -f2- | tr -d ' "'
}

# Verificar variáveis de ambiente
if ! check_env_vars; then
    log "❌ Variáveis de ambiente necessárias não definidas corretamente"
    exit 1
fi

log "✅ Variáveis de ambiente verificadas"

# 1. Aguardar serviços ficarem prontos
log "⏳ Aguardando Elasticsearch ficar pronto..."
retry_command \
    "curl -s -u elastic:${ELASTIC_PASSWORD} '${ELASTIC_URL}' > /dev/null" \
    "Elasticsearch pronto"

log "⏳ Aguardando Kibana ficar pronto..."
retry_command \
    "curl -s -u elastic:${ELASTIC_PASSWORD} '${KIBANA_URL}/api/status' > /dev/null" \
    "Kibana pronto"

# 2. Criar Index Templates
log "📋 Criando index templates..."

# Template para logs de aplicação
if curl -s -u "elastic:${ELASTIC_PASSWORD}" -X PUT "${ELASTIC_URL}/_index_template/application-logs-template" \
  -H "Content-Type: application/json" \
  -d '{
    "index_patterns": ["application-logs-*"],
    "template": {
      "settings": {
        "number_of_shards": 1,
        "number_of_replicas": 0
      },
      "mappings": {
        "properties": {
          "@timestamp": {"type": "date"},
          "level": {"type": "keyword"},
          "message": {"type": "text"},
          "service": {"type": "keyword"},
          "host": {"type": "keyword"}
        }
      }
    }
  }' > /dev/null; then
    log "✅ Template application-logs-* criado"
else
    log "⚠️  Erro ao criar template application-logs-* (pode já existir)"
fi

# 3. Criar Data Views (SIMPLIFICADO - sem jq)
log "📊 Criando data views..."

# Data view para logs de aplicação
if kibana_request "POST" "/api/data_views/data_view" '{
  "data_view": {
    "title": "application-logs-*",
    "name": "Logs de Aplicação",
    "timeFieldName": "@timestamp"
  }
}' > /dev/null; then
    log "✅ Data view: application-logs-*"
else
    log "⚠️  Falha ao criar data view: application-logs-* (pode já existir)"
fi

# Data view para métricas de sistema
if kibana_request "POST" "/api/data_views/data_view" '{
  "data_view": {
    "title": "system-metrics-*",
    "name": "Métricas de Sistema",
    "timeFieldName": "@timestamp"
  }
}' > /dev/null; then
    log "✅ Data view: system-metrics-*"
else
    log "⚠️  Falha ao criar data view: system-metrics-* (pode já existir)"
fi

# 4. Configurações do Kibana (OPCIONAL - pode comentar se der erro)
log "⚙️ Configurando padrões default..."

if kibana_request "POST" "/api/kibana/settings" '{
  "changes": {
    "defaultIndex": "application-logs-*",
    "dateFormat:tz": "America/Sao_Paulo"
  }
}' > /dev/null; then
    log "✅ Configurações padrão definidas"
else
    log "⚠️  Erro ao definir configurações padrão (pode não ser necessário)"
fi

# 5. Verificação final simplificada
log "🔍 Realizando verificação final..."

# Verificar conexão básica com Kibana
if curl -s -u "elastic:${ELASTIC_PASSWORD}" "${KIBANA_URL}/api/status" > /dev/null; then
    log "✅ Kibana respondendo corretamente"
else
    log "⚠️  Kibana não está respondendo como esperado"
fi

echo ""
echo "=========================================================="
echo "🎉 CONFIGURAÇÃO CONCLUÍDA!"
echo ""
echo "🌐 Acesse: $KIBANA_URL"
echo "👤 Usuário: elastic"
echo "🔑 Senha: ${ELASTIC_PASSWORD}"
echo "=========================================================="

# Script finalizado com sucesso
exit 0
