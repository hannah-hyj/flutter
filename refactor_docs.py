import re
import sys

def refactor(filename, is_zh=False):
    with open(filename, 'r', encoding='utf-8') as f:
        text = f.read()

    sections = {}
    current_text = text
    for i in range(9, 0, -1):
        marker = f"## {i}. "
        if marker in current_text:
            parts = current_text.split(marker)
            sections[i] = parts[1]
            current_text = parts[0]
            
    frontmatter = current_text
    
    # ---------------------------------------------------------
    # NEW SECTION 2: Broader Ecosystem Use Cases (old 7)
    # ---------------------------------------------------------
    old_7_title = sections[7].split("\n", 1)[0]
    old_7_content = sections[7].split("\n", 1)[1]
    old_7_content = re.sub(r'### 7\.', r'### 2.', old_7_content)
    new_sec_2 = f"{old_7_title}\n" + old_7_content

    # ---------------------------------------------------------
    # NEW SECTION 3: Design Goals & Framework/Community Taxonomy (old 2 + 8)
    # ---------------------------------------------------------
    new_sec_3_title = "Design Goals & Framework/Community Taxonomy\n" if not is_zh else "设计目标与 API 划界战略 (Design Goals & Framework/Community Taxonomy)\n"
    
    old_2_title = sections[2].split("\n", 1)[0]
    old_2_content = sections[2].split("\n", 1)[1]
    sec_3_body = f"\n### 3.1 {old_2_title}\n" + old_2_content
    
    old_8_title = sections[8].split("\n", 1)[0]
    old_8_content = sections[8].split("\n", 1)[1]
    # Demote 8.x to #### 3.2.x
    old_8_content = old_8_content.replace("### 8.1", "#### 3.2.1").replace("### 8.2", "#### 3.2.2").replace("### 8.3", "#### 3.2.3")
    sec_3_body += f"\n### 3.2 {old_8_title}\n" + old_8_content
    
    new_sec_3 = new_sec_3_title + sec_3_body

    # ---------------------------------------------------------
    # NEW SECTION 4: Architecture & Component Design (old 3)
    # ---------------------------------------------------------
    old_3_title = sections[3].split("\n", 1)[0]
    old_3_content = sections[3].split("\n", 1)[1]
    old_3_content = re.sub(r'### 3\.', r'### 4.', old_3_content)
    new_sec_4 = f"{old_3_title}\n" + old_3_content

    # ---------------------------------------------------------
    # NEW SECTION 5: Feature Deep Dives (old 6 + 5)
    # ---------------------------------------------------------
    new_sec_5_title = "Feature Deep Dives\n" if not is_zh else "高阶特性深度探讨 (Feature Deep Dives)\n"
    
    # Old 6 becomes 5.1
    old_6_title = sections[6].split("\n", 1)[0]
    old_6_content = sections[6].split("\n", 1)[1]
    # Demote internal 6.x to #### 5.1.x
    old_6_content = re.sub(r'### 6\.', r'#### 5.1.', old_6_content)
    sec_5_body = f"\n### 5.1 {old_6_title}\n" + old_6_content
    
    # Old 5 becomes 5.2
    old_5_title = sections[5].split("\n", 1)[0]
    old_5_content = sections[5].split("\n", 1)[1]
    # Demote internal 5.x to #### 5.2.x
    old_5_content = re.sub(r'### 5\.', r'#### 5.2.', old_5_content)
    sec_5_body += f"\n### 5.2 {old_5_title}\n" + old_5_content
    
    new_sec_5 = new_sec_5_title + sec_5_body

    # ---------------------------------------------------------
    # NEW SECTION 6: Corner Cases (old 4)
    # ---------------------------------------------------------
    old_4_title = sections[4].split("\n", 1)[0]
    old_4_content = sections[4].split("\n", 1)[1]
    new_sec_6 = f"{old_4_title}\n" + old_4_content

    # ---------------------------------------------------------
    # NEW SECTION 7: Summary (old 9)
    # ---------------------------------------------------------
    old_9_title = sections[9].split("\n", 1)[0]
    old_9_content = sections[9].split("\n", 1)[1]
    new_sec_7 = f"{old_9_title}\n" + old_9_content

    # Reassemble
    out = frontmatter
    out += "## 1. " + sections[1]
    out += "## 2. " + new_sec_2
    out += "## 3. " + new_sec_3
    out += "## 4. " + new_sec_4
    out += "## 5. " + new_sec_5
    out += "## 6. " + new_sec_6
    out += "## 7. " + new_sec_7

    with open(filename, 'w', encoding='utf-8') as f:
        f.write(out)

    print(f"Refactored {filename} successfully.")

refactor("text_plugins_design_doc.md", is_zh=False)
refactor("text_plugins_design_doc_zh.md", is_zh=True)
