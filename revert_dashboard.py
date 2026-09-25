import re

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/components/Dashboard/index.tsx', 'r') as f:
    code = f.read()

code = code.replace("import { Calendar, RotateCw, Lock, Unlock } from 'lucide-react'\nimport ClosingEntryWidget from './ClosingEntryWidget'", "import { Calendar, RotateCw } from 'lucide-react'")

code = code.replace("""        <ClosingEntryWidget />
        <div className="header-row">""", """        <div className="header-row">""")

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/components/Dashboard/index.tsx', 'w') as f:
    f.write(code)

