import re

def refactor(filename, is_zh=False):
    with open(filename, 'r', encoding='utf-8') as f:
        text = f.read()

    # Split by exactly "\n## X. "
    parts = re.split(r'\n## (\d+)\. ', '\n' + text)
    
    frontmatter = parts[0].lstrip('\n')
    sections = {}
    for i in range(1, len(parts), 2):
        sec_num = int(parts[i])
        sec_content = parts[i+1]
        sections[sec_num] = sec_content
        
    # Current sections:
    # 1. Problem Statement
    # 2. Broader Ecosystem
    # 3. Design Goals & Taxonomy
    # 4. Architecture
    # 5. Feature Deep Dives
    # 6. Corner Cases
    # 7. Summary
    
    # We want:
    # 1. Problem Statement (keep 1)
    # 2. Design Goals & Taxonomy (old 3)
    # 3. Architecture (old 4)
    # 4. Broader Ecosystem (old 2)
    # 5. Feature Deep Dives (keep 5)
    # 6. Corner Cases (keep 6)
    # 7. Summary (keep 7)
    
    new_sec_2 = "\n## 2. " + re.sub(r'\n### 3\.', r'\n### 2.', sections[3]).strip() + "\n"
    # Also fix #### 3.2.1 -> #### 2.2.1
    new_sec_2 = re.sub(r'\n#### 3\.', r'\n#### 2.', new_sec_2)
    
    new_sec_3 = "\n## 3. " + re.sub(r'\n### 4\.', r'\n### 3.', sections[4]).strip() + "\n"
    # Architecture doesn't have deep nested 4.x.y usually, but just in case:
    new_sec_3 = re.sub(r'\n#### 4\.', r'\n#### 3.', new_sec_3)
    
    new_sec_4 = "\n## 4. " + re.sub(r'\n### 2\.', r'\n### 4.', sections[2]).strip() + "\n"
    
    # REASSEMBLE
    out = frontmatter.strip() + "\n"
    out += "\n## 1. " + sections[1].strip() + "\n"
    out += new_sec_2
    out += new_sec_3
    out += new_sec_4
    out += "\n## 5. " + sections[5].strip() + "\n"
    out += "\n## 6. " + sections[6].strip() + "\n"
    out += "\n## 7. " + sections[7].strip() + "\n"

    with open(filename, 'w', encoding='utf-8') as f:
        f.write(out)

    print(f"Refactored {filename} successfully.")

refactor("text_plugins_design_doc.md", is_zh=False)
refactor("text_plugins_design_doc_zh.md", is_zh=True)
