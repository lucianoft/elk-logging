#!/bin/bash

ELASTIC_URL="http://localhost:9200"
ELASTIC_PASSWORD="Elastic123!"
LOGSTASH_TCP_HOST="localhost"
LOGSTASH_TCP_PORT="5000"

# Função para enviar log via TCP para Logstash
send_log_via_tcp() {
    local log_message="$1"
    echo "$log_message" | nc -w 2 $LOGSTASH_TCP_HOST $LOGSTASH_TCP_PORT
    if [ $? -eq 0 ]; then
        echo "✅ Log enviado: $log_message"
    else
        echo "❌ Falha ao enviar log: $log_message"
    fi
}

# Função para enviar log via HTTP para Elasticsearch
send_log_via_http() {
    local log_message="$1"
    local index_name="$2"
    
    curl -s -u "elastic:${ELASTIC_PASSWORD}" -X POST "${ELASTIC_URL}/${index_name}/_doc" \
        -H "Content-Type: application/json" \
        -d "$log_message" > /dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ Log enviado para índice $index_name"
    else
        echo "❌ Falha ao enviar log para $index_name"
    fi
}

# Função para verificar se os serviços estão rodando
check_services() {
    echo "🔍 Verificando serviços..."
    
    # Verificar Elasticsearch
    if curl -s -u "elastic:${ELASTIC_PASSWORD}" "${ELASTIC_URL}" > /dev/null; then
        echo "✅ Elasticsearch está rodando"
    else
        echo "❌ Elasticsearch não está respondendo"
        return 1
    fi
    
    # Verificar Logstash (porta TCP)
    if nc -z $LOGSTASH_TCP_HOST $LOGSTASH_TCP_PORT 2>/dev/null; then
        echo "✅ Logstash TCP (porta 5000) está rodando"
    else
        echo "⚠️  Logstash TCP não está respondendo na porta 5000"
    fi
    
    # Verificar Kibana
    if curl -s "http://localhost:5601/api/status" > /dev/null; then
        echo "✅ Kibana está rodando"
    else
        echo "⚠️  Kibana não está respondendo"
    fi
    
    return 0
}

# Função para criar índice de teste se não existir
create_test_index() {
    local index_name="$1"
    
    echo "📋 Verificando índice $index_name..."
    index_exists=$(curl -s -o /dev/null -w "%{http_code}" -u "elastic:${ELASTIC_PASSWORD}" "${ELASTIC_URL}/${index_name}")
    
    if [ "$index_exists" -ne 200 ]; then
        echo "Criando índice $index_name..."
        curl -s -u "elastic:${ELASTIC_PASSWORD}" -X PUT "${ELASTIC_URL}/${index_name}" \
            -H "Content-Type: application/json" \
            -d '{
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
                        "host": {"type": "keyword"},
                        "response_time_ms": {"type": "integer"}
                    }
                }
            }'
        echo "✅ Índice $index_name criado"
    else
        echo "✅ Índice $index_name já existe"
    fi
}

# Função para gerar log de aplicação
generate_app_log() {
    local levels=("INFO" "WARN" "ERROR" "DEBUG")
    local services=("auth-service" "user-service" "order-service" "payment-service")
    local hosts=("server-01" "server-02" "server-03")
    local messages=(
        "User login successful"
        "Database connection timeout"
        "Payment processed successfully"
        "Invalid request parameters"
        "Cache miss occurred"
        "Response time exceeded threshold"
        "Resource not found"
        "Authentication failed"
    )
    
    local level=${levels[$RANDOM % ${#levels[@]}]}
    local service=${services[$RANDOM % ${#services[@]}]}
    local host=${hosts[$RANDOM % ${#hosts[@]}]}
    local message=${messages[$RANDOM % ${#messages[@]}]}
    local response_time=$((RANDOM % 500 + 1))
    
    echo "{
        \"@timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")\",
        \"level\": \"$level\",
        \"message\": \"$message\",
        \"service\": \"$service\",
        \"host\": \"$host\",
        \"response_time_ms\": $response_time
    }"
}

# Função para gerar log de sistema
generate_system_log() {
    local metrics=("cpu" "memory" "disk" "network")
    local hosts=("server-01" "server-02" "server-03")
    
    local metric=${metrics[$RANDOM % ${#metrics[@]}]}
    local host=${hosts[$RANDOM % ${#hosts[@]}]}
    local usage=$((RANDOM % 100 + 1))
    
    echo "{
        \"@timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")\",
        \"metric\": \"$metric\",
        \"host\": \"$host\",
        \"usage_percent\": $usage,
        \"threshold\": 80
    }"
}

# Função principal
main() {
    echo "🚀 Iniciando envio de logs de teste..."
    echo "=========================================="
    
    # Verificar serviços
    if ! check_services; then
        echo "❌ Serviços não estão prontos. Execute: docker-compose up -d"
        exit 1
    fi
    
    # Criar índices de teste
    create_test_index "application-logs-2025.08.22"
    create_test_index "system-metrics-2025.08.22"
    
    echo ""
    echo "📤 Enviando logs de teste..."
    echo "=========================================="
    
    # Enviar logs via TCP para Logstash
    echo "🔌 Enviando logs via TCP para Logstash (porta 5000)..."
    for i in {1..5}; do
        log_message=$(generate_app_log)
        send_log_via_tcp "$log_message"
        sleep 0.5
    done
    
    # Enviar logs via HTTP direto para Elasticsearch
    #echo ""
#    echo "🌐 Enviando logs via HTTP para Elasticsearch..."
#    for i in {1..3}; do
        # Logs de aplicação
#        app_log=$(generate_app_log)
 #       send_log_via_http "$app_log" "application-logs-2025.08.22"
        
        # Logs de sistema
  #      system_log=$(generate_system_log)
   #     send_log_via_http "$system_log" "system-metrics-2025.08.22"
        
    #    sleep 1
    #done
    
    echo ""
    echo "=========================================="
    echo "🎯 Envio de logs concluído!"
    echo ""
    echo "📊 Verifique os logs no Kibana:"
    echo "   🌐 http://localhost:5601"
    echo "   👤 Usuário: elastic"
    echo "   🔑 Senha: Elastic123!"
    echo ""
    echo "💡 Comandos úteis:"
    echo "   Ver índices: curl -u elastic:Elastic123! http://localhost:9200/_cat/indices?v"
    echo "   Ver logs: curl -u elastic:Elastic123! http://localhost:9200/application-logs-2025.08.22/_search?pretty"
    echo "   Ver métricas: curl -u elastic:Elastic123! http://localhost:9200/system-metrics-2025.08.22/_search?pretty"
}

# Executar função principal
main
