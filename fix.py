import xml.etree.ElementTree as ET

# 配置文件路径
INPUT_XML  = "tspi_1f_rk3566_linux.xml"
OUTPUT_XML = "final_manifest.xml"
# 你的私有仓库地址
NEW_FETCH_URL = "http://10.161.60.141:3000/aosp13/"

def fix_manifest():
    # 解析XML
    tree = ET.parse(INPUT_XML)
    root = tree.getroot()

    # ===================== 1. 处理远程仓库 remote =====================
    for remote in root.findall("remote"):
        # 修改fetch为你的私有仓库地址
        remote.set("fetch", NEW_FETCH_URL)
        # 删除无用的 review 属性
        if "review" in remote.attrib:
            del remote.attrib["review"]

    # ===================== 2. 处理默认配置 default =====================
    for default in root.findall("default"):
        # 统一默认分支为 aosp13
        default.set("revision", "aosp13")

    # ===================== 3. 处理所有 project 标签 =====================
    for project in root.findall("project"):
        original_name = project.get("name")
        if not original_name:
            continue

        # ① name 中所有 / 替换为 _
        new_name = original_name.replace("/", "_")
        project.set("name", new_name)

        # ② 有path保留，无path自动用原始name填充
        if not project.get("path"):
            project.set("path", original_name)

        # ③ 强制修改 revision 为 aosp13
        project.set("revision", "aosp13")

        # ④ 删除所有无用属性（新增clone-depth）
        remove_attrs = ["upstream", "dest-branch", "clone-depth"]
        for attr in remove_attrs:
            if attr in project.attrib:
                del project.attrib[attr]

    # 写入标准XML文件
    tree.write(OUTPUT_XML, encoding="utf-8", xml_declaration=True)
    
    # 打印结果
    print("="*60)
    print("✅ 脚本处理完成！")
    print(f"📂 输入文件：{INPUT_XML}")
    print(f"📂 输出文件：{OUTPUT_XML}")
    print("="*60)
    print("🔥 处理清单：")
    print("1. name 所有 / → 下划线")
    print("2. 有path保留，无path自动补全")
    print("3. 所有 revision 强制改为 aosp13")
    print("4. 删除：upstream / dest-branch / clone-depth")
    print("5. 远程仓库地址改为你的私有服务器")
    print("6. 删除无用 review 属性")
    print("7. 全局默认分支统一为 aosp13")
    print("="*60)

if __name__ == "__main__":
    fix_manifest()
