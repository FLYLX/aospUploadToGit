#!/bin/bash
clear
echo "============================================="
echo "  标准初始化 | 清华镜像拉取 Repo 工具"
echo "============================================="

# 1. 清理旧环境
rm -rf .repo

# 2. 初始化 (清华镜像拉 git-repo，你的项目配置)
./repo init \
-u http://10.161.60.141:3000/aosp13/manifests \
-b master \
-m final_manifest.xml \
--repo-url=https://mirrors.tuna.tsinghua.edu.cn/git/git-repo \
--repo-branch=stable

# 🔥 核心：使用初始化后生成的官方 repo 工具执行命令
REPO="./.repo/repo/repo"

# 3. 同步代码
$REPO sync --force-sync --fail-fast -j88


echo -e "\n✅ 初始化完成"
