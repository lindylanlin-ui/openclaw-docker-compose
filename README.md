# OpenClaw Docker Compose SOP

本文件整理這個專案從零開始到成功啟動 OpenClaw，並把預設模型固定為 `openai-codex/gpt-5.4-mini` 的完整流程。

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

## 3. 建立 `.env` 與 `.env.secrets`

可直接從 [`.env.example`](/home/tuffy/openclaw-docker-compose/.env.example) 複製：

```bash
cp .env.example .env
cp .env.secrets.example .env.secrets
```

`.env` 放非敏感設定，內容可參考：

```env
OPENCLAW_CONFIG_DIR=/absolute/path/to/openclaw-docker-compose/data/.openclaw
OPENCLAW_WORKSPACE_DIR=/absolute/path/to/openclaw-docker-compose/data/workspace
OPENCLAW_OPENCLAWDATA_DIR=/absolute/path/to/openclaw-docker-compose/data/openclaw_data
OPENCLAW_GATEWAY_PORT=3000
# OPENCLAW_BRIDGE_PORT=3001
# OPENCLAW_GATEWAY_BIND=lan
OPENCLAW_GATEWAY_HOST=0.0.0.0
OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:latest
# OPENCLAW_EXTRA_MOUNTS=
# OPENCLAW_HOME_VOLUME=
# OPENCLAW_DOCKER_APT_PACKAGES=
# OPENCLAW_EXTENSIONS=
# OPENCLAW_SANDBOX=
# OPENCLAW_DOCKER_SOCKET=
# OPENCLAW_INSTALL_DOCKER_CLI=
OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=false
OPENCLAW_TZ=Asia/Taipei
OPENCLAW_MODE=gateway
```

`.env.secrets` 只放敏感值：

```env
OPENCLAW_GATEWAY_TOKEN=replace-with-a-long-random-token
TELEGRAM_BOT_TOKEN=replace-with-your-telegram-bot-token
GEMINI_CLI_OAUTH_CLIENT_SECRET=replace-if-you-use-gemini
# OPENAI_API_KEY=sk-...
```

產生 gateway token 可使用：

```bash
openssl rand -hex 32
```

## 4. 建立 `docker-compose.yml`

可直接從 [docker-compose.yml.example](/home/tuffy/openclaw-docker-compose/docker-compose.yml.example) 複製：

```bash
cp docker-compose.yml.example docker-compose.yml
```

目前建議使用這份設定：

```yaml
services:
  openclaw:
    image: ${OPENCLAW_IMAGE}
    container_name: openclaw-server
    restart: unless-stopped

    ports:
      - "127.0.0.1:${OPENCLAW_GATEWAY_PORT}:3000"

    env_file:
      - .env
      - .env.secrets
    environment:
      - OPENCLAW_MODE=${OPENCLAW_MODE}
      - OPENCLAW_GATEWAY_HOST=${OPENCLAW_GATEWAY_HOST}
      - OPENCLAW_GATEWAY_PORT=${OPENCLAW_GATEWAY_PORT}
      - OPENCLAW_TZ=${OPENCLAW_TZ}
      - TZ=${OPENCLAW_TZ}

    volumes:
      - ${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
      - ${OPENCLAW_WORKSPACE_DIR}:/home/node/workspace
      - ${OPENCLAW_OPENCLAWDATA_DIR}:/home/node/data
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro

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

- `ports` 使用 `"127.0.0.1:${OPENCLAW_GATEWAY_PORT}:3000"`，代表只有本機可連到 Gateway
- `volumes` 要掛到 `/home/node/...`，因為容器內實際使用的是這個路徑
- `.env.secrets` 不應提交到版本控制，建議權限至少設成 `chmod 600 .env.secrets`

## 5. 建立 `data/.openclaw/openclaw.json`

可直接從 [openclaw.json.example](/home/tuffy/openclaw-docker-compose/openclaw.json.example) 複製：

```bash
cp openclaw.json.example data/.openclaw/openclaw.json
```

請建立或修改 [data/.openclaw/openclaw.json](/home/tuffy/openclaw-docker-compose/data/.openclaw/openclaw.json)：

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "openai-codex/gpt-5.4-mini"
      },
      "models": {
        "openai-codex/gpt-5.4-mini": {
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
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "groups": {
        "*": {
          "requireMention": true
        }
      },
      "groupPolicy": "open",
      "streaming": {
        "mode": "off"
      }
    }
  },
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "controlUi": {
      "allowedOrigins": [
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://192.168.1.10:3000"
      ]
    },
    "auth": {
      "mode": "token"
    }
  }
}
```

重點：

- `gateway.bind: "lan"`：讓 OpenClaw 在容器內綁定 `0.0.0.0`
- `allowedOrigins`：加入你實際會開啟 Control UI 的網址
- `agents.defaults.model.primary`：把預設模型固定成 `openai-codex/gpt-5.4-mini`
- `channels.telegram`：啟用 Telegram Bot API，私訊預設走 pairing，群組預設可用但需要 `@bot` mention

建議不要把 `channels.telegram.botToken` 或 `gateway.auth.token` 直接寫進 `openclaw.json`。
讓 OpenClaw 回退使用 `.env.secrets` 內的 `TELEGRAM_BOT_TOKEN` 與 `OPENCLAW_GATEWAY_TOKEN`，暴露面會比較小。

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

## 9. 驗證 `openai-codex/gpt-5.4-mini` 是否設定成功

在容器內執行：

```bash
openclaw models status
```

建議再做一次實際探測：

```bash
openclaw models status --probe
```

你應確認：

- 預設模型是 `openai-codex/gpt-5.4-mini`
- `openai-codex` 認證狀態不是 missing 或 expired

離開容器：

```bash
exit
```

## 10. 串接 Telegram

### 10.1 建立 Telegram bot

在 Telegram 搜尋 `@BotFather`，依序執行：

```text
/newbot
```

依提示完成後，BotFather 會給你一組 bot token。

建議把這組 token 放進 `.env.secrets`：

```env
TELEGRAM_BOT_TOKEN=請填入你的 BotFather token
```

### 10.2 重新啟動並驗證 Telegram channel

```bash
docker compose restart openclaw
docker exec openclaw-server sh -lc 'openclaw channels status --probe'
```

正常情況會看到類似：

```text
- Telegram default: enabled, configured, running, mode:polling, bot:@your_bot, token:env, works
```

如果顯示 `token:config`，表示目前實際使用的是 `openclaw.json` 內的 `channels.telegram.botToken`。

### 10.3 私訊啟用與 pairing

Telegram 私訊預設是 `dmPolicy: "pairing"`，第一次私訊 bot 時，OpenClaw 會要求 pairing。

可在容器內查看與核准：

```bash
docker exec -it openclaw-server sh
openclaw pairing list telegram
openclaw pairing approve telegram <配對碼>
```

### 10.4 讓 bot 能讀取群組訊息

若要在 Telegram 群組正常觸發 bot，除了把 bot 加入群組，還建議到 `@BotFather` 關閉 privacy mode：

1. 在 Telegram 中打開 `@BotFather`
2. 輸入 `/mybots`
3. 選擇你的 bot
4. 點 `Bot Settings`
5. 點 `Group Privacy`
6. 選 `Turn off` 或 `Disable`

修改後，請把 bot 從原群組移除，再重新加回群組，讓 Telegram 套用新的群組隱私設定。

## 11. 在 Telegram 群組內使用

目前這份設定：

- 允許群組使用 Telegram bot
- 群組訊息需要 `@bot` 才會觸發
- 不需要先完成 DM pairing 才能在群組內使用

在群組中可直接這樣下指令：

```text
@your_bot_username 幫我整理今天這個專案進度
@your_bot_username 幫我把這段需求改寫成工程 task
@your_bot_username 幫我查今天台積電股價
```

如果要根據某一則訊息做事，建議用「回覆該訊息 + mention bot」的方式，例如：

```text
@your_bot_username 幫我總結上面那段對話
```

若想讓群組內不用 mention 也能觸發，可把 `channels.telegram.groups."*".requireMention` 改成 `false`，但這樣 bot 會更容易被群組一般聊天誤觸發。

## 12. 開啟 Control UI

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

## 13. 常見問題

### 13.1 `origin not allowed`

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

### 13.2 `control ui requires device identity`

這通常發生在使用區網 HTTP，而不是 `localhost` 或 HTTPS。

暫時測試可使用：

```json
"dangerouslyDisableDeviceAuth": true
```

正式環境建議改用 HTTPS。

### 13.3 容器啟動了，但瀏覽器打不開

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

### 13.4 Telegram 顯示 `works`，但群組內叫 bot 沒反應

先依序檢查：

1. bot 是否真的已加入該群組
2. 訊息是否有正確 `@bot_username`
3. `channels.telegram.groups."*".requireMention` 是否仍為 `true`
4. BotFather 的 `Group Privacy` 是否已關閉
5. 關閉 privacy mode 後，是否已把 bot 移除再重新加回群組

可再用以下指令確認 Telegram channel 狀態：

```bash
docker exec openclaw-server sh -lc 'openclaw channels status --probe'
```

若輸出包含：

```text
- Telegram default: enabled, configured, running, mode:polling, bot:@your_bot, works
```

表示 Telegram 連線本身正常，通常問題在群組觸發條件或 Telegram 群組隱私設定。

### 13.5 重啟後要不要重新認證

通常不用。

只要以下資料夾還在，設定與 OAuth 狀態通常會保留：

- [data/.openclaw](/home/tuffy/openclaw-docker-compose/data/.openclaw)
- [data/workspace](/home/tuffy/openclaw-docker-compose/data/workspace)
- [data/openclaw_data](/home/tuffy/openclaw-docker-compose/data/openclaw_data)

如果刪掉 [data/.openclaw](/home/tuffy/openclaw-docker-compose/data/.openclaw)，就可能需要重新登入。

## 14. 常用檢查指令

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
