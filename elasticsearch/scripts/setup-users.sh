#!/bin/bash


ELASTIC_PASSWORD=Elastic123!
KIBANA_SYSTEM_PASSWORD=Kibana123!
LOGSTASH_SYSTEM_PASSWORD=Logstash123!

# Aguardar o Elasticsearch ficar pronto
echo "Aguardando Elasticsearch ficar pronto..."
until curl -s -u elastic:${ELASTIC_PASSWORD} "http://localhost:9200" > /dev/null; do
  echo "Elasticsearch não está pronto, aguardando 5 segundos..."
  sleep 5
done

echo "✅ Elasticsearch está pronto!"

# Função para log com timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Função para verificar se um comando foi bem sucedido
check_command() {
    if [ $? -eq 0 ]; then
        echo "✅ $1"
        return 0
    else
        echo "❌ $1"
        return 1
    fi
}

# Verificar e criar a role kibana_system se não existir
echo "Verificando role kibana_system..."
ROLE_RESPONSE=$(curl -s -u elastic:${ELASTIC_PASSWORD} -w "%{http_code}" "http://localhost:9200/_security/role/kibana_system")
ROLE_HTTP_CODE=${ROLE_RESPONSE: -3}

if [ "$ROLE_HTTP_CODE" -ne 200 ]; then
    echo "Criando role kibana_system..."
    curl -s -u elastic:${ELASTIC_PASSWORD} -X PUT "http://localhost:9200/_security/role/kibana_system" \
      -H "Content-Type: application/json" \
      -d '{
        "cluster": [
          "monitor",
          "manage_api_key", 
          "manage_own_api_key",
          "read_ccr",
          "read_ilm"
        ],
        "indices": [
          {
            "names": [
              ".kibana*",
              ".reporting-*",
              ".apm-agent-configuration", 
              ".apm-custom-link",
              ".logs-*",
              ".metrics-*",
              ".traces-*",
              ".siem-signals-*"
            ],
            "privileges": ["all"],
            "allow_restricted_indices": true
          },
          {
            "names": ["*"],
            "privileges": [
              "read",
              "view_index_metadata", 
              "monitor"
            ]
          }
        ],
        "applications": [
          {
            "application": "kibana-.kibana",
            "privileges": ["all"],
            "resources": ["*"]
          }
        ]
      }'
    check_command "Role kibana_system criada"
else
    echo "✅ Role kibana_system já existe"
fi

# Verificar e criar/atualizar usuário kibana_system
echo "Verificando usuário kibana_system..."
KIBANA_USER_RESPONSE=$(curl -s -u elastic:${ELASTIC_PASSWORD} -w "%{http_code}" "http://localhost:9200/_security/user/kibana_system")
KIBANA_USER_HTTP_CODE=${KIBANA_USER_RESPONSE: -3}

if [ "$KIBANA_USER_HTTP_CODE" -ne 200 ]; then
    echo "Criando usuário kibana_system..."
    curl -s -u elastic:${ELASTIC_PASSWORD} -X POST "http://localhost:9200/_security/user/kibana_system" \
      -H "Content-Type: application/json" \
      -d '{
        "password": "'${KIBANA_SYSTEM_PASSWORD}'",
        "roles": ["kibana_system"],
        "full_name": "Kibana System User"
      }'
    check_command "Usuário kibana_system criado"
else
    echo "✅ Usuário kibana_system já existe"
    echo "Atualizando senha do usuário kibana_system..."
    curl -s -u elastic:${ELASTIC_PASSWORD} -X POST "http://localhost:9200/_security/user/kibana_system/_password" \
      -H "Content-Type: application/json" \
      -d '{
        "password": "'${KIBANA_SYSTEM_PASSWORD}'"
      }'
    check_command "Senha do kibana_system atualizada"
fi

# Testar autenticação do kibana_system com retry
echo "Testando autenticação do kibana_system..."
MAX_RETRIES=5
RETRY_COUNT=0
AUTH_SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$AUTH_SUCCESS" = false ]; do
    AUTH_RESPONSE=$(curl -s -u kibana_system:${KIBANA_SYSTEM_PASSWORD} -w "%{http_code}" "http://localhost:9200/_nodes")
    AUTH_HTTP_CODE=${AUTH_RESPONSE: -3}
    
    if [ "$AUTH_HTTP_CODE" -eq 200 ]; then
        echo "✅ Autenticação do kibana_system bem-sucedida!"
        AUTH_SUCCESS=true
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "❌ Falha na autenticação (tentativa $RETRY_COUNT/$MAX_RETRIES). HTTP Code: $AUTH_HTTP_CODE"
        
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "Aguardando 3 segundos antes de tentar novamente..."
            sleep 3
            
            # Forçar recriação do usuário na última tentativa
            if [ $RETRY_COUNT -eq $((MAX_RETRIES - 1)) ]; then
                echo "Recriando usuário kibana_system..."
                curl -s -u elastic:${ELASTIC_PASSWORD} -X DELETE "http://localhost:9200/_security/user/kibana_system"
                sleep 2
                
                curl -s -u elastic:${ELASTIC_PASSWORD} -X POST "http://localhost:9200/_security/user/kibana_system" \
                  -H "Content-Type: application/json" \
                  -d '{
                    "password": "'${KIBANA_SYSTEM_PASSWORD}'",
                    "roles": ["kibana_system"],
                    "full_name": "Kibana System User"
                  }'
                sleep 2
            fi
        fi
    fi
done

if [ "$AUTH_SUCCESS" = false ]; then
    echo "❌ ❌ ❌ FALHA CRÍTICA: Não foi possível autenticar com kibana_system após $MAX_RETRIES tentativas"
    echo "Resposta detalhada:"
    curl -s -u kibana_system:${KIBANA_SYSTEM_PASSWORD} "http://localhost:9200/_nodes"
    exit 1
fi


# Verificar e criar a role personalizada para Logstash (não usar nome reservado)
log "Verificando role logstash_writer..."
LOGSTASH_ROLE_RESPONSE=$(curl -s -u "elastic:${ELASTIC_PASSWORD}" -w "%{http_code}" "${ELASTIC_URL}/_security/role/logstash_writer")
LOGSTASH_ROLE_HTTP_CODE=${LOGSTASH_ROLE_RESPONSE: -3}

if [ "$LOGSTASH_ROLE_HTTP_CODE" -ne 200 ]; then
    log "Criando role logstash_writer..."
    curl -s -u "elastic:${ELASTIC_PASSWORD}" -X POST "${ELASTIC_URL}/_security/role/logstash_writer" \
      -H "Content-Type: application/json" \
      -d '{
        "cluster": [
          "monitor", 
          "manage_index_templates", 
          "manage_ilm"
        ],
        "indices": [
          {
            "names": ["logstash-*", "application-logs-*", "system-metrics-*", "test-*"],
            "privileges": [
              "write", 
              "create_index", 
              "create", 
              "delete", 
              "manage", 
              "index",
              "monitor",
              "read"
            ],
            "allow_restricted_indices": false
          }
        ]
      }'
    check_command "Role logstash_writer criada"
else
    log "✅ Role logstash_writer já existe"
fi

# Verificar e atualizar a SENHA do usuário reservado logstash_system
log "Verificando usuário reservado logstash_system..."
LOGSTASH_USER_RESPONSE=$(curl -s -u elastic:${ELASTIC_PASSWORD} -w "%{http_code}" "${ELASTIC_URL}/_security/user/logstash_system")
LOGSTASH_USER_HTTP_CODE=${LOGSTASH_USER_RESPONSE: -3}

if [ "$LOGSTASH_USER_HTTP_CODE" -eq 200 ]; then
    log "✅ Usuário reservado logstash_system existe"
    log "Atualizando senha do usuário logstash_system..."
    curl -s -u elastic:${ELASTIC_PASSWORD} -X POST "${ELASTIC_URL}/_security/user/logstash_system/_password" \
      -H "Content-Type: application/json" \
      -d '{
        "password": "'${LOGSTASH_SYSTEM_PASSWORD}'"
      }'
    check_command "Senha do logstash_system atualizada"
    
    # Associar a role personalizada ao usuário reservado
    log "Associando role logstash_writer ao usuário reservado..."
    curl -s -u elastic:${ELASTIC_PASSWORD} -X POST "${ELASTIC_URL}/_security/user/logstash_system/_roles" \
      -H "Content-Type: application/json" \
      -d '{
        "roles": ["logstash_writer"]
      }'
    check_command "Role associada ao usuário reservado"
else
    log "❌ Usuário reservado logstash_system não encontrado"
    log "💡 O usuário logstash_system é reservado e deve ser criado automaticamente pelo Elasticsearch"
    log "Execute: docker-compose restart elasticsearch e aguarde a inicialização completa"
fi

# Como alternativa, criar um usuário personalizado (não reservado)
log "Criando usuário personalizado logstash_user como alternativa..."
curl -s -u elastic:${ELASTIC_PASSWORD} -X POST "${ELASTIC_URL}/_security/user/logstash_user" \
  -H "Content-Type: application/json" \
  -d '{
    "password": "'${LOGSTASH_SYSTEM_PASSWORD}'",
    "roles": ["logstash_writer", "logstash_system"],
    "full_name": "Logstash Custom User",
    "email": null,
    "metadata": {},
    "enabled": true
  }'
check_command "Usuário personalizado logstash_user criado"

# Testar as permissões
log "Testando permissões do usuário logstash_system..."
TEST_RESPONSE=$(curl -s -u logstash_system:${LOGSTASH_SYSTEM_PASSWORD} -w "%{http_code}" \
  -X PUT "${ELASTIC_URL}/test-logstash-permissions" \
  -H "Content-Type: application/json" \
  -d '{"settings": {"number_of_shards": 1}}')
TEST_HTTP_CODE=${TEST_RESPONSE: -3}

if [ "$TEST_HTTP_CODE" -eq 200 ]; then
    log "✅ Permissões do logstash_system estão funcionando!"
    # Limpar índice de teste
    curl -s -u logstash_system:${LOGSTASH_SYSTEM_PASSWORD} -X DELETE "${ELASTIC_URL}/test-logstash-permissions" > /dev/null
else
    log "⚠️  Permissões do logstash_system podem estar incompletas (HTTP $TEST_HTTP_CODE)"
    log "💡 Usando usuário personalizado logstash_user como fallback"
fi

# Teste final de autenticação
echo "Realizando teste final de autenticação..."
FINAL_TEST_RESPONSE=$(curl -s -u kibana_system:${KIBANA_SYSTEM_PASSWORD} -w "%{http_code}" "http://localhost:9200/_nodes?filter_path=nodes.*.version")
FINAL_TEST_HTTP_CODE=${FINAL_TEST_RESPONSE: -3}

if [ "$FINAL_TEST_HTTP_CODE" -eq 200 ]; then
    echo "🎉 🎉 🎉 Setup de usuários concluído com sucesso!"
    echo "✅ kibana_system pode autenticar e acessar o endpoint /_nodes"
    echo "📊 Informações dos nodes:"
    echo "${FINAL_TEST_RESPONSE%???}" | jq .
else
    echo "❌ ❌ ❌ ERRO CRÍTICO: kibana_system ainda não pode acessar /_nodes"
    echo "📋 Detalhes do erro (HTTP $FINAL_TEST_HTTP_CODE):"
    echo "${FINAL_TEST_RESPONSE%???}"
    echo ""
    echo "🔧 Solução recomendada:"
    echo "1. Verifique se as senhas no arquivo .env estão corretas"
    echo "2. Execute: docker-compose down -v"
    echo "3. Delete os volumes: docker volume prune -f"
    echo "4. Execute: docker-compose up -d"
    exit 1
fi

echo "✅ Todos os usuários do sistema foram configurados com sucesso!"
