import re

def filter_cases(filename):
    with open(filename, 'r', encoding='utf-8') as f:
        text = f.read()

    # The section starts at "## 6. Exhaustive Corner Cases"
    # We will find where it starts
    sec_start = text.find("\n## 6.")
    if sec_start == -1:
        print(f"Could not find section 6 in {filename}")
        return
        
    intro_end = text.find("\n### Corner Case 1:", sec_start)
    if intro_end == -1:
        print("Could not find Corner Case 1")
        return
        
    pre_cases = text[:intro_end]
    cases_text = text[intro_end:]
    
    # Split by "\n### Corner Case "
    parts = re.split(r'\n### Corner Case \d+:', cases_text)
    
    # parts[0] is empty or whitespace
    cases = parts[1:]
    
    print(f"Found {len(cases)} cases in {filename}.")
    
    # We want to keep cases 1 to 10, skip 11, keep 12, keep 13, skip 14.
    # Note: 0-indexed:
    # 0 -> Case 1
    # 1 -> Case 2
    # 2 -> Case 3
    # 3 -> Case 4
    # 4 -> Case 5
    # 5 -> Case 6
    # 6 -> Case 7
    # 7 -> Case 8
    # 8 -> Case 9
    # 9 -> Case 10
    # 10 -> Case 11 (Static vs Editable - OBSOLETE)
    # 11 -> Case 12 (Lazy Slivers)
    # 12 -> Case 13 (Canvas State Corruption)
    # 13 -> Case 14 (Accessibility - Future pub.dev feature)
    
    kept_cases = []
    for i, case in enumerate(cases):
        original_num = i + 1
        if original_num in [11, 14]:
            continue
        kept_cases.append(case)
        
    # Reassemble and renumber
    out = pre_cases
    # update "14 critical corner cases" to "12 critical corner cases"
    out = out.replace("14 critical corner cases", "12 critical corner cases")
    out = out.replace("14 个 Corner Cases", "12 个 Corner Cases")
    out = out.replace("14 个核心边界情况", "12 个核心边界情况")
    out = out.replace("14 个极端边界情况", "12 个极端边界情况")
    
    for i, case in enumerate(kept_cases):
        new_num = i + 1
        out += f"\n### Corner Case {new_num}:{case}"
        
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(out)
        
    print(f"Filtered cases in {filename}")

filter_cases('text_plugins_design_doc.md')
filter_cases('text_plugins_design_doc_zh.md')
