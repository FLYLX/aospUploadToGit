#!/bin/bash

# ====================== 你的配置（和原脚本一致） ======================
GITEA_HOST="10.161.60.141:3000"
GITEA_ORG="aosp13"
GIT_USER="liuxin"
GIT_PASS=""
TARGET_BRANCH="aosp13"
# XML 配置
XML_FILE="tspi_1f_rk3566_linux.xml"
JSON_OUTPUT="project_map.json"
# ====================================================================

# ===================== 1. 扫描模式：解析XML生成JSON ======================
scan_mode() {
    echo "===== 开始扫描 XML 项目仓库 ====="

    # 检查XML文件是否存在
    if [ ! -f "$XML_FILE" ]; then
        echo "❌ 错误：未找到文件 $XML_FILE"
        exit 1
    fi

    # 生成标准JSON文件
    echo "{" > "$JSON_OUTPUT"

    # 提取所有 project 的 name 和 path
    grep -o '<project [^>]*' "$XML_FILE" | while read -r line; do
        name=$(echo "$line" | sed -n 's/.*name="\([^"]*\)".*/\1/p')
        path=$(echo "$line" | sed -n 's/.*path="\([^"]*\)".*/\1/p')
        
        # ============== 核心修复：无path时，默认使用name作为path ==============
        if [ -z "$path" ]; then
            path="$name"
        fi
        # 仅跳过完全没有name的无效project
        [ -z "$name" ] && continue
        
        # name 中的 / 替换为 _ 作为键
        key=$(echo "$name" | tr '/' '_')
        echo "    \"$key\": \"$path\"," >> "$JSON_OUTPUT"
    done

    # 修复JSON格式（删除最后一个逗号）
    sed -i '$ s/,$//' "$JSON_OUTPUT"
    echo "}" >> "$JSON_OUTPUT"

    # 统计仓库数量
    repo_count=$(grep -c '"' "$JSON_OUTPUT" | awk '{print $1-2}')

    echo -e "\n✅ 扫描完成！共找到【 $repo_count 】个项目仓库"
    echo "✅ 已自动处理【无path的project】：默认使用 name 作为 path"
    echo "仓库映射已保存到：$JSON_OUTPUT"
    echo "格式：key=name(/_) | value=本地path"
}

# ===================== 2. 检查模式：检测【软链接+真实】.git 仓库 ======================
check_mode() {
    if [ ! -f "$JSON_OUTPUT" ]; then
        echo "❌ 错误：未找到 $JSON_OUTPUT，请先执行 ./start_repo.sh scan！"
        exit 1
    fi

    total_count=$(grep -c '"' "$JSON_OUTPUT" | awk '{print $1-2}')
    echo "===== 检查【 $total_count 】个仓库的 .git 仓库 ====="
    echo "检查规则：检测 path/.git → 【软链接/真实目录都算正常】"
    echo "✅ 已包含【无path的project】（自动用name作为path校验）"
    echo "--------------------------------------------------------"

    # 统计变量
    git_exists=0    # 存在.git（软链接+真实目录）
    git_missing=0   # 目录存在，但无.git
    dir_missing=0   # 目录不存在

    # 遍历JSON解析path（已自动补全无path的项目）
    awk -F'"' '/"/{print $4}' "$JSON_OUTPUT" | grep -v '^$' | while read -r repo_path; do
        git_path="${repo_path}/.git"

        if [ ! -d "$repo_path" ]; then
            echo "❌ 目录不存在：$repo_path"
            dir_missing=$((dir_missing + 1))
        elif [ -e "$git_path" ]; then
            echo "✅ .git仓库正常：$repo_path (软链接/真实目录)"
            git_exists=$((git_exists + 1))
        else
            echo "⚠️  无.git仓库：$repo_path"
            git_missing=$((git_missing + 1))
        fi
    done

    echo "--------------------------------------------------------"
    echo "📊 检查统计："
    echo "  总仓库数：$total_count"
    echo "  ✅ .git仓库正常：$git_exists (软链接+真实目录)"
    echo "  ⚠️  无.git仓库：$git_missing"
    echo "  ❌ 目录不存在：$dir_missing"
    echo "--------------------------------------------------------"
}

# ===================== 3. 推送模式（和你原版逻辑完全一致）=====================
push_mode() {
    if [ ! -f "$JSON_OUTPUT" ]; then
        echo "❌ 错误：未找到 $JSON_OUTPUT，请先执行 ./start_repo.sh scan！"
        exit 1
    fi

    total_count=$(grep -c '"' "$JSON_OUTPUT" | awk '{print $1-2}')
    echo "===== 开始推送【 $total_count 】个仓库至 Gitea ====="

    # 解析JSON，遍历 仓库名(key) + 路径(value)
    awk -F'"' '/"/{print $2,$4}' "$JSON_OUTPUT" | while read -r REPO_NAME repo_path; do
        [ -z "$REPO_NAME" ] || [ ! -d "$repo_path" ] && continue

        cd "$repo_path" || continue

        echo -e "\n========================================"
        echo "仓库名称：$REPO_NAME"
        echo "本地路径：$repo_path"

        # ===================== 原版逻辑：清理.git =====================
        rm -rf .git
        find . -type d -name ".git" -exec rm -rf {} \; 2>/dev/null
        find . -name ".gitignore" -delete 2>/dev/null

        # 初始化Git
        git init
        git config user.name "$GIT_USER"
        git config user.email "$GIT_USER@local.com"
        git add -A -f
        git commit -m "init: initial commit"

        # 创建分支
        git branch -M main
        git checkout -b "$TARGET_BRANCH" 2>/dev/null

        # 免密远程地址
        REMOTE_URL="http://$GIT_USER:$GIT_PASS@$GITEA_HOST/$GITEA_ORG/$REPO_NAME.git"

        # 创建Gitea仓库
        curl -s -X POST "http://$GITEA_HOST/api/v1/orgs/$GITEA_ORG/repos" \
          -u "$GIT_USER:$GIT_PASS" \
          -H "Content-Type: application/json" \
          -d "{\"name\":\"$REPO_NAME\",\"private\":false,\"auto_init\":false}" > /dev/null

        # 推送
        git remote remove origin 2>/dev/null
        git remote add origin "$REMOTE_URL"
        
        if git push -f origin main && git push -f origin "$TARGET_BRANCH"; then
            echo "✅ 推送成功：$REPO_NAME"
        else
            echo "❌ 推送失败：$REPO_NAME"
        fi

        cd - > /dev/null
    done

    echo -e "\n🎉 所有仓库推送流程执行完成！"
}

# ===================== 入口（和原脚本完全一样）=====================
case "$1" in
    scan) scan_mode ;;
    check) check_mode ;;
    push) push_mode ;;
    *)
        echo "用法："
        echo "  ./start_repo.sh scan   # 扫描XML生成仓库映射（自动补全无path项目）"
        echo "  ./start_repo.sh check  # 检查.git仓库(软链接+真实目录，含无path项目)"
        echo "  ./start_repo.sh push   # 批量推送至Gitea"
        ;;
esac
