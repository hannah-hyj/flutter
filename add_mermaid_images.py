import re
import json
import base64

def generate_mermaid_url(code):
    payload = json.dumps({
        "code": code.strip(),
        "mermaid": {"theme": "default"}
    })
    # urlsafe_b64encode adds padding by default, mermaid.ink handles it fine
    b64 = base64.urlsafe_b64encode(payload.encode('utf-8')).decode('utf-8')
    return f"https://mermaid.ink/img/{b64}"

def process_file(filename):
    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()

    # Find all ```mermaid ... ``` blocks
    pattern = re.compile(r'```mermaid\n(.*?)```', re.DOTALL)
    
    def replacer(match):
        code = match.group(1)
        url = generate_mermaid_url(code)
        img_tag = f"![Mermaid Diagram]({url})\n\n*(如果您无法看到上图，请参阅下方的 Mermaid 源码)*\n\n"
        # in english, use english disclaimer
        if 'zh' not in filename:
            img_tag = f"![Mermaid Diagram]({url})\n\n*(If you cannot see the image above, see the Mermaid source below)*\n\n"
        return img_tag + match.group(0)

    # But wait, what if I already added it? Let's check first.
    if "https://mermaid.ink/img/" not in content:
        new_content = pattern.sub(replacer, content)
        with open(filename, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Added mermaid images to {filename}")

files = [
    'text_plugins_design_doc.md',
    'text_plugins_design_doc_zh.md'
]

for f in files:
    try:
        process_file(f)
    except Exception as e:
        print(f"Error on {f}: {e}")

