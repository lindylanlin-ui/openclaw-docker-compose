# OpenClaw Docker Compose SOP

本文件整理這個專案從零開始到成功啟動 OpenClaw，並把預設模型固定為 `openai-codex/gpt-5.4` 的完整流程。

## 1. 前置需求

- 已安裝 Docker 與 Docker Compose
- 可以正常執行 `docker compose version`
- 已有 OpenAI Codex 可用帳號，準備用 OAuth 登入

## 2. 準備目錄

在專案根目錄建立需要的資料夾：

```bash
mkdir -p data/.openclaw
mkdir -p data/workspace
mkdir -p data/openclaw_data
```

這些目錄會被掛進容器中，因此：

- `data/.openclaw`：保存 OpenClaw 設定與登入狀態
- `data/workspace`：工作區
- `data/openclaw_data`：額外資料

只要這些目錄不刪除，`docker compose down` 後再啟動，設定與認證通常都會保留。

## 3. 建立 `.env`

請建立 `.env`，內容可參考：

```env
OPENCLAW_CONFIG_DIR=/home/{{ User }}/openclaw-docker-compose/data/.openclaw
OPENCLAW_WORKSPACE_DIR=/home/{{ User }}/openclaw-docker-compose/data/workspace
OPENCLAW_OPENCLAWDATA_DIR=/home/{{ User }}/openclaw-docker-compose/data/openclaw_data
OPENCLAW_GATEWAY_PORT=3000
OPENCLAW_GATEWAY_TOKEN=請改成你自己的長隨機字串
OPENCLAW_GATEWAY_HOST=0.0.0.0
OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:latest
OPENCLAW_EXTRA_MOUNTS=
OPENCLAW_HOME_VOLUME=
OPENCLAW_DOCKER_APT_PACKAGES=
OPENCLAW_EXTENSIONS=
OPENCLAW_SANDBOX=
OPENCLAW_DOCKER_SOCKET=
OPENCLAW_INSTALL_DOCKER_CLI=
OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=false
OPENCLAW_TZ=Asia/Taipei
OPENCLAW_MODE=gateway
```

產生 token 可使用：

```bash
openssl rand -hex 32
```

## 4. 建立 `docker-compose.yml`

目前建議使用這份設定：

```yaml
services:
  openclaw:
    image: ${OPENCLAW_IMAGE}
    container_name: openclaw-server
    restart: unless-stopped

    ports:
      - "${OPENCLAW_GATEWAY_PORT}:3000"

    env_file:
      - .env
    environment:
      - OPENCLAW_MODE=${OPENCLAW_MODE}
      - OPENCLAW_GATEWAY_HOST=${OPENCLAW_GATEWAY_HOST}
      - OPENCLAW_GATEWAY_PORT=${OPENCLAW_GATEWAY_PORT}
      - OPENCLAW_TZ=${OPENCLAW_TZ}

    volumes:
      - ${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
      - ${OPENCLAW_WORKSPACE_DIR}:/home/node/workspace
      - ${OPENCLAW_OPENCLAWDATA_DIR}:/home/node/data

    networks:
      - ai-internal

    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s

networks:
  ai-internal:
    driver: bridge
```

重點：

- `ports` 使用 `"${OPENCLAW_GATEWAY_PORT}:3000"`，代表主機對外埠號可由 `.env` 控制
- `volumes` 要掛到 `/home/node/...`，因為容器內實際使用的是這個路徑

## 5. 建立 `data/.openclaw/openclaw.json`

請建立或修改 [data/.openclaw/openclaw.json](/home/tuffy/openclaw-docker-compose/data/.openclaw/openclaw.json)：

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "openai-codex/gpt-5.4"
      },
      "models": {
        "openai-codex/gpt-5.4": {
          "params": {
            "transport": "auto"
          }
        }
      }
    }
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "restart": true,
    "ownerDisplay": "raw"
  },
  "gateway": {
    "bind": "lan",
    "controlUi": {
      "allowedOrigins": [
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://192.168.1.10:3000"
      ],
      "dangerouslyDisableDeviceAuth": true
    },
    "auth": {
      "mode": "token",
      "token": "請改成和 .env 內 OPENCLAW_GATEWAY_TOKEN 相同的值"
    }
  }
}
```

重點：

- `gateway.bind: "lan"`：讓 OpenClaw 在容器內綁定 `0.0.0.0`
- `allowedOrigins`：加入你實際會開啟 Control UI 的網址
- `dangerouslyDisableDeviceAuth: true`：只適合內網測試，若改成 HTTPS 或只用 localhost，建議移除
- `agents.defaults.model.primary`：把預設模型固定成 `openai-codex/gpt-5.4`

`openclaw.json` 與 `.env` 中的 token 請保持一致。

## 6. 啟動服務

```bash
docker compose up -d
```

確認 Compose 展開是否正常：

```bash
docker compose config
```

確認容器是否啟動：

```bash
docker compose ps
```

正常情況下會看到類似：

```bash
0.0.0.0:3000->3000/tcp
```

## 7. 檢查 OpenClaw 是否正常綁定

查看 log：

```bash
docker logs openclaw-server --tail 50
```

正常情況應看到：

```text
[gateway] listening on ws://0.0.0.0:3000
```

若仍看到 `127.0.0.1:3000`，通常表示 `openclaw.json` 的 `gateway.bind` 尚未正確生效。

## 8. 登入 OpenAI Codex

進入容器：

```bash
docker exec -it openclaw-server sh
```

執行 OAuth 登入：

```bash
openclaw models auth login --provider openai-codex
```

依照畫面完成登入授權。

## 9. 驗證 `openai-codex/gpt-5.4` 是否設定成功

在容器內執行：

```bash
openclaw models status
```

建議再做一次實際探測：

```bash
openclaw models status --probe
```

你應確認：

- 預設模型是 `openai-codex/gpt-5.4`
- `openai-codex` 認證狀態不是 missing 或 expired

離開容器：

```bash
exit
```

## 10. 開啟 Control UI

本機可使用：

```text
http://localhost:3000
```

區網可使用：

```text
http://192.168.1.10:3000
```

在登入畫面中：

- WebSocket URL：`ws://192.168.1.10:3000` 或 `ws://localhost:3000`
- 網關令牌：填 `.env` 內的 `OPENCLAW_GATEWAY_TOKEN`

## 11. 常見問題

### 11.1 `origin not allowed`

表示 `gateway.controlUi.allowedOrigins` 沒包含你目前開頁面的來源網址。

請把實際網址加入 `openclaw.json`：

```json
"allowedOrigins": [
  "http://localhost:3000",
  "http://127.0.0.1:3000",
  "http://192.168.1.10:3000"
]
```

修改後重啟：

```bash
docker compose restart
```

### 11.2 `control ui requires device identity`

這通常發生在使用區網 HTTP，而不是 `localhost` 或 HTTPS。

暫時測試可使用：

```json
"dangerouslyDisableDeviceAuth": true
```

正式環境建議改用 HTTPS。

### 11.3 容器啟動了，但瀏覽器打不開

先檢查：

```bash
docker compose ps
docker logs openclaw-server --tail 50
```

如果 log 顯示：

```text
[gateway] listening on ws://127.0.0.1:3000
```

表示 OpenClaw 仍只綁在 loopback，需要確認 `openclaw.json` 內是否為：

```json
"bind": "lan"
```

### 11.4 重啟後要不要重新認證

通常不用。

只要以下資料夾還在，設定與 OAuth 狀態通常會保留：

- [data/.openclaw](/home/tuffy/openclaw-docker-compose/data/.openclaw)
- [data/workspace](/home/tuffy/openclaw-docker-compose/data/workspace)
- [data/openclaw_data](/home/tuffy/openclaw-docker-compose/data/openclaw_data)

如果刪掉 [data/.openclaw](/home/tuffy/openclaw-docker-compose/data/.openclaw)，就可能需要重新登入。

## 12. 常用檢查指令

```bash
docker compose up -d
docker compose down
docker compose restart
docker compose ps
docker compose config
docker logs openclaw-server --tail 50
docker exec -it openclaw-server sh
```

容器內常用檢查：

```bash
env | sort | grep OPENCLAW
cat /home/node/.openclaw/openclaw.json
curl http://127.0.0.1:3000/health
openclaw models status
openclaw models status --probe
```
