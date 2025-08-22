# 🚀 Tutorial Completo: Cloudflare Tunnel no Ubuntu Linux

## 📋 Índice
1. [O que é e qual problema resolve](#o-que-é-e-qual-problema-resolve)
2. [Como funciona - Diagrama](#como-funciona)
3. [Pré-requisitos](#pré-requisitos)
4. [Instalação do Cloudflared](#instalação-do-cloudflared)
5. [Configuração Inicial](#configuração-inicial)
6. [Criando seu Primeiro Túnel](#criando-seu-primeiro-túnel)
7. [Configurando Serviços](#configurando-serviços)
8. [Adicionando Novos Subdomínios](#adicionando-novos-subdomínios)
9. [Modos de Execução](#modos-de-execução)
10. [Troubleshooting](#troubleshooting)

---

## 🎯 O que é e qual problema resolve

### Problema Tradicional
- ❌ Você tem serviços rodando localmente (API, banco de dados, aplicação)
- ❌ Precisa expor para internet mas está atrás de NAT/Firewall
- ❌ Não tem IP público fixo
- ❌ Configurar port forwarding é complexo e inseguro
- ❌ Certificados SSL são difíceis de gerenciar

### Solução: Cloudflare Tunnel
- ✅ Expõe serviços locais para internet sem abrir portas
- ✅ Conexão segura e criptografada
- ✅ SSL/TLS automático e gratuito
- ✅ Funciona atrás de NAT, firewall, IP dinâmico
- ✅ Zero configuração de rede

---

## 🔄 Como Funciona

```mermaid
graph TB
    subgraph "Sua Máquina Local"
        A[PostgreSQL<br/>:5432] 
        B[API HTTP<br/>:3001]
        C[Web App<br/>:3000]
        D[cloudflared<br/>daemon]
        
        A --> D
        B --> D
        C --> D
    end
    
    subgraph "Cloudflare Edge Network"
        E[Cloudflare<br/>Tunnel Service]
        F[SSL/TLS<br/>Termination]
        G[DDoS<br/>Protection]
        H[CDN<br/>Cache]
        
        E --> F
        F --> G
        G --> H
    end
    
    subgraph "Internet"
        I[Cliente 1<br/>Browser]
        J[Cliente 2<br/>App Mobile]
        K[Cliente 3<br/>API Consumer]
    end
    
    D ==Túnel Seguro<br/>Outbound Only==> E
    
    H --> I
    H --> J
    H --> K
    
    style A fill:#e1f5fe
    style B fill:#e1f5fe
    style C fill:#e1f5fe
    style D fill:#fff59d
    style E fill:#c8e6c9
    style F fill:#c8e6c9
    style G fill:#c8e6c9
    style H fill:#c8e6c9
    style I fill:#ffccbc
    style J fill:#ffccbc
    style K fill:#ffccbc
```

### Fluxo da Requisição

```mermaid
sequenceDiagram
    participant U as Usuário Internet
    participant CF as Cloudflare Edge
    participant CT as Cloudflare Tunnel
    participant CD as cloudflared (local)
    participant S as Serviço Local
    
    U->>CF: HTTPS: api.usuario.dominio.com
    Note over CF: SSL Termination<br/>DDoS Protection
    CF->>CT: Roteamento via Tunnel ID
    CT->>CD: Via túnel estabelecido
    Note over CD: Rota baseada em hostname
    CD->>S: HTTP: localhost:3001
    S-->>CD: Resposta da API
    CD-->>CT: Via túnel seguro
    CT-->>CF: Resposta
    CF-->>U: HTTPS Response
    
    Note over U,S: Todo tráfego criptografado<br/>Sem portas abertas no firewall
```

---

## ⚙️ Pré-requisitos

### Sistema Operacional
- Ubuntu 20.04 LTS ou superior
- Arquitetura: amd64 ou arm64

### Requisitos
- Acesso root ou sudo
- Conexão com internet
- Conta Cloudflare (gratuita)
- Domínio configurado no Cloudflare

### Verificar Arquitetura
```bash
# Verificar arquitetura do sistema
uname -m
# Resultado esperado: x86_64 (amd64) ou aarch64 (arm64)
```

---

## 📦 Instalação do Cloudflared

### Método 1: Download Direto (Recomendado)

```bash
# Para Ubuntu amd64 (x86_64)
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb

# Para Ubuntu arm64 (aarch64)
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
sudo dpkg -i cloudflared-linux-arm64.deb

# Verificar instalação
cloudflared --version
```

### Método 2: Via APT Repository

```bash
# Adicionar chave GPG da Cloudflare
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

# Adicionar repositório
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflared.list

# Instalar
sudo apt update
sudo apt install cloudflared
```

---

## 🔐 Configuração Inicial

### Passo 1: Autenticar com Cloudflare

```bash
# Login na Cloudflare (abrirá browser)
cloudflared tunnel login

# Isso criará o arquivo de certificado em:
# ~/.cloudflared/cert.pem
```

### Passo 2: Verificar Certificado

```bash
# Verificar se o certificado foi criado
ls -la ~/.cloudflared/cert.pem

# Deve mostrar algo como:
# -rw------- 1 user user 1976 Aug 15 10:30 cert.pem
```

---

## 🚇 Criando seu Primeiro Túnel

### Método Automático: Usando o Script

```bash
# Baixar o script de configuração
wget https://github.com/richarddaros/cloudflared-tunnel/blob/main/cloudflare-tunnel-config.sh

# Dar permissão de execução
chmod +x cloudflare-tunnel-config.sh

# Executar (substitua pelos seus valores)
./cloudflare-tunnel-config.sh usuario dominio.com
```

### Método Manual: Passo a Passo

#### 1. Criar o Túnel

```bash
# Criar túnel com nome descritivo
cloudflared tunnel create meu-tunnel

# Saída esperada:
# Tunnel credentials written to /home/user/.cloudflared/TUNNEL_ID.json
# Created tunnel meu-tunnel with id 5b3f7a8e-3cf7-4c25-9157-example
```

#### 2. Criar Arquivo de Configuração

```bash
# Criar arquivo config.yml
nano ~/.cloudflared/config.yml
```

Conteúdo do `config.yml`:

```yaml
# Configuração do Cloudflare Tunnel
tunnel: meu-tunnel
credentials-file: /home/user/.cloudflared/TUNNEL_ID.json

# Métricas (opcional)
metrics: localhost:2000

# Regras de roteamento
ingress:
  # PostgreSQL
  - hostname: db.meudominio.com
    service: tcp://localhost:5432
    originRequest:
      proxyType: socks
  
  # API HTTP
  - hostname: api.meudominio.com
    service: http://localhost:3001
    originRequest:
      noTLSVerify: false
      connectTimeout: 60s
      
  # Aplicação Web
  - hostname: app.meudominio.com
    service: http://localhost:3000
    originRequest:
      noTLSVerify: false
      connectTimeout: 30s
  
  # Regra catch-all (obrigatória)
  - service: http_status:404
```

#### 3. Criar Registros DNS

```bash
# Para cada hostname no config.yml
cloudflared tunnel route dns meu-tunnel db.meudominio.com
cloudflared tunnel route dns meu-tunnel api.meudominio.com
cloudflared tunnel route dns meu-tunnel app.meudominio.com
```

---

## 🔧 Configurando Serviços

### PostgreSQL (Porta 5432)

#### 1. Configurar PostgreSQL para aceitar conexões locais

```bash
# Editar postgresql.conf
sudo nano /etc/postgresql/14/main/postgresql.conf

# Adicionar/modificar:
listen_addresses = 'localhost'
port = 5432
```

#### 2. Adicionar no config.yml

```yaml
ingress:
  - hostname: postgres.meudominio.com
    service: tcp://localhost:5432
    originRequest:
      proxyType: socks
      
  # IMPORTANTE: Para PostgreSQL via navegador, adicione também:
  - hostname: pgadmin.meudominio.com
    service: http://localhost:5050  # Se tiver pgAdmin
```

#### 3. Criar rota DNS

```bash
cloudflared tunnel route dns meu-tunnel postgres.meudominio.com
```

#### 4. Conectar ao PostgreSQL remoto

```bash
# String de conexão
psql "host=postgres.meudominio.com port=443 dbname=mydb user=myuser sslmode=require"

# Ou via aplicação
DATABASE_URL="postgresql://user:pass@postgres.meudominio.com:443/dbname?sslmode=require"
```

### API HTTP (Porta 3001)

#### 1. Configurar sua API

```javascript
// Node.js/Express exemplo
const express = require('express');
const app = express();

app.listen(3001, 'localhost', () => {
  console.log('API rodando em http://localhost:3001');
});
```

#### 2. Adicionar no config.yml

```yaml
ingress:
  - hostname: api.meudominio.com
    service: http://localhost:3001
    originRequest:
      noTLSVerify: false
      connectTimeout: 60s
      # Headers customizados se necessário
      httpHostHeader: "api.meudominio.com"
      originServerName: "api.meudominio.com"
```

#### 3. Configurar CORS na API (se necessário)

```javascript
// Permitir origem do Cloudflare
app.use(cors({
  origin: ['https://api.meudominio.com'],
  credentials: true
}));
```

### Aplicação Web (Porta 3000)

#### 1. Adicionar múltiplos paths

```yaml
ingress:
  # Path específico para admin
  - hostname: app.meudominio.com
    path: /admin/*
    service: http://localhost:3000/admin
    
  # Path para API
  - hostname: app.meudominio.com
    path: /api/*
    service: http://localhost:3001
    
  # Resto da aplicação
  - hostname: app.meudominio.com
    service: http://localhost:3000
```

---

## ➕ Adicionando Novos Subdomínios

### Passo 1: Editar config.yml

```bash
nano ~/.cloudflared/config.yml
```

Adicionar nova entrada ANTES da regra catch-all:

```yaml
ingress:
  # ... entradas existentes ...
  
  # NOVO SERVIÇO
  - hostname: novo-servico.meudominio.com
    service: http://localhost:8080
    originRequest:
      noTLSVerify: false
      connectTimeout: 30s
  
  # Regra catch-all (sempre última!)
  - service: http_status:404
```

### Passo 2: Criar registro DNS

```bash
# Adicionar DNS para novo subdomínio
cloudflared tunnel route dns meu-tunnel novo-servico.meudominio.com
```

### Passo 3: Reiniciar o túnel

```bash
# Se rodando como serviço
sudo systemctl restart cloudflared

# Se rodando manual
# Ctrl+C para parar
cloudflared tunnel run meu-tunnel  # Reiniciar
```

### Validar nova configuração

```bash
# Validar sintaxe do config.yml
cloudflared tunnel ingress validate

# Testar nova rota
cloudflared tunnel ingress rule https://novo-servico.meudominio.com
```

---

## 🏃 Modos de Execução

### Modo 1: Manual (Desenvolvimento)

```bash
# Executar em foreground
cloudflared tunnel run meu-tunnel

# Ver logs em tempo real
# Ctrl+C para parar
```

### Systemd Service (Produção) ⭐

```bash
# Instalar como serviço
sudo cloudflared --config ~/.cloudflared/config.yml service install

# Iniciar serviço
sudo systemctl start cloudflared

# Habilitar início automático
sudo systemctl enable cloudflared

# Ver status
sudo systemctl status cloudflared

# Ver logs
sudo journalctl -u cloudflared -f

# Reiniciar após mudanças
sudo systemctl restart cloudflared

# Parar serviço
sudo systemctl stop cloudflared
```

---

## 🔍 Monitoramento e Logs

### Verificar Status do Túnel

```bash
# Informações do túnel
cloudflared tunnel info meu-tunnel

# Listar todos os túneis
cloudflared tunnel list

# Ver métricas (se habilitado)
curl http://localhost:2000/metrics
```

### Logs Detalhados

```bash
# Aumentar nível de log no config.yml
loglevel: debug  # opções: trace, debug, info, warn, error, fatal

# Ver logs do systemd
sudo journalctl -u cloudflared --since="1 hour ago"

# Filtrar logs por padrão
sudo journalctl -u cloudflared | grep ERROR
```

---

## 🐛 Troubleshooting

### Problema: "502 Bad Gateway"

**Causa**: Serviço local não está rodando

```bash
# Verificar se serviço está rodando
sudo netstat -tlnp | grep :3000

# Solução: Iniciar o serviço
npm start  # ou comando apropriado
```

### Problema: "DNS_PROBE_FINISHED_NXDOMAIN"

**Causa**: DNS não propagado

```bash
# Verificar DNS
nslookup app.meudominio.com

# Aguardar 2-5 minutos para propagação
# Ou limpar cache DNS local
sudo systemd-resolve --flush-caches
```

### Problema: "Unauthorized: Invalid tunnel secret"

**Causa**: Credenciais incorretas

```bash
# Recriar credenciais
cloudflared tunnel delete meu-tunnel
cloudflared tunnel create meu-tunnel

# Atualizar config.yml com novo ID
```

### Problema: "Connection refused"

**Causa**: Firewall ou serviço bind em interface errada

```bash
# Verificar firewall
sudo ufw status

# Verificar bind do serviço
ss -tlnp | grep :3000

# Certificar que está em localhost/127.0.0.1
```

### Problema: Certificado SSL inválido

**Causa**: Subdomínio de múltiplos níveis

```bash
# ❌ ERRADO: app.usuario.dominio.com (2º nível)
# ✅ CERTO: usuario-app.dominio.com (1º nível)

# SSL gratuito cobre apenas *.dominio.com
```

---

## 🔒 Segurança

### Boas Práticas

1. **Nunca exponha serviços sensíveis sem autenticação**
```yaml
# Adicionar autenticação no Cloudflare Access
- hostname: admin.meudominio.com
  service: http://localhost:8080
  originRequest:
    access:
      required: true
      teamName: "meu-time"
```

2. **Use firewall local**
```bash
# Permitir apenas localhost
sudo ufw deny 3000/tcp
sudo ufw allow from 127.0.0.1 to any port 3000
```

3. **Monitore acessos**
```bash
# Ver logs de acesso
sudo journalctl -u cloudflared | grep "GET\|POST"
```

4. **Rotacione credenciais periodicamente**
```bash
# Recriar túnel com novas credenciais
cloudflared tunnel cleanup meu-tunnel
cloudflared tunnel delete meu-tunnel
cloudflared tunnel create meu-tunnel
```

---

## 📚 Referências e Links Úteis

- [Documentação Oficial Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare Dashboard](https://dash.cloudflare.com/)
- [Status Cloudflare](https://www.cloudflarestatus.com/)
- [Cloudflare Community](https://community.cloudflare.com/)

---

## 💡 Dicas Extras

### Performance
- Use cache do Cloudflare para arquivos estáticos
- Configure `connectTimeout` apropriado para cada serviço
- Use compressão gzip na origem

### Desenvolvimento
- Use túneis temporários para testes: `cloudflared tunnel --url http://localhost:3000`
- Configure múltiplos túneis para diferentes ambientes (dev, staging, prod)

### Monitoramento
- Integre com Prometheus via endpoint de métricas
- Configure alertas para quedas de serviço
- Use Cloudflare Analytics para insights de tráfego

---

*Tutorial criado para cloudflare-tunnel-config.sh v2.0*
*Última atualização: Agosto 2025*