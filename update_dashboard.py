import re

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/components/Dashboard/index.tsx', 'r') as f:
    code = f.read()

import_lucide = "import { Calendar, RotateCw } from 'lucide-react'"
new_import_lucide = "import { Calendar, RotateCw, Lock, Unlock } from 'lucide-react'\nimport ClosingEntryWidget from './ClosingEntryWidget'"

if "ClosingEntryWidget" not in code:
    code = code.replace(import_lucide, new_import_lucide)

    render_location = """
        <div className="header-row">
"""
    
    new_render_location = """
        <ClosingEntryWidget />
        <div className="header-row">
"""
    code = code.replace(render_location.strip(), new_render_location.strip())

    with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/components/Dashboard/index.tsx', 'w') as f:
        f.write(code)

