import re

filename = 'text_plugins_design_doc_zh.md'
with open(filename, 'r', encoding='utf-8') as f:
    text = f.read()

sec_start = text.find("\n## 6.")
intro_end = text.find("\n### 边界 1：", sec_start)
if intro_end == -1:
    print("Could not find 边界 1：")
    exit(1)
    
pre_cases = text[:intro_end]
cases_text = text[intro_end:]

# Split by "\n### 边界 X："
parts = re.split(r'\n### 边界 \d+：', cases_text)
cases = parts[1:]

print(f"Found {len(cases)} cases in {filename}.")

kept_cases = []
for i, case in enumerate(cases):
    original_num = i + 1
    # Skip obsolete EditableText case (11) and future pub.dev accessibility case (14)
    if original_num in [11, 14]:
        continue
    kept_cases.append(case)
    
out = pre_cases
out = out.replace("14 个 Corner Cases", "12 个 Corner Cases")
out = out.replace("14 个关键边界情况", "12 个关键边界情况")

for i, case in enumerate(kept_cases):
    new_num = i + 1
    out += f"\n### 边界 {new_num}：{case}"
    
with open(filename, 'w', encoding='utf-8') as f:
    f.write(out)
    
print(f"Filtered cases in {filename}")
