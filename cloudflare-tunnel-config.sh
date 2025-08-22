#!/bin/bash
# ============================================
# Script Completo para Criar Túnel Cloudflare
# Autor: Sistema Automatizado
# Versão: 2.0
# ============================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para imprimir com cores
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# Verificar se foi passado argumento
if [ $# -lt 2 ]; then
    echo -e "${RED}Uso: $0 <nome_usuario> <dominio>${NC}"
    echo -e "${YELLOW}Exemplo: $0 joao exemplo.com${NC}"
    exit 1
fi

# Variáveis
USUARIO=$1
DOMINIO=$2
TUNNEL_NAME="tunel-$USUARIO"
WORK_DIR="./$USUARIO"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Banner
echo ""
echo "============================================"
echo "   CRIADOR DE TÚNEL CLOUDFLARE v2.0"
echo "============================================"
echo -e "Usuário: ${YELLOW}$USUARIO${NC}"
echo -e "Domínio: ${YELLOW}$DOMINIO${NC}"
echo -e "Túnel:   ${YELLOW}$TUNNEL_NAME${NC}"
echo "============================================"
echo ""

# Verificar se cloudflared está instalado
if ! command -v cloudflared &> /dev/null; then
    print_error "cloudflared não está instalado!"
    print_info "Instale com: wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb && sudo dpkg -i cloudflared-linux-amd64.deb"
    exit 1
fi

# Verificar se já existe certificado
if [ ! -f "$HOME/.cloudflared/cert.pem" ]; then
    print_warning "Certificado não encontrado. Execute primeiro: cloudflared tunnel login"
    exit 1
fi

# Criar diretório de trabalho
print_info "Criando diretório de trabalho..."
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# ============================================
# PASSO 1: CRIAR O TÚNEL
# ============================================
echo ""
echo "=== PASSO 1: Criando Túnel ==="
echo ""

# Verificar se túnel já existe
if cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
    print_warning "Túnel $TUNNEL_NAME já existe!"
    read -p "Deseja deletar e recriar? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        print_info "Deletando túnel existente..."
        cloudflared tunnel delete -f "$TUNNEL_NAME" 2>/dev/null
        sleep 2
    else
        print_error "Operação cancelada"
        exit 1
    fi
fi

# Criar novo túnel
print_info "Criando túnel $TUNNEL_NAME..."
TUNNEL_OUTPUT=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1)
if [ $? -eq 0 ]; then
    print_success "Túnel criado com sucesso!"
    
    # Extrair ID do túnel
    TUNNEL_ID=$(echo "$TUNNEL_OUTPUT" | grep -oP 'id \K[a-f0-9-]+' | head -1)
    if [ -z "$TUNNEL_ID" ]; then
        # Método alternativo
        TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    fi
    
    if [ -z "$TUNNEL_ID" ]; then
        print_error "Não foi possível obter o ID do túnel!"
        print_info "Saída do comando: $TUNNEL_OUTPUT"
        exit 1
    fi
    
    print_info "ID do Túnel: $TUNNEL_ID"
    
    # Aguardar arquivo de credenciais ser criado
    sleep 2
    
    # Verificar se o arquivo de credenciais foi criado
    if [ ! -f "$HOME/.cloudflared/$TUNNEL_ID.json" ]; then
        print_warning "Arquivo de credenciais ainda não existe. Aguardando..."
        sleep 3
        if [ ! -f "$HOME/.cloudflared/$TUNNEL_ID.json" ]; then
            print_error "Arquivo de credenciais não foi criado após 5 segundos!"
            print_info "Arquivos disponíveis:"
            ls -la "$HOME/.cloudflared/" | grep "\.json"
            exit 1
        fi
    fi
else
    print_error "Erro ao criar túnel!"
    echo "$TUNNEL_OUTPUT"
    exit 1
fi

# ============================================
# PASSO 2: CONFIGURAR DNS
# ============================================
echo ""
echo "=== PASSO 2: Configurando DNS ==="
echo ""

# Lista de subdomínios para criar (usando primeiro nível para compatibilidade SSL)
declare -a SUBDOMINIOS=(
    "$USUARIO.$DOMINIO"
    "$USUARIO-app.$DOMINIO"
    "$USUARIO-api.$DOMINIO"
    "$USUARIO-www.$DOMINIO"
)

# Criar rotas DNS
for SUBDOMINIO in "${SUBDOMINIOS[@]}"; do
    print_info "Criando DNS para $SUBDOMINIO..."
    
    DNS_OUTPUT=$(cloudflared tunnel route dns "$TUNNEL_NAME" "$SUBDOMINIO" 2>&1)
    if [ $? -eq 0 ]; then
        print_success "DNS criado: $SUBDOMINIO → $TUNNEL_ID.cfargotunnel.com"
    else
        if echo "$DNS_OUTPUT" | grep -q "already exists"; then
            print_warning "DNS já existe para $SUBDOMINIO"
        else
            print_error "Erro ao criar DNS para $SUBDOMINIO"
            echo "$DNS_OUTPUT"
        fi
    fi
done

# ============================================
# PASSO 3: PREPARAR ARQUIVOS DO USUÁRIO
# ============================================
echo ""
echo "=== PASSO 3: Preparando Arquivos ==="
echo ""

# Criar diretório do pacote
PACKAGE_DIR="$USUARIO-tunnel"
mkdir -p "$PACKAGE_DIR"

# Copiar credenciais
print_info "Copiando credenciais..."
if [ -f "$HOME/.cloudflared/$TUNNEL_ID.json" ]; then
    cp "$HOME/.cloudflared/$TUNNEL_ID.json" "$PACKAGE_DIR/$TUNNEL_ID.json"
    print_success "Credenciais copiadas como $TUNNEL_ID.json"
else
    print_error "Arquivo de credenciais $TUNNEL_ID.json não encontrado!"
    print_info "Verificando se o túnel foi criado corretamente..."
    cloudflared tunnel list | grep "$TUNNEL_NAME"
    print_warning "Tentando localizar arquivo de credenciais..."
    ls -la "$HOME/.cloudflared/" | grep -E "\.json$"
    exit 1
fi

# Criar config.yml
print_info "Criando arquivo de configuração..."
cat > "$PACKAGE_DIR/config.yml" << EOF
# Configuração do Cloudflare Tunnel
# Usuário: $USUARIO
# Criado em: $(date)

tunnel: $TUNNEL_NAME
credentials-file: ~/.cloudflared/$TUNNEL_ID.json

# Configurações opcionais
loglevel: info
metrics: localhost:2000

# Regras de roteamento
ingress:
  # Domínio principal (porta 3000)
  - hostname: $USUARIO.$DOMINIO
    service: http://localhost:3000
    originRequest:
      noTLSVerify: false
      connectTimeout: 30s
  
  # Subdomínio www (porta 3000)
  - hostname: $USUARIO-www.$DOMINIO
    service: http://localhost:3000
  
  # Subdomínio app (porta 8080)
  - hostname: $USUARIO-app.$DOMINIO
    service: http://localhost:8080
    originRequest:
      noTLSVerify: false
      connectTimeout: 30s
  
  # Subdomínio api (porta 3001)
  - hostname: $USUARIO-api.$DOMINIO
    service: http://localhost:3001
    originRequest:
      noTLSVerify: false
      connectTimeout: 60s
  
  # SSH (opcional - descomente se necessário)
  # - hostname: $USUARIO-ssh.$DOMINIO
  #   service: ssh://localhost:22
  
  # Regra obrigatória - deve ser a última!
  - service: http_status:404
EOF
print_success "Arquivo de configuração criado"

# Criar script de instalação
print_info "Criando script de instalação..."
cat > "$PACKAGE_DIR/instalar.sh" << 'INSTALLER_EOF'
#!/bin/bash
# Script de Instalação do Cloudflare Tunnel

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "============================================"
echo "   INSTALADOR CLOUDFLARE TUNNEL"
echo "============================================"
echo ""

# Detectar usuário atual
CURRENT_USER=$(whoami)
echo -e "${BLUE}ℹ Instalando para usuário: $CURRENT_USER${NC}"

# Criar diretório
echo -e "${BLUE}ℹ Criando diretórios...${NC}"
mkdir -p ~/.cloudflared

# Copiar arquivos
echo -e "${BLUE}ℹ Copiando arquivos de configuração...${NC}"

# Encontrar o arquivo JSON de credenciais e extrair o TunnelID
CRED_FILE=$(ls *.json 2>/dev/null | head -1)
if [ -n "$CRED_FILE" ]; then
    # Extrair o TunnelID do arquivo JSON
    TUNNEL_ID=$(grep -o '"TunnelID":"[^"]*' "$CRED_FILE" | cut -d'"' -f4)
    if [ -z "$TUNNEL_ID" ]; then
        echo -e "${RED}✗ Não foi possível extrair o TunnelID do arquivo de credenciais!${NC}"
        exit 1
    fi
    
    # Copiar com o nome correto baseado no TunnelID
    cp "$CRED_FILE" ~/.cloudflared/$TUNNEL_ID.json
    echo -e "${GREEN}✓ Credenciais copiadas como $TUNNEL_ID.json${NC}"
else
    echo -e "${RED}✗ Arquivo de credenciais não encontrado!${NC}"
    exit 1
fi

# Copiar config.yml
cp config.yml ~/.cloudflared/

# Atualizar caminhos no config.yml
echo -e "${BLUE}ℹ Atualizando configuração...${NC}"
# Atualizar o caminho do credentials-file para usar o TunnelID correto
sed -i "s|~/.cloudflared/.*\.json|~/.cloudflared/$TUNNEL_ID.json|g" ~/.cloudflared/config.yml

# Verificar cloudflared
if ! command -v cloudflared &> /dev/null; then
    echo -e "${YELLOW}⚠ Cloudflared não encontrado!${NC}"
    echo "Instalando cloudflared..."
    
    # Detectar arquitetura
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        ARCH="amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        ARCH="arm64"
    fi
    
    wget -q "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"
    sudo dpkg -i cloudflared-linux-${ARCH}.deb
    rm cloudflared-linux-${ARCH}.deb
fi

# Obter nome do túnel do config
TUNNEL_NAME=$(grep "tunnel:" ~/.cloudflared/config.yml | awk '{print $2}')

echo ""
echo -e "${GREEN}✓ Instalação concluída!${NC}"
echo ""
echo "============================================"
echo "   PRÓXIMOS PASSOS"
echo "============================================"
echo ""
echo "1. INICIE SEUS SERVIÇOS nas portas:"
echo "   - Porta 3000 (domínio principal e www)"
echo "   - Porta 8080 (app)"
echo "   - Porta 3001 (api)"
echo ""
echo "2. EXECUTE O TÚNEL:"
echo -e "   ${YELLOW}cloudflared tunnel run $TUNNEL_NAME${NC}"
echo ""
echo "3. PARA EXECUTAR EM BACKGROUND:"
echo -e "   ${YELLOW}nohup cloudflared tunnel run $TUNNEL_NAME > tunnel.log 2>&1 &${NC}"
echo ""
echo "4. PARA INSTALAR COMO SERVIÇO (recomendado):"
echo -e "   ${YELLOW}sudo cloudflared --config ~/.cloudflared/config.yml service install${NC}"
echo -e "   ${YELLOW}sudo systemctl start cloudflared${NC}"
echo -e "   ${YELLOW}sudo systemctl enable cloudflared${NC}"
echo ""
echo "============================================"
INSTALLER_EOF

chmod +x "$PACKAGE_DIR/instalar.sh"
print_success "Script de instalação criado"

# Criar arquivo de teste
print_info "Criando servidor de teste..."
cat > "$PACKAGE_DIR/servidor-teste.py" << 'EOF'
#!/usr/bin/env python3
"""
Servidor de Teste para Cloudflare Tunnel
Inicia servidores HTTP nas portas configuradas
"""

import http.server
import socketserver
import threading
import os
import signal
import sys
from datetime import datetime

# Configuração das portas
PORTS = {
    3000: "Principal / WWW",
    8080: "App",
    3001: "API"
}

servers = []

def create_handler(port, description):
    class CustomHandler(http.server.SimpleHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            
            html = f"""
            <!DOCTYPE html>
            <html>
            <head>
                <title>Servidor de Teste - Porta {port}</title>
                <style>
                    body {{
                        font-family: Arial, sans-serif;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                        height: 100vh;
                        margin: 0;
                        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                        color: white;
                    }}
                    .container {{
                        text-align: center;
                        padding: 40px;
                        background: rgba(255, 255, 255, 0.1);
                        border-radius: 20px;
                        backdrop-filter: blur(10px);
                    }}
                    h1 {{ margin: 0 0 20px 0; }}
                    .info {{ 
                        background: rgba(0, 0, 0, 0.3);
                        padding: 20px;
                        border-radius: 10px;
                        margin-top: 20px;
                    }}
                    .success {{ color: #4ade80; }}
                </style>
            </head>
            <body>
                <div class="container">
                    <h1 class="success">✓ Servidor Funcionando!</h1>
                    <h2>{description}</h2>
                    <div class="info">
                        <p><strong>Porta:</strong> {port}</p>
                        <p><strong>Caminho:</strong> {self.path}</p>
                        <p><strong>Hora:</strong> {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}</p>
                        <p><strong>Cliente:</strong> {self.client_address[0]}</p>
                    </div>
                </div>
            </body>
            </html>
            """.encode('utf-8')
            
            self.wfile.write(html)
            
        def log_message(self, format, *args):
            print(f"[Porta {port}] {self.client_address[0]} - {format%args}")
    
    return CustomHandler

def start_server(port, description):
    handler = create_handler(port, description)
    with socketserver.TCPServer(("", port), handler) as httpd:
        print(f"✓ Servidor iniciado na porta {port} ({description})")
        servers.append(httpd)
        httpd.serve_forever()

def signal_handler(sig, frame):
    print("\n\nEncerrando servidores...")
    for server in servers:
        server.shutdown()
    sys.exit(0)

if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal_handler)
    
    print("=" * 50)
    print("   SERVIDORES DE TESTE - CLOUDFLARE TUNNEL")
    print("=" * 50)
    print()
    
    # Iniciar servidores em threads separadas
    threads = []
    for port, desc in PORTS.items():
        thread = threading.Thread(target=start_server, args=(port, desc))
        thread.daemon = True
        thread.start()
        threads.append(thread)
    
    print()
    print("Todos os servidores estão rodando!")
    print("Pressione Ctrl+C para parar")
    print()
    
    # Manter o programa rodando
    try:
        for thread in threads:
            thread.join()
    except KeyboardInterrupt:
        pass
EOF

chmod +x "$PACKAGE_DIR/servidor-teste.py"
print_success "Servidor de teste criado"

# Criar README detalhado
print_info "Criando documentação..."
cat > "$PACKAGE_DIR/LEIA-ME.txt" << EOF
============================================
   CLOUDFLARE TUNNEL - INSTRUÇÕES
============================================

USUÁRIO: $USUARIO
DATA DE CRIAÇÃO: $(date)

DOMÍNIOS CONFIGURADOS:
- https://$USUARIO.$DOMINIO (porta 3000)
- https://$USUARIO-www.$DOMINIO (porta 3000)
- https://$USUARIO-app.$DOMINIO (porta 8080)
- https://$USUARIO-api.$DOMINIO (porta 3001)

============================================
   ARQUIVOS INCLUÍDOS
============================================

1. [TUNNEL_ID].json
   - Sua chave única do túnel
   - MANTENHA ESTE ARQUIVO SEGURO!
   - Não compartilhe com ninguém
   - O arquivo tem o nome do ID do túnel

2. config.yml
   - Configuração do túnel
   - Define os domínios e portas

3. instalar.sh
   - Script de instalação automática
   - Detecta e instala dependências

4. servidor-teste.py
   - Servidor HTTP de teste
   - Útil para testar o túnel

5. LEIA-ME.txt
   - Este arquivo

============================================
   INSTALAÇÃO RÁPIDA
============================================

1. Descompacte o arquivo ZIP:
   unzip $USUARIO-tunnel.zip

2. Entre na pasta:
   cd $USUARIO-tunnel

3. Execute o instalador:
   ./instalar.sh

4. Teste o túnel:
   ./servidor-teste.py &
   cloudflared tunnel run $TUNNEL_NAME

5. Acesse no navegador:
   https://$USUARIO.$DOMINIO
   https://$USUARIO-app.$DOMINIO
   https://$USUARIO-api.$DOMINIO

============================================
   EXECUTAR EM PRODUÇÃO
============================================

OPÇÃO 1 - Como serviço (recomendado):

   sudo cloudflared --config ~/.cloudflared/config.yml service install
   sudo systemctl start cloudflared
   sudo systemctl enable cloudflared
   
   # Ver logs
   sudo journalctl -u cloudflared -f

OPÇÃO 2 - Em background:

   nohup cloudflared tunnel run $TUNNEL_NAME > tunnel.log 2>&1 &
   
   # Parar
   killall cloudflared

OPÇÃO 3 - Com screen/tmux:

   screen -S tunnel
   cloudflared tunnel run $TUNNEL_NAME
   # Ctrl+A, D para sair
   
   # Voltar
   screen -r tunnel

============================================
   SOLUÇÃO DE PROBLEMAS
============================================

ERRO: "connection refused"
- Verifique se o serviço está rodando na porta
- Use ./servidor-teste.py para teste

ERRO: "DNS_PROBE_FINISHED_NXDOMAIN"
- Aguarde 2-3 minutos para DNS propagar
- Verifique no dashboard da Cloudflare

ERRO: "502 Bad Gateway"
- Serviço local não está respondendo
- Verifique a porta no config.yml

============================================
   COMANDOS ÚTEIS
============================================

# Status do túnel
cloudflared tunnel info $TUNNEL_NAME

# Logs em tempo real
sudo journalctl -u cloudflared -f

# Testar conectividade de todos os subdomínios
curl https://$USUARIO.$DOMINIO
curl https://$USUARIO-app.$DOMINIO  
curl https://$USUARIO-api.$DOMINIO
curl https://$USUARIO-www.$DOMINIO

# Verificar portas abertas
sudo netstat -tlnp | grep -E '3000|8080|3001'

============================================
   IMPORTANTE: CERTIFICADOS SSL
============================================

Este túnel usa subdomínios de PRIMEIRO NÍVEL para garantir
compatibilidade com o certificado SSL gratuito do Cloudflare.

Formato usado: usuario-servico.dominio.com
Exemplos:
- $USUARIO.$DOMINIO (principal)
- $USUARIO-app.$DOMINIO (aplicação)
- $USUARIO-api.$DOMINIO (API)
- $USUARIO-www.$DOMINIO (www)

⚠ EVITE usar subdomínios de múltiplos níveis como:
  app.$USUARIO.$DOMINIO ← Não funciona com SSL gratuito!

✓ Use sempre: $USUARIO-app.$DOMINIO ← Funciona com SSL gratuito!

============================================
   SEGURANÇA
============================================

- NUNCA compartilhe o arquivo credentials.json
- Use HTTPS sempre que possível
- Configure firewall local se necessário
- Monitore logs regularmente

============================================
   SUPORTE
============================================

Documentação: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/
Status: https://www.cloudflarestatus.com/

============================================
EOF
print_success "Documentação criada"

# ============================================
# PASSO 4: CRIAR PACOTE ZIP
# ============================================
echo ""
echo "=== PASSO 4: Criando Pacote ==="
echo ""

# Verificar se os arquivos essenciais estão no pacote
if [ ! -f "$PACKAGE_DIR/$TUNNEL_ID.json" ]; then
    print_error "Arquivo de credenciais não está no pacote!"
    exit 1
fi

if [ ! -f "$PACKAGE_DIR/config.yml" ]; then
    print_error "Arquivo config.yml não está no pacote!"
    exit 1
fi

# Criar ZIP
ZIP_NAME="$USUARIO-tunnel-$TIMESTAMP.zip"
print_info "Criando arquivo $ZIP_NAME..."
zip -r "$ZIP_NAME" "$PACKAGE_DIR" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    print_success "Pacote criado com sucesso!"
    
    # Calcular tamanho
    SIZE=$(du -h "$ZIP_NAME" | cut -f1)
    print_info "Tamanho do arquivo: $SIZE"
    
    # Verificar conteúdo do ZIP
    print_info "Verificando conteúdo do pacote..."
    if unzip -l "$ZIP_NAME" | grep -q "$TUNNEL_ID.json" && unzip -l "$ZIP_NAME" | grep -q "config.yml"; then
        print_success "Pacote contém todos os arquivos necessários"
    else
        print_error "Pacote está incompleto!"
        unzip -l "$ZIP_NAME"
        exit 1
    fi
else
    print_error "Erro ao criar ZIP!"
    exit 1
fi

# Limpar diretório temporário
rm -rf "$PACKAGE_DIR"

# ============================================
# RESUMO FINAL
# ============================================
echo ""
echo "============================================"
echo "   ✅ PROCESSO CONCLUÍDO COM SUCESSO!"
echo "============================================"
echo ""
echo -e "${GREEN}TÚNEL CRIADO:${NC}"
echo "  Nome: $TUNNEL_NAME"
echo "  ID: $TUNNEL_ID"
echo ""
echo -e "${GREEN}DNS CONFIGURADO:${NC}"
for SUBDOMINIO in "${SUBDOMINIOS[@]}"; do
    echo "  ✓ https://$SUBDOMINIO"
done
echo ""
echo -e "${GREEN}ARQUIVO GERADO:${NC}"
echo "  📦 $WORK_DIR/$ZIP_NAME"
echo ""
echo -e "${YELLOW}PRÓXIMOS PASSOS:${NC}"
echo "1. Envie o arquivo ZIP para $USUARIO"
echo "2. Instrua a executar: ./instalar.sh"
echo "3. Depois: cloudflared tunnel run $TUNNEL_NAME"
echo ""
echo -e "${BLUE}TESTAR AGORA:${NC}"
echo "  python3 -m http.server 3000 &"
echo "  cloudflared tunnel run $TUNNEL_NAME"
echo "  Acesse: https://$USUARIO.$DOMINIO"
echo ""
echo "============================================"

# Perguntar se quer ver o conteúdo
read -p "Deseja listar o conteúdo do ZIP? (s/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    echo ""
    unzip -l "$ZIP_NAME"
fi

# Salvar log
LOG_FILE="$WORK_DIR/criacao-$USUARIO-$TIMESTAMP.log"
echo "Log salvo em: $LOG_FILE"

# Fim do script
exit 0