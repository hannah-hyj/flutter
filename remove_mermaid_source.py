import re

def remove_mermaid(filename):
    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Match the disclaimer text and the mermaid block
    # English
    content = re.sub(r'\*\(If you cannot see the image above, see the Mermaid source below\)\*\n\n```mermaid\n.*?```\n', '', content, flags=re.DOTALL)
    # Chinese
    content = re.sub(r'\*\(如果您无法看到上图，请参阅下方的 Mermaid 源码\)\*\n\n```mermaid\n.*?```\n', '', content, flags=re.DOTALL)
    
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"Removed mermaid source from {filename}")

remove_mermaid('text_plugins_design_doc.md')
remove_mermaid('text_plugins_design_doc_zh.md')
