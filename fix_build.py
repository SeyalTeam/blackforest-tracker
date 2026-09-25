import re
import os

def replace_in_file(filepath, old, new):
    if not os.path.exists(filepath): return
    with open(filepath, 'r') as f:
        code = f.read()
    code = code.replace(old, new)
    with open(filepath, 'w') as f:
        f.write(code)

base = '/Users/castromurugan/Documents/Blackforest/blackforest-payload'

# 1. payload.config.ts
replace_in_file(f'{base}/src/payload.config.ts', 
  "autoIndex: process.env.NODE_ENV !== 'production',", 
  "// autoIndex: process.env.NODE_ENV !== 'production',")

# 2. Media.ts
replace_in_file(f'{base}/src/collections/Media.ts', 
  "user?.role === 'watcher'", 
  "(user?.role as string) === 'watcher'")

# 3. rawMaterialBilling.ts
replace_in_file(f'{base}/src/services/reports/rawMaterialBilling.ts', 
  "notes: toNonEmptyString(item.notes, ''),", 
  "notes: toNonEmptyString((item as any).notes, ''),")

# 4. WorkTasksBoard
replace_in_file(f'{base}/src/components/WorkTasksBoard/index.tsx', 
  "task.assignmentType !== 'unassigned'", 
  "(task.assignmentType as string) !== 'unassigned'")
replace_in_file(f'{base}/src/components/WorkTasksBoard/index.tsx', 
  "t.assignmentType !== 'unassigned'", 
  "(t.assignmentType as string) !== 'unassigned'")
replace_in_file(f'{base}/src/components/WorkTasksBoard/index.tsx', 
  "activeModalCard.assignmentType === 'unassigned'", 
  "(activeModalCard.assignmentType as string) === 'unassigned'")
replace_in_file(f'{base}/src/components/WorkTasksBoard/index.tsx', 
  "assignmentType: 'unassigned',", 
  "assignmentType: 'unassigned' as any,")

# 5. WidgetSettings
replace_in_file(f'{base}/src/components/WidgetSettings/index.tsx',
  "activeWidget === 'attendance'",
  "(activeWidget as string) === 'attendance'")
replace_in_file(f'{base}/src/components/WidgetSettings/index.tsx',
  "setActiveWidget('attendance')",
  "setActiveWidget('attendance' as any)")

# 6. ReportGraph
replace_in_file(f'{base}/src/components/ReportGraph/index.tsx',
  "<Gutter style={{ paddingTop: '50px' }}>",
  '<Gutter className="pt-[50px]">')
replace_in_file(f'{base}/src/app/(frontend)/report-graph/page.tsx',
  "findIndex(pt =>",
  "findIndex((pt: any) =>")
replace_in_file(f'{base}/src/app/(frontend)/report-graph/page.tsx',
  "flexShrink={0}",
  "style={{ flexShrink: 0 }}")


