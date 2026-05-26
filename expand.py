import os

def expand(filename, base_dir):
    with open(os.path.join(base_dir, filename), 'r') as f:
        content = f.read()
    
    result = []
    lines = content.split('\n')
    for line in lines:
        if line.strip().startswith('{$include ') or line.strip().startswith('{$I '):
            # extract include filename
            parts = line.strip().split()
            inc_file = parts[1].replace('}', '').replace("'", "").replace('"', '').strip()
            result.extend(expand(inc_file, base_dir))
        else:
            result.append(line)
    return result

expanded = expand('compiler.pas', 'compiler')
for idx, line in enumerate(expanded[5260:5310], start=5261):
    print(f"{idx}: {line}")
