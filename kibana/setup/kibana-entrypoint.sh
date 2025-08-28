#!/bin/bash

# Esperar o Kibana ficar healthy
echo "Aguardando Kibana ficar healthy..."
while ! curl -f http://localhost:5601/api/status >/dev/null 2>&1; do
    echo "Kibana não está healthy ainda, aguardando..."
    sleep 10
done

echo "Kibana está healthy! Executando setup..."
# Executar script de setup
/usr/local/bin/kibana-setup.sh

# Executar o comando original do Kibana
exec /usr/local/bin/kibana-docker
