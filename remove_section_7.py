import re

def remove_sec_7(filename):
    with open(filename, 'r', encoding='utf-8') as f:
        text = f.read()
    
    # Split the text at "## 7. " and keep only the first part
    parts = re.split(r'\n## 7\. ', text)
    if len(parts) > 1:
        # Save the part before section 7
        with open(filename, 'w', encoding='utf-8') as f:
            f.write(parts[0].rstrip() + '\n')
        print(f"Removed Section 7 from {filename}")
    else:
        print(f"Section 7 not found in {filename}")

remove_sec_7("text_plugins_design_doc.md")
remove_sec_7("text_plugins_design_doc_zh.md")
