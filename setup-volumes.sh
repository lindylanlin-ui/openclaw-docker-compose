#!/bin/bash

# 初始化 OpenClaw Docker Compose 所需的掛載目錄腳本
# 此腳本會創建所需的目錄並設置適當的權限
# 
# 權限策略: 將目錄所有權設為容器內的 node 用戶（UID 1000）
#          並使用 755 權限（擁有者可讀寫執行，其他人僅可讀）

set -e

echo "=== OpenClaw 目錄初始化腳本 ==="

# 檢查是否需要 sudo（當前用戶 UID 不是 1000 時）
CURRENT_UID=$(id -u)
NEED_SUDO=""
if [ "$CURRENT_UID" != "1000" ]; then
    echo "提示: 當前用戶 UID 是 $CURRENT_UID，將使用 sudo 設置權限"
    NEED_SUDO="sudo"
fi

# 檢查 .env 檔案是否存在
if [ ! -f .env ]; then
    echo "錯誤: 找不到 .env 檔案"
    echo "請先複製 .env.example 到 .env 並設定正確的路徑"
    exit 1
fi

# 載入環境變數
source .env

# 需要創建的目錄列表
DIRS=(
    "$OPENCLAW_CONFIG_DIR"
    "$PROJECT_DIR"
    "$TEMP_DATA_DIR"
)

# 創建目錄並設置權限
for dir in "${DIRS[@]}"; do
    if [ -z "$dir" ]; then
        echo "警告: 檢測到空的目錄路徑，請檢查 .env 設定"
        continue
    fi
    
    if [ ! -d "$dir" ]; then
        echo "創建目錄: $dir"
        mkdir -p "$dir"
    else
        echo "目錄已存在: $dir"
    fi
    
    # 設置權限，確保容器內的 node 用戶（UID 1000）可以讀寫
    echo "設置權限: $dir"
    
    # 將目錄所有權設置為容器內的 node 用戶（UID:GID = 1000:1000）
    $NEED_SUDO chown -R 1000:1000 "$dir"
    
    # 設置合理的權限：擁有者可讀寫執行，群組可讀執行，其他人無權限
    $NEED_SUDO chmod -R 755 "$dir"
done

echo ""
echo "✅ 目錄初始化完成！"
echo ""
echo "權限設置:"
echo "  - 所有者: UID 1000 (容器內的 node 用戶)"
echo "  - 權限: 755 (rwxr-xr-x)"
echo ""
echo "接下來請執行:"
echo "  docker-compose up -d"
