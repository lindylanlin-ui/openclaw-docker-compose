1. 複製 openclaw.json.sample 到 /data/.openclaw 
   設定方式可參考文件： https://docs.openclaw.ai/zh-CN

2. docker-compse up -d
3. docker exec -it openclaw-docker-compose-openclaw-gateway-1 bash
4. docker compose run --rm openclaw-cli pairing list
