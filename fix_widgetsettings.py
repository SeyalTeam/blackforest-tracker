import re

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/components/WidgetSettings/index.tsx', 'r') as f:
    code = f.read()

# 1. Add WidgetKey
code = code.replace("  | 'entire-bill-blocking'", "  | 'entire-bill-blocking'\n  | 'closing-entry-access'")

# 2. Import ClosingEntryWidget
import_str = "import ClosingEntryWidget from '../Dashboard/ClosingEntryWidget'"
code = code.replace("import AttendanceWidget from '../AttendanceWidget'", "import AttendanceWidget from '../AttendanceWidget'\n" + import_str)

# 3. Add to the tile list (render)
old_api_tile = """
          <button
            type="button"
            className={`tile ${activeWidget === 'api' ? 'active' : ''}`}
            onClick={() => setActiveWidget('api')}
          >
            <Globe className="tile-icon" size={48} />
            <span className="tile-label">LIVE API</span>
          </button>
"""

new_closing_tile = """
          <button
            type="button"
            className={`tile ${(activeWidget as string) === 'closing-entry-access' ? 'active' : ''}`}
            onClick={() => setActiveWidget('closing-entry-access' as any)}
          >
            <Lock className="tile-icon" size={48} />
            <span className="tile-label">Closing Entry Access</span>
          </button>
"""

if 'Closing Entry Access' not in code:
    code = code.replace(old_api_tile.strip(), old_api_tile.strip() + "\n" + new_closing_tile.strip())

# 4. Add the component rendering
old_api_render = """
          {activeWidget === 'api' && (
"""

new_closing_render = """
          {(activeWidget as string) === 'closing-entry-access' && (
            <div className="widget-modal">
              <div className="modal-header">
                <h2>Closing Entry Access Control</h2>
                <button className="close-btn" onClick={() => setActiveWidget(null)}>
                  <X size={20} />
                </button>
              </div>
              <div className="modal-body" style={{ padding: '20px' }}>
                <ClosingEntryWidget />
              </div>
            </div>
          )}

          {activeWidget === 'api' && (
"""

if 'closing-entry-access' not in code.split('activeWidget === \'api\'')[0]:
    code = code.replace(old_api_render.strip(), new_closing_render.strip())

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/components/WidgetSettings/index.tsx', 'w') as f:
    f.write(code)

