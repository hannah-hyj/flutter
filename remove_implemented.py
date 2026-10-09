import re

def clean_doc(filename, is_zh=False):
    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()

    if is_zh:
        content = content.replace("## 2. 更广泛的生态应用场景与已实现的插件", "## 2. 更广泛的生态应用场景 (Broader Ecosystem Use Cases)")
        content = content.replace("，为 Flutter 生态解锁了一系列“即插即用”的插件能力：", "，为 Flutter 生态解锁了一系列“即插即用”的强大插件能力：")
        # I'll just regex remove the (已实现: ...) blocks
        content = re.sub(r' \(已实现: \[.*?\]\(.*?\)\)', '', content)
        # Also clean up the intro paragraph if needed
    else:
        content = content.replace("## 2. Broader Ecosystem Use Cases & Implemented Plugins", "## 2. Broader Ecosystem Use Cases")
        content = re.sub(r', along with the \*\*three additional plugins\*\* we implemented in `examples/text_plugins/`', '', content)
        content = re.sub(r' \(\*\*Implemented\*\*: \[.*?\]\(.*?\)\)', '', content)

    with open(filename, 'w', encoding='utf-8') as f:
        f.write(content)

    print(f"Cleaned {filename}")

clean_doc('text_plugins_design_doc.md', is_zh=False)
clean_doc('text_plugins_design_doc_zh.md', is_zh=True)
