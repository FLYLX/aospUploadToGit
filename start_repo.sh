#!/bin/bash

# ====================== 你的配置 ======================
GITEA_HOST="10.161.60.141:3000"
GITEA_ORG="aosp13"
GIT_USER="liuxin"
GIT_PASS=""
TARGET_BRANCH="aosp13"
XML_FILE="tspi_1f_rk3566_linux.xml"
JSON_OUTPUT="project_map.json"
# ======================================================

# ===================== 1. 扫描XML ======================
scan_mode() {
    echo "===== 开始扫描 XML 项目仓库 ====="
    if [ ! -f "$XML_FILE" ]; then
        echo "❌ 错误：未找到文件 $XML_FILE"
        exit 1
    fi

    echo "{" > "$JSON_OUTPUT"
    grep -o '<project [^>]*' "$XML_FILE" | while read -r line; do
        name=$(echo "$line" | sed -n 's/.*name="\([^"]*\)".*/\1/p')
        path=$(echo "$line" | sed -n 's/.*path="\([^"]*\)".*/\1/p')
        
        if [ -z "$path" ]; then path="$name"; fi
        [ -z "$name" ] && continue
        
        key=$(echo "$name" | tr '/' '_')
        echo "    \"$key\": \"$path\"," >> "$JSON_OUTPUT"
    done

    sed -i '$ s/,$//' "$JSON_OUTPUT"
    echo "}" >> "$JSON_OUTPUT"
    repo_count=$(grep -c '"' "$JSON_OUTPUT" | awk '{print $1-2}')

    echo -e "\n✅ 扫描完成！共找到【 $repo_count 】个项目"
}

# ===================== 2. 检查仓库 ======================
check_mode() {
    if [ ! -f "$JSON_OUTPUT" ]; then
        echo "❌ 错误：先执行 scan！"
        exit 1
    fi

    total_count=$(grep -c '"' "$JSON_OUTPUT" | awk '{print $1-2}')
    echo "===== 检查【 $total_count 】个仓库 ====="

    git_exists=0
    git_missing=0
    dir_missing=0

    awk -F'"' '/"/{print $4}' "$JSON_OUTPUT" | grep -v '^$' | while read -r repo_path; do
        git_path="${repo_path}/.git"
        if [ ! -d "$repo_path" ]; then
            echo "❌ 目录不存在：$repo_path"
            dir_missing=$((dir_missing + 1))
        elif [ -e "$git_path" ]; then
            echo "✅ .git正常：$repo_path"
            git_exists=$((git_exists + 1))
        else
            echo "⚠️  无.git：$repo_path"
            git_missing=$((git_missing + 1))
        fi
    done

    echo "--------------------------------------------------------"
    echo "总仓库：$total_count | 正常：$git_exists | 缺失.git：$git_missing | 目录不存在：$dir_missing"
}

# ===================== 3. 推送（强制保留所有空目录） ======================
push_mode() {
    if [ ! -f "$JSON_OUTPUT" ]; then
        echo "❌ 错误：先执行 scan！"
        exit 1
    fi

    total_count=$(grep -c '"' "$JSON_OUTPUT" | awk '{print $1-2}')
    echo "===== 开始推送【 $total_count 】个仓库（自动保留所有空目录） ====="

    awk -F'"' '/"/{print $2,$4}' "$JSON_OUTPUT" | while read -r REPO_NAME repo_path; do
        [ -z "$REPO_NAME" ] || [ ! -d "$repo_path" ] && continue
        cd "$repo_path" || continue

        echo -e "\n========================================"
        echo "推送：$REPO_NAME | 路径：$repo_path"

        # 清理旧git
        rm -rf .git
        find . -type d -name ".git" -exec rm -rf {} \; 2>/dev/null
        find . -name ".gitignore" -delete 2>/dev/null

        # ==============================================
        # 核心：强制给所有空目录添加 .gitkeep（必上传）
        # ==============================================
        echo "✅ 自动保留所有空目录..."
        find . -type d -empty -exec touch {}/.gitkeep \; 2>/dev/null

        # 空仓库自动创建README，保证能推送
        if [ -z "$(ls -A | grep -v '^\.git$')" ]; then
            echo "📄 空仓库自动创建 README.md"
            echo "# $REPO_NAME" > README.md
            echo "AOSP 仓库初始化" >> README.md
        fi

        # GIT 提交（包含所有空目录结构）
        git init -q
        git config user.name "$GIT_USER"
        git config user.email "$GIT_USER@local.com"
        git add -A -f
        git commit -m "初始化完整目录结构（含空目录）" -q

        git branch -M main
        git checkout -b "$TARGET_BRANCH" -q 2>/dev/null

        # 推送
        REMOTE_URL="http://$GIT_USER:$GIT_PASS@$GITEA_HOST/$GITEA_ORG/$REPO_NAME.git"
        curl -s -X POST "http://$GITEA_HOST/api/v1/orgs/$GITEA_ORG/repos" -u "$GIT_USER:$GIT_PASS" -H "Content-Type: application/json" -d "{\"name\":\"$REPO_NAME\",\"private\":false,\"auto_init\":false}" > /dev/null
        git remote remove origin 2>/dev/null
        git remote add origin "$REMOTE_URL"

        if git push -f origin main --quiet && git push -f origin "$TARGET_BRANCH" --quiet; then
            echo "✅ 推送成功（目录结构完整）"
        else
            echo "❌ 推送失败"
        fi

        cd - > /dev/null
    done

    echo -e "\n🎉 全部推送完成！空目录/完整文件结构已全部上传！"
}

# ===================== 入口 =====================
case "$1" in
    scan) scan_mode ;;
    check) check_mode ;;
    push) push_mode ;;
    *)
        echo "用法："
        echo "  ./start_repo.sh scan   # 扫描XML"
        echo "  ./start_repo.sh check  # 检查仓库"
        echo "  ./start_repo.sh push   # 推送（自动包含所有空目录+完整结构）"
        ;;
esac
