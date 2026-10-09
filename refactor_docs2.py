import re

def refactor(filename, is_zh=False):
    with open(filename, 'r', encoding='utf-8') as f:
        text = f.read()

    # Split by exactly "\n## X. "
    # We'll use a regex that captures the section number and the content
    parts = re.split(r'\n## (\d+)\. ', '\n' + text)
    
    frontmatter = parts[0].lstrip('\n')
    sections = {}
    for i in range(1, len(parts), 2):
        sec_num = int(parts[i])
        sec_content = parts[i+1]
        sections[sec_num] = sec_content
        print(f"[{filename}] Extracted section {sec_num}: {sec_content[:40].strip()}...")
        
    # NEW SECTION 2: (Old 7)
    old_7_content = sections[7]
    old_7_content = re.sub(r'\n### 7\.', r'\n### 2.', old_7_content)
    new_sec_2 = "\n## 2. " + old_7_content.strip() + "\n"

    # NEW SECTION 3: (Old 2 + 8)
    new_sec_3_title = "Design Goals & Framework/Community Taxonomy" if not is_zh else "设计目标与 API 划界战略 (Design Goals & Framework/Community Taxonomy)"
    
    # Extract title from Old 2
    old_2_lines = sections[2].split("\n", 1)
    old_2_title = old_2_lines[0].strip()
    old_2_body = old_2_lines[1]
    
    # Extract title from Old 8
    old_8_lines = sections[8].split("\n", 1)
    old_8_title = old_8_lines[0].strip()
    old_8_body = old_8_lines[1]
    
    # Demote 8.x to 3.2.x
    old_8_body = old_8_body.replace("\n### 8.1", "\n#### 3.2.1").replace("\n### 8.2", "\n#### 3.2.2").replace("\n### 8.3", "\n#### 3.2.3")
    
    new_sec_3 = f"\n## 3. {new_sec_3_title}\n\n### 3.1 {old_2_title}\n{old_2_body}\n\n### 3.2 {old_8_title}\n{old_8_body}\n"
    
    # NEW SECTION 4: (Old 3)
    old_3_content = sections[3]
    old_3_content = re.sub(r'\n### 3\.', r'\n### 4.', old_3_content)
    new_sec_4 = "\n## 4. " + old_3_content.strip() + "\n"

    # NEW SECTION 5: (Old 6 + 5)
    new_sec_5_title = "Feature Deep Dives" if not is_zh else "高阶特性深度探讨 (Feature Deep Dives)"
    
    old_6_lines = sections[6].split("\n", 1)
    old_6_title = old_6_lines[0].strip()
    old_6_body = old_6_lines[1]
    old_6_body = re.sub(r'\n### 6\.', r'\n#### 5.1.', old_6_body)
    
    old_5_lines = sections[5].split("\n", 1)
    old_5_title = old_5_lines[0].strip()
    old_5_body = old_5_lines[1]
    old_5_body = re.sub(r'\n### 5\.', r'\n#### 5.2.', old_5_body)
    
    new_sec_5 = f"\n## 5. {new_sec_5_title}\n\n### 5.1 {old_6_title}\n{old_6_body}\n\n### 5.2 {old_5_title}\n{old_5_body}\n"

    # NEW SECTION 6: (Old 4)
    old_4_content = sections[4]
    new_sec_6 = "\n## 6. " + old_4_content.strip() + "\n"

    # NEW SECTION 7: (Old 9)
    old_9_content = sections[9]
    new_sec_7 = "\n## 7. " + old_9_content.strip() + "\n"

    # REASSEMBLE
    out = frontmatter.strip() + "\n"
    out += "\n## 1. " + sections[1].strip() + "\n"
    out += new_sec_2
    out += new_sec_3
    out += new_sec_4
    out += new_sec_5
    out += new_sec_6
    out += new_sec_7

    with open(filename, 'w', encoding='utf-8') as f:
        f.write(out)

    print(f"Refactored {filename} successfully.")

refactor("text_plugins_design_doc.md", is_zh=False)
refactor("text_plugins_design_doc_zh.md", is_zh=True)
